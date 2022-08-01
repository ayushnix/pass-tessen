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
declare tsn_url tsn_otp chosen_key tsn_web_browser fz_preview
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

  if [[ $fz_preview == "true" ]] && [[ $fz_backend != "fzy" ]]; then
    tsn_passfile="$(printf "%s\n" "${tmp_pass_files[@]}" \
      | "$fz_backend" "${fz_backend_opts[@]}" --preview='pass show {}')"
  else
    tsn_passfile="$(printf "%s\n" "${tmp_pass_files[@]}" \
      | "$fz_backend" "${fz_backend_opts[@]}")"
  fi

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

# apparently, $XDG_SESSION_TYPE isn't reliable and can output `tty` instead of
# `wayland` or `x11` if a display manager isn't being used
tsn_clip() {
  local -a tsn_clip_cmd tsn_clip_args

  if [[ -n $WAYLAND_DISPLAY ]]; then
    tsn_clip_cmd=("wl-copy" "--trim-newline")
    tsn_clip_args=("--clear")
  else
    tsn_clip_cmd=("xclip" "-selection" "clipboard" "-rmlastnl")
    tsn_clip_args=("-i" "/dev/null")
  fi

  if [[ -n $1 ]]; then
    printf "%s" "$1" | "${tsn_clip_cmd[@]}"
    printf "%s\n" "data has been copied and will be cleared from the clipboard after $CLIP_TIME seconds"
    {
      sleep "$CLIP_TIME" || kill 0
      "${tsn_clip_cmd[@]}" "${tsn_clip_args[@]}"
    } > /dev/null 2>&1 &
  else
    _die "error: no data found for copying"
  fi

  unset -v tsn_clip_cmd tsn_clip_args
}

# find a fuzzy selection backend if not provided by the user and initialize
# settings for it
find_fz_backend() {
  if [[ -z $fz_backend ]]; then
    local -a fz_prog=('fzf' 'sk' 'fzy')
    local idx

    for idx in "${fz_prog[@]}"; do
      if is_installed "$idx"; then
        fz_backend="$idx"
        break
      fi
    done
  fi

  if [[ -z $fz_backend ]]; then
    _die "error: unable to find a fuzzy selection program"
  fi

  init_fz_backend

  unset -v fz_prog idx
}

init_fz_backend() {
  case "$fz_backend" in
    fzf)
      if [[ -z $FZF_DEFAULT_OPTS ]]; then
        fz_backend_opts=("--no-multi" "--height=50" "--no-info" "--prompt='pass: '" "--reverse")
      else
        fz_backend_opts=("${FZF_DEFAULT_OPTS[@]}")
      fi
      ;;
    sk)
      if [[ -z $SKIM_DEFAULT_OPTIONS ]]; then
        fz_backend_opts=("--no-multi" "--height=50" "--prompt='pass: '" "--reverse")
      else
        fz_backend_opts=("${SKIM_DEFAULT_OPTIONS[@]}")
      fi
      ;;
    fzy) fz_backend_opts=("--lines=20" "--prompt='pass: '") ;;
  esac
}

is_installed() {
  if command -v "$1" > /dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

_die() {
  if [[ -n $1 ]]; then
    if [[ -z $NO_COLOR ]]; then
      local red="\033[31m"
      local reset="\033[0m"
      printf "%b%s%b\n" "$red" "$1" "$reset" >&2
    else
      printf "%s\n" "$1" >&2
    fi
  fi
  exit 1
}

tsn_help() {
  printf '%s\n' "$PROGRAM tessen - a fuzzy data selection interface for pass"
  printf '%s\n' "Usage: $PROGRAM tessen [-p|--preview] [-h|--help] [-v|--version]"
  printf '\t%s\n' "-p, --preview: show preview of password data"
  printf '\t%s\n' "-h, --help:    print this help menu"
  printf '\t%s\n' "-v, --version: print the version of $PROGRAM tessen"
  printf '%s\n' "For more details, visit https://github.com/ayushnix/pass-tessen"
}

while [[ $# -gt 0 ]]; do
  tsn_opt="$1"
  case "$tsn_opt" in
    -p | --preview)
      readonly fz_preview=true
      ;;
    -f | --fuzzy)
      if [[ $# -lt 2 ]] || ! is_installed "$2"; then
        _die "error: please specify a valid fuzzy selection backend"
      fi
      readonly fz_backend="$2"
      init_fz_backend
      shift
      ;;
    -u | --userkey)
      if [[ $# -lt 2 ]]; then
        _die "error: please specify a custom username key"
      fi
      readonly tsn_userkey="$2"
      shift
      ;;
    -U | --urlkey)
      if [[ $# -lt 2 ]]; then
        _die "error: please specify a custom URL key"
      fi
      readonly tsn_urlkey="$2"
      shift
      ;;
    -w | --web-browser)
      if [[ $# -lt 2 ]]; then
        _die "error: please specify the web browser to use for opening URLs"
      fi
      readonly tsn_web_browser="$2"
      shift
      ;;
    -h | --help)
      tsn_help
      exit 0
      ;;
    -v | --version)
      printf "%s\n" "$PROGRAM tessen version $tsn_version"
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *) _die "error: invalid option detected" ;;
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
