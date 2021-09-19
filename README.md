# pass-tessen

A [pass](https://www.passwordstore.org/) extension that uses [fzf](https://github.com/junegunn/fzf)
to select and copy password store data.

If you want to autotype and copy password-store data, similar to how
[rofi-pass](https://github.com/carnager/rofi-pass) works, check out
[tessen](https://github.com/ayushnix/tessen).

## Dependencies

- [pass](https://git.zx2c4.com/password-store/)
- [bash](https://www.gnu.org/software/bash/bash.html)
- [fzf](https://github.com/junegunn/fzf)
- [xclip](https://github.com/astrand/xclip) (if you're using X11/Xorg)
- [wl-clipboard](https://github.com/bugaevc/wl-clipboard) or
  [wl-clipboard-rs](https://github.com/YaLTeR/wl-clipboard-rs) (if you're using Wayland)

## Usage

```
Usage: pass tessen [-p|--preview] [-h|--help] [-v|--version]
        -p, --preview: show preview of password data
        -h, --help:    print this help menu
        -v, --version: print the version of pass tessen
```

## Why should I use this instead of [pass-clip](https://github.com/ibizaman/pass-clip)?

- pass-tessen can copy other key-value pair data, not just passwords

  For example, if you have something like

  ```
  $ pass show mybank/username
  correct horse battery staple
  url: https://mybank.com
  credit card number: 1111 1111 1111 1111
  ```

  pass tessen can copy your `username`, `url`, and `credit card number` as well

- pass-tessen can show a preview of your password-store data before you select it

  just use `pass tessen -p` to see a preview of your password store data before you make a selection
- focuses on doing one thing well, copying password store data as conveniently and quickly as
  possible while using a terminal
- you don't need `sed`, `find`, GNU coreutils, or anything else besides what's mentioned above to
  run pass-tessen (although `pass` needs all of those binaries)
- the code is linted using [shellcheck](https://github.com/koalaman/shellcheck) and formatted using
  [shfmt](https://github.com/mvdan/sh)
- focuses on minimalism and security (please let me know if you have any suggestions for
  improvement)

## What does `tessen` mean?

[Here](https://en.wikipedia.org/wiki/Japanese_war_fan) you go.

## Why did you choose this weird name?

Because obvious names like pass-fzf and pass-clip are already taken by other projects? Also, for
some reason, the way how FZF's UI instantly opens up and displays relevant information reminded me
of Japanese hand fans. I guess I was thinking of some anime while coming up with this name.
