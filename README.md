<img alt="password store logo" src="https://git.sr.ht/~ayushnix/pass-tessen/blob/master/images/pass-logo-128.png" align="right" width="128" height="128">

## pass-tessen

`pass-tessen` is a [password store][1] extension that uses a fuzzy data selection menu to copy
password store data while using a terminal. `pass-tessen` can open URLs in a web browser of your
choice, generate OTPs using [pass-otp][2], and copy all [valid key-value pair data][3] in a password
store file. The fuzzy data selection menu can be either [fzf][4], [skim][5], or [fzy][6].

If you want to autotype and copy password store and [gopass][21] data on Wayland wlroots compositors
like [sway][7], check out [tessen][8]. If you're using Xorg/X11 window managers, check out
[rofi-pass][9].

## Why use `pass-tessen`?

- unlike [pass-clip][10], `pass-tessen` can copy all valid key-value pair data in a password store
  file

  For example, if you have something like

  ```
  $ pass show mybank/username
  correct horse battery staple
  url: https://mybank.com
  credit card number: 1111 1111 1111 1111
  otpauth://totp/ACME%20Co:john@example.com?secret=HXDMVJECJJWSRB3HWIZR4IFUGFTMXBOZ&issuer=ACME%20Co&algorithm=SHA1&digits=6&period=30
  ```

  `pass-tessen` can copy the value of `credit card number` key

- `pass-tessen` can generate and copy OTPs if [pass-otp][2] is installed

- `pass-tessen` can open URLs using [xdg-open][11] or any other web browser of your choice

- `pass-tessen` can show a preview of your password store data before you select it

<picture>
  <source srcset="https://git.sr.ht/~ayushnix/pass-tessen/blob/master/images/preview-dark.jpg" media="(prefers-color-scheme: dark)" height="167" width="721">
  <img alt="pass-tessen preview showcase" src="https://git.sr.ht/~ayushnix/pass-tessen/blob/master/images/preview-light.jpg" height="168" width="720">
</picture>

- focuses on doing one thing well, copying password store data while using a terminal

- `pass-tessen` doesn't use any external dependencies unless absolutely necessary

  As a result, `pass-tessen` doesn't depend on commonly used utilities like coreutils, sed, awk, and
  find (although password store needs them).

- the code is linted using [shellcheck][12] and formatted using [shfmt][13]

- focuses on minimalism and security (please let me know if you have any suggestions for
  improvement)

## Installation

Before installing `pass-tessen`, make sure that the environment variable
`PASSWORD_STORE_ENABLE_EXTENSIONS` is set to `true`. This can be confirmed by executing,

```
env | grep PASSWORD_STORE_ENABLE_EXTENSIONS
```

If there's no output, add the following line in `~/.bash_profile` assuming you're using bash and
re-login.

```
export PASSWORD_STORE_ENABLE_EXTENSIONS=true
```

If this environment variable isn't set, password store extensions will not work. For more details,
please read the man page of `PASS(1)`.

### Dependencies

- [pass][1]
- at least one fuzzy data selection backend is needed - either [fzf][4], [skim][5], or [fzy][6]
- at least one copy paste program is needed - either [wl-clipboard][15] if you're using a Wayland
  compositor or [xclip][14] if you're using Xorg/X11
- [xdg-utils][11] (optional, if you want to open URLs using `xdg-open`)
- [pass-otp][2] (optional, if you want to generate and copy TOTP/HOTP)

### Arch Linux

`pass-tessen` is available in the [Arch User Repository][17].

### Git Release

```
git clone https://git.sr.ht/~ayushnix/pass-tessen
cd pass-tessen
sudo make install
```

You can also do `doas make install` if you're using [doas][18] on Linux, which you probably should.

### Stable Release

```
wget https://git.sr.ht/~ayushnix/pass-tessen/archive/v2.0.0.tar.gz
tar xvzf pass-tessen-2.0.0.tar.gz
cd pass-tessen-2.0.0
sudo make install
```

or, you know, `doas make install`.

## Usage

```
usage: pass tessen [-p|--preview] [-f|--fuzzy fuzzy_backend_program]
                   [-u|--userkey custom_username_key]
                   [-U|--urlkey custom_url_key]
                   [-w|--web-browser custom_web_browser] [-h|--help]
                   [-v|--version]

pass tessen                   find a fuzzy selection program and show pass data
pass tessen -p                show preview while selecting a pass file
pass tessen -p -f sk          use skim as fuzzy backend and show preview
pass tessen -f fzy            use fzy as fuzzy backend; doesn't support preview
pass tessen -u username       set 'username' as the custom username key
pass tessen -U URL            set 'URL' as the custom URL key
pass tessen -w qutebrowser    use qutebrowser to open URLs
pass tessen -h                show this help menu
pass tessen -v                show the version of pass tessen
```

## Assumptions

`pass-tessen` assumes that the data organization format in a password store file is the same as
mentioned on the [password store website][3]. If a key is not detected, please raise a ticket on a
git forge website of your choice where `pass-tessen` is hosted.

The `password` key is reserved in a case-insensitive manner to avoid confusion. The custom username
and URL keys are also checked in a case-insensitive manner and the first unique key is selected. If
a custom username key is not mentioned, `user` is assumed. If a custom URL key is not mentioned,
`url` is assumed. If a username key is not found, the basename of the selected password store
(without the `.gpg` extension) is considered as the username.

## What does `tessen` mean?

[Here you go.][20]

## Why did you choose this weird name?

Because obvious names like pass-fzf and pass-clip are already taken by other projects? Also, for
some reason, the way how FZF's UI instantly opens up and displays relevant information reminded me
of Japanese hand fans. I guess I was thinking of some anime while coming up with this name.

## Contributions

Please see the [CONTRIBUTING.md file][19].

[1]: https://www.passwordstore.org/
[2]: https://github.com/tadfisher/pass-otp
[3]: https://www.passwordstore.org/#organization
[4]: https://github.com/junegunn/fzf
[5]: https://github.com/lotabout/skim
[6]: https://github.com/jhawthorn/fzy
[7]: https://swaywm.org/
[8]: https://git.sr.ht/~ayushnix/tessen
[9]: https://github.com/carnager/rofi-pass
[10]: https://github.com/ibizaman/pass-clip
[11]: https://www.freedesktop.org/wiki/Software/xdg-utils/
[12]: https://github.com/koalaman/shellcheck
[13]: https://github.com/mvdan/sh
[14]: https://github.com/astrand/xclip
[15]: https://github.com/bugaevc/wl-clipboard
[16]: https://github.com/YaLTeR/wl-clipboard-rs
[17]: https://aur.archlinux.org/packages/pass-tessen/
[18]: https://github.com/Duncaen/OpenDoas
[19]: https://git.sr.ht/~ayushnix/pass-tessen/tree/master/item/CONTRIBUTING.md
[20]: https://en.wikipedia.org/wiki/Japanese_war_fan
[21]: https://github.com/gopasspw/gopass
