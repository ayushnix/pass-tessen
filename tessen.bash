#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (C) 2021 Ayush Agarwal <ayushnix at fastmail dot com>
#
# vim: set expandtab ts=2 sw=2 sts=2:
#
# pass tessen - Password Store Extension (https://www.passwordstore.org)
# a fuzzy data selection interface for pass using fzf
# ------------------------------------------------------------------------------

# disable debug mode to prevent leaking sensitive password store data
set +x

# initialize global variables
readonly tsn_version="2.0.0"
declare tsn_passfile fz_backend tsn_password tsn_username tsn_userkey tsn_urlkey
declare tsn_url tsn_otp chosen_key
declare -a fz_backend_opts
declare -A tsn_passdata
tsn_otp=false
tsn_userkey="user"
tsn_url="url"

# FIRST MENU: generate list of password store files and let user select one
get_pass_file() {
  local tmp_prefix="${PREFIX:-$PASSWORD_STORE_DIR}"
  if ! [[ -d $tmp_prefix ]]; then
    _die "error: password store directory not found"
  fi

  local -a tmp_pass_files
  shopt -s nullglob globstar
  tmp_pass_files=("$tmp_prefix"/**/*.gpg)
  tmp_pass_files=("${tmp_pass_files[@]#"$tmp_prefix"/}")
  tmp_pass_files=("${tmp_pass_files[@]%.gpg}")
  shopt -u nullglob globstar

  tsn_passfile="$(printf "%s\n" "${tmp_pass_files[@]}" \
    | "$fz_backend" "${fz_backend_opts[@]}")"

  if ! [[ -f "$tmp_prefix/$tsn_passfile".gpg ]]; then
    _die "error: the selected file was not found"
  fi

  unset -v tmp_pass_files tmp_prefix
}

# parse the selected password store file in the FIRST MENU
get_pass_data() {
  local -a passdata

  mapfile -t passdata < <(pass show "$tsn_passfile" 2> /dev/null)
  if [[ ${#passdata[@]} -eq 0 ]]; then
    _die "error: $tsn_passfile is empty"
  fi

  local keyval_regex
  keyval_regex='^[[:alnum:][:blank:]+#@_-]+:[[:blank:]].+$'

  local otp_regex
  # this regex is borrowed from pass-otp at commit 3ba564c
  otp_regex='^otpauth:\/\/(totp|hotp)(\/(([^:?]+)?(:([^:?]*))?)(:([0-9]+))?)?\?(.+)$'

  tsn_password="${passdata[0]}"

  local key val idx
  # we've assumed that keys are unique and if they aren't, the first non-unique
  # key will be considered and other non-unique keys will be ignored
  # this has been done to improve performance and eliminate ambiguity
  for idx in "${passdata[@]:1}"; do
    key="${idx%%:*}"
    val="${idx#*: }"
    if [[ ${key,,} == "password" ]]; then
      continue
    elif [[ ${key,,} =~ ^$tsn_userkey$ ]] && [[ -z $tsn_username ]]; then
      tsn_userkey="${key,,}"
      tsn_username="$val"
    elif [[ ${key,,} =~ ^$tsn_urlkey$ ]] && [[ -z $tsn_url ]]; then
      tsn_urlkey="${key,,}"
      tsn_url="$val"
    elif [[ $idx =~ $otp_regex ]] && [[ $tsn_otp == "false" ]]; then
      tsn_otp=true
    elif [[ $idx =~ $keyval_regex ]] && [[ -z ${tsn_passdata["$key"]} ]]; then
      tsn_passdata["$key"]="$val"
    fi
  done

  # if a user key isn't found, assume that the basename of the selected file is
  # the username
  # this is mentioned because the value of the username key cannot be blank and
  # this acts like a sensible fallback option
  if [[ -z $tsn_username ]]; then
    tsn_username="${tsn_passfile##*/}"
  fi

  unset -v passdata keyval_regex otp_regex key val idx
}

# SECOND MENU: generate a menu with a list of keys present in the selected file
# in the FIRST MENU
get_key() {
  local -a key_arr

  if [[ $tsn_otp == "false" ]] && [[ -z $tsn_url ]]; then
    key_arr=("$tsn_userkey" "password" "${!tsn_passdata[@]}")
  elif [[ $tsn_otp == "false" ]] && [[ -n $tsn_url ]]; then
    key_arr=("$tsn_userkey" "password" "$tsn_urlkey" "${!tsn_passdata[@]}")
  elif [[ $tsn_otp == "true" ]] && [[ -z $tsn_url ]]; then
    key_arr=("$tsn_userkey" "password" "otp" "${!tsn_passdata[@]}")
  elif [[ $tsn_otp == "true" ]] && [[ -n $tsn_url ]]; then
    key_arr=("$tsn_userkey" "password" "otp" "$tsn_urlkey" "${!tsn_passdata[@]}")
  fi

  chosen_key="$(printf "%s\n" "${key_arr[@]}" | "$fz_backend" "${fz_backend_opts[@]}")"

  local ch flag=false
  for ch in "${key_arr[@]}"; do
    if [[ $chosen_key == "$ch" ]]; then
      flag=true
      break
    fi
  done
  if [[ $flag == "false" ]]; then
    _die "error: the chosen key doesn't exist"
  fi

  unset -v key_arr ch flag
}

# copy the selected key
# if OTP is selected, use pass-otp to generate and copy a OTP
# if URL is selected, open it using `xdg-open` or a configurable browser value
# I don't expect invalid input in $chosen_key which is why the case statement
# doesn't account for invalid values in this subroutine
key_action() {
  local tmp_otp

  case "$chosen_key" in
    otp)
      if ! pass otp -h > /dev/null 2>&1; then
        _die "error: pass-otp is not installed"
      fi
      tmp_otp="$(pass otp "$tsn_passfile")"
      if ! [[ $tmp_otp =~ ^[[:digit:]]+$ ]]; then
        _die "error: invalid OTP detected"
      fi
      tsn_clip "$tmp_otp"
      ;;
    "$tsn_urlkey")
      if [[ -n $tsn_web_browser ]]; then
        "$tsn_web_browser" "$tsn_url" > /dev/null 2>&1 \
          || _die "error: unable to open URL using $tsn_web_browser"
      elif is_installed xdg-open; then
        xdg-open "$tsn_url" > /dev/null 2>&1 \
          || _die "error: unable to open URL using xdg-open"
      else
        _die "error: unable to open URL"
      fi
      ;;
    "$tsn_userkey") tsn_clip "$tsn_username" ;;
    password) tsn_clip "$tsn_password" ;;
    *) tsn_clip "${tsn_passdata[$chosen_key]}" ;;
  esac

  unset -v tmp_otp
}

# copy the password store data using either xclip (X11) or wl-copy (Wayland)
tsn_find_clip_cmd() {
  if [[ -n "$WAYLAND_DISPLAY" || "$XDG_SESSION_TYPE" == "wayland" ]]; then
    TSN_CLIP_CMD="wl-copy"
    TSN_CLIP_CMD_CLEAR_ARGS=("--clear")
  elif [[ "$XDG_SESSION_TYPE" == "x11" || -n "$DISPLAY" ]]; then
    TSN_CLIP_CMD="xclip"
    TSN_CLIP_CMD_ARGS=("-selection" "clipboard")
    TSN_CLIP_CMD_CLEAR_ARGS=("-i" "/dev/null")
  else
    printf '%s\n' "Error: No X11 or Wayland display detected" >&2
    exit 1
  fi
}

# function to copy the password
tsn_clip() {
  if [[ -n "$WAYLAND_DISPLAY" || "$XDG_SESSION_TYPE" == "wayland" ]]; then
    printf '%s' "${1-}" | "$TSN_CLIP_CMD"
  elif [[ "$XDG_SESSION_TYPE" == "x11" || -n "$DISPLAY" ]]; then
    printf '%s' "${1-}" | "$TSN_CLIP_CMD" "${TSN_CLIP_CMD_ARGS[*]-}"
  else
    printf '%s\n' "Error: No X11 or Wayland display detected" >&2
    exit 1
  fi
  shift
}

# copy the password, wait for CLIP_TIME seconds, clear the clipboard, and exit
tsn_clean() {
  {
    sleep "$CLIP_TIME" || exit 1
    "$TSN_CLIP_CMD" "${TSN_CLIP_CMD_ARGS[*]-}" "${TSN_CLIP_CMD_CLEAR_ARGS[*]-}"
  } > /dev/null 2>&1 &
  disown
  unset -v TSN_PASSFILE TSN_USERNAME TSN_PASSWORD TSN_PASSDATA_ARR TSN_KEY
}

# function for performing cleanup jobs on errors
tsn_die() {
  "$TSN_CLIP_CMD" "${TSN_CLIP_CMD_ARGS[*]-}" "${TSN_CLIP_CMD_CLEAR_ARGS[*]-}"
  unset -v TSN_PASSFILE TSN_USERNAME TSN_PASSWORD TSN_PASSDATA_ARR TSN_KEY
}

# the help menu
tsn_help() {
  printf '%s\n' "$PROGRAM tessen - a fuzzy data selection interface for pass"
  printf '%s\n' "Usage: $PROGRAM tessen [-p|--preview] [-h|--help] [-v|--version]"
  printf '\t%s\n' "-p, --preview: show preview of password data"
  printf '\t%s\n' "-h, --help:    print this help menu"
  printf '\t%s\n' "-v, --version: print the version of $PROGRAM tessen"
  printf '%s\n' "For more details, visit https://github.com/ayushnix/pass-tessen"
}

while [[ "$#" -gt 0 ]]; do
  tsn_opt="${1-}"
  case "$tsn_opt" in
    -p | --preview)
      TSN_FZF_PRV=true
      ;;
    -h | --help)
      tsn_help
      exit 0
      ;;
    -v | --version)
      printf '%s\n' "$PROGRAM tessen version $TSN_VERSION"
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      printf '%s\n' "Invalid argument received" >&2
      exit 1
      ;;
  esac
  shift
done
unset -v tsn_opt

tsn_find_clip_cmd
trap 'tsn_die' EXIT TERM
tsn_get_pass_file
tsn_get_pass_data
tsn_menu
trap - EXIT TERM
