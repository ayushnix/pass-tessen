#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2021 Ayush Agarwal <ayush at fastmail dot in>
#
# pass tessen - Password Store Extension (https://www.passwordstore.org)
# a fuzzy data selection interface for pass using fzf
# ------------------------------------------------------------------------------

# password-store.sh doesn't use nounset, we will
set -u

# don't leak password data if debug mode is enabled
set +x

# list of variables inherited from password-store.sh used in this extension
# PREFIX    - the location of password store
# CLIP_TIME - the time for which data should be kept in the clipboard
# PROGRAM   - the name of password-store, pass

# initialize the global variables
TSN_VERSION="1.3.0"
TSN_PASSFILE=""
declare -A TSN_PASSDATA_ARR
TSN_USERNAME=""
TSN_PASSWORD=""
TSN_KEY=""
TSN_CLIP_CMD=""
TSN_CLIP_CMD_ARGS=()
TSN_CLIP_CMD_CLEAR_ARGS=()
TSN_FZF_PRV=false

# set the default fzf options
fzf_opt=("--no-multi --height=50 --info=hidden --prompt='pass: ' --layout=reverse")
FZF_DEFAULT_OPTS="${fzf_opt[*]-}"
export FZF_DEFAULT_OPTS
unset -v fzf_opt

# display and get the shortened path of the password file
tsn_get_pass_file() {
  local tmp_pass_1 tmp_pass_2 tmp_pass_3

  # temporarily enable globbing to get the list of gpg files
  shopt -s nullglob globstar
  tmp_pass_1=("$PREFIX"/**/*.gpg)
  tmp_pass_2=("${tmp_pass_1[@]#"$PREFIX"/}")
  tmp_pass_3=("${tmp_pass_2[@]%.gpg}")
  shopt -u nullglob globstar

  if "$TSN_FZF_PRV"; then
    TSN_PASSFILE="$(printf '%s\n' "${tmp_pass_3[@]}" | fzf --preview='pass {}')"
  else
    TSN_PASSFILE="$(printf '%s\n' "${tmp_pass_3[@]}" | fzf)"
  fi

  if ! [[ -e "$PREFIX/$TSN_PASSFILE".gpg ]]; then
    exit 1
  fi
}

# get the password data including every key-value pair inside the encrypted file
tsn_get_pass_data() {
  local passdata passdata_regex idx key val

  mapfile -t passdata < <(pass "$TSN_PASSFILE")
  # ASSUMPTION: the key can contain alphanumerics, spaces, hyphen, underscore
  #             the value can contain anything but it has to follow after a space
  passdata_regex="^[[:alnum:][:blank:]_-]+:[[:blank:]].+$"
  # ASSUMPTION: the basename of the gpg file is the username although one can still
  #             select a username field inside the file, if it exists
  TSN_USERNAME="${TSN_PASSFILE##*/}"
  # ASSUMPTION: the first line of $PASSFILE will contain the password
  TSN_PASSWORD="${passdata[0]}"

  # skip the password, validate each entry against $passdata_regex, store valid results
  # ASSUMPTION: each key is unique otherwise, the value of the last non-unique key will be used
  for idx in "${passdata[@]:1}"; do
    if [[ "$idx" =~ $passdata_regex ]]; then
      key="${idx%%:*}"
      val="${idx#*: }"
      TSN_PASSDATA_ARR["$key"]="$val"
    else
      continue
    fi
  done
}

# the menu for selecting and copying the decrypted data
tsn_menu() {
  local ch flag key_arr
  flag=false
  key_arr=("username" "password" "${!TSN_PASSDATA_ARR[@]}")

  TSN_KEY="$(printf '%s\n' "${key_arr[@]}" | fzf)"

  # although fzf doesn't seem to accept invalid input, we'll still validate it
  for ch in "${key_arr[@]}"; do
    if [[ "$TSN_KEY" == "$ch" ]]; then
      flag=true
      break
    fi
  done
  if ! "$flag"; then
    exit 1
  fi

  if [[ "$TSN_KEY" == "username" ]]; then
    tsn_clip "$TSN_USERNAME"
    printf '%s\n' "Copied username to clipboard. Will clear in $CLIP_TIME seconds."
    tsn_clean
  elif [[ "$TSN_KEY" == "password" ]]; then
    tsn_clip "$TSN_PASSWORD"
    printf '%s\n' "Copied password to clipboard. Will clear in $CLIP_TIME seconds."
    tsn_clean
  elif [[ -n "${TSN_PASSDATA_ARR[$TSN_KEY]}" ]]; then
    tsn_clip "${TSN_PASSDATA_ARR[$TSN_KEY]}"
    printf '%s\n' "Copied '$TSN_KEY' to clipboard. Will clear in $CLIP_TIME seconds."
    tsn_clean
  else
    exit 1
  fi
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
  printf '%s\n' "$PROGRAM ${0##*/} - a fuzzy data selection interface for pass"
  printf '%s\n' "Usage: $PROGRAM ${0##*/} [-p|--preview] [-h|--help] [-v|--version]"
  printf '\t%s\n' "-p, --preview: show preview of password data"
  printf '\t%s\n' "-h, --help:    print this help menu"
  printf '\t%s\n' "-v, --version: print the version of $PROGRAM ${0##*/}"
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
      printf '%s\n' "$PROGRAM ${0##*/} version $TSN_VERSION"
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
