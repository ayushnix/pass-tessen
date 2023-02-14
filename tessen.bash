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

# list of variables inherited from password-store.sh used in this extension
# PREFIX    - the location of password store
# CLIP_TIME - the time for which data should be kept in the clipboard
# PROGRAM   - the name of password-store, pass

# initialize global variables
readonly tsn_version="2.0.0"
declare tsn_passfile fz_backend tsn_password tsn_username tsn_userkey tsn_urlkey
declare tsn_url tsn_otp chosen_key tsn_web_browser fz_preview
declare -a fz_backend_opts
declare -A tsn_passdata
tsn_otp=false
tsn_userkey="user"
tsn_urlkey="url"

# FIRST MENU: generate list of password store files and let user select one
get_pass_file() {
  local -a tmp_pass_files

  shopt -s nullglob globstar
  tmp_pass_files=("$PREFIX"/**/*.gpg)
  tmp_pass_files=("${tmp_pass_files[@]#"$PREFIX"/}")
  tmp_pass_files=("${tmp_pass_files[@]%.gpg}")
  shopt -u nullglob globstar

  # fzy doesn't support previewing selected data
  if [[ $fz_preview == "true" ]] && [[ $fz_backend != "fzy" ]]; then
    tsn_passfile="$(printf "%s\n" "${tmp_pass_files[@]}" \
      | "$fz_backend" "${fz_backend_opts[@]}" --preview='pass show {}')"
  else
    tsn_passfile="$(printf "%s\n" "${tmp_pass_files[@]}" \
      | "$fz_backend" "${fz_backend_opts[@]}")"
  fi

  if ! [[ -f "$PREFIX/$tsn_passfile".gpg ]]; then
    _die "error: input not received or selected file not found"
  fi

  unset -v tmp_pass_files
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
  for idx in "${passdata[@]}"; do
    key="${idx%%:*}"
    val="${idx#*: }"
    if [[ ${key,,} == "password" ]]; then
      continue
    elif [[ $idx =~ $otp_regex ]] && [[ $tsn_otp == "false" ]]; then
      tsn_otp=true
    elif [[ $idx =~ $keyval_regex ]] && [[ ${key,,} =~ ^$tsn_userkey$ ]] && [[ -z $tsn_username ]]; then
      tsn_userkey="${key,,}"
      tsn_username="$val"
    elif [[ $idx =~ $keyval_regex ]] && [[ ${key,,} =~ ^$tsn_urlkey$ ]] && [[ -z $tsn_url ]]; then
      tsn_urlkey="${key,,}"
      tsn_url="$val"
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
          || _die "error: unable to open URL using $tsn_web_browser" &
        printf "%s\n" "URL has been opened in $tsn_web_browser"
      elif is_installed xdg-open; then
        xdg-open "$tsn_url" > /dev/null 2>&1 \
          || _die "error: unable to open URL using xdg-open" &
        printf "%s\n" "URL has been opened using xdg-open"
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
    tsn_clip_cmd=(wl-copy --trim-newline)
    tsn_clip_args=(--clear)
  else
    tsn_clip_cmd=(xclip -selection clipboard -rmlastnl)
    tsn_clip_args=(-i /dev/null)
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

  unset -v fz_prog idx

  init_fz_backend
}

# initialize the default options for the fuzzy selection backend program
init_fz_backend() {
  case "$fz_backend" in
    fzf)
      if [[ -z $FZF_DEFAULT_OPTS ]]; then
        fz_backend_opts=(--no-multi --height=30 --no-info --prompt='pass: ' --reverse)
      fi
      ;;
    sk)
      if [[ -z $SKIM_DEFAULT_OPTIONS ]]; then
        fz_backend_opts=(--no-multi --height=30 --prompt='pass: ' --reverse)
      fi
      ;;
    fzy) fz_backend_opts=(--lines=20 --prompt='pass: ') ;;
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
  printf "%s" "\
$PROGRAM tessen - a fuzzy data selection interface for pass

usage: $PROGRAM tessen [-p|--preview] [-f|--fuzzy fuzzy_backend_program]
                       [-u|--userkey custom_username_key]
                       [-U|--urlkey custom_url_key]
                       [-w|--web-browser custom_web_browser] [-h|--help]
                       [-v|--version]

$PROGRAM tessen                find a fuzzy selection program and show pass data
$PROGRAM tessen -p             show preview while selecting a pass file
$PROGRAM tessen -p -f sk       use skim as fuzzy backend and show preview
$PROGRAM tessen -f fzy         use fzy as fuzzy backend; doesn't support preview
$PROGRAM tessen -u username    set 'username' as the custom username key
$PROGRAM tessen -U URL         set 'URL' as the custom URL key
$PROGRAM tessen -w qutebrowser use qutebrowser to open URLs
$PROGRAM tessen -h             show this help menu
$PROGRAM tessen -v             show the version of pass tessen

if no fuzzy selection program is specified, $PROGRAM tessen looks for either
one of fzf, skim, and fzy in the order specified. please note that fzy
doesn't support showing previews as of fzy version 1.0. to specify options for
fzf and skim, use

FZF_DEFAULT_OPTS=\"--height 20 --prompt='pass: ' --reverse\" pass tessen
SKIM_DEFAULT_OPTIONS=\"--height 20 --prompt='pass: ' --reverse\" pass tessen -f sk

the default username key is 'user' and the default URL key is 'url'.

if a custom web browser value is provided, $PROGRAM tessen uses it otherwise,
it falls back to using xdg-open. xdg-open is an optional dependency.

$PROGRAM tessen uses red color to show error messages. To disable using red
color, use the $NO_COLOR environment variable and set its value to anything you
like (true, 1, yes).

for reporting bugs or feedback, visit one of the following git forge providers
https://sr.ht/~ayushnix/pass-tessen
https://codeberg.org/ayushnix/pass-tessen
https://github.com/ayushnix/pass-tessen
"
}

while [[ $# -gt 0 ]]; do
  tsn_opt="$1"
  case "$tsn_opt" in
    -p | --preview)
      readonly fz_preview=true
      ;;
    -f | --fuzzy)
      if [[ $# -lt 2 ]]; then
        _die "error: please specify a valid fuzzy selection backend"
      fi
      if ! is_installed "$2"; then
        _die "error: $2 is not installed"
      fi
      readonly fz_backend="$2"
      init_fz_backend
      shift
      ;;
    -u | --userkey)
      if [[ $# -lt 2 ]]; then
        _die "error: please specify a custom username key"
      fi
      tsn_userkey="$2"
      shift
      ;;
    -U | --urlkey)
      if [[ $# -lt 2 ]]; then
        _die "error: please specify a custom URL key"
      fi
      tsn_urlkey="$2"
      shift
      ;;
    -w | --web-browser)
      if [[ $# -lt 2 ]]; then
        _die "error: please specify the web browser to use for opening URLs"
      fi
      if ! is_installed "$2"; then
        _die "error: $2 is not installed"
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

if [[ -z $fz_backend ]]; then
  find_fz_backend
fi

get_pass_file
get_pass_data
get_key
key_action
