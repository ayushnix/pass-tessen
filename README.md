## pass-tessen

A [pass](https://www.passwordstore.org/) extension that uses [fzf](https://github.com/junegunn/fzf)
to select and copy password store data.

If you want to autotype and copy password-store data, similar to how
[rofi-pass](https://github.com/carnager/rofi-pass) works, check out
[tessen](https://github.com/ayushnix/tessen).

`pass-tessen` will automatically use the following environment variables if they're set or assume
reasonable defaults if not.

- `PASSWORD_STORE_DIR` (the default location of your password store)
- `PASSWORD_STORE_CLIP_TIME` (the amount of time for which password-store data stays on the
  clipboard)

## Installation

Before installing `pass-tessen`, make sure you've added the following line in `~/.bash_profile` or
an equivalent file and have logged out and logged back in.

```
export PASSWORD_STORE_ENABLE_EXTENSIONS=true
```

Password Store extensions will not work if this environment variable isn't set.

### Dependencies

- [pass](https://git.zx2c4.com/password-store/)
- [fzf](https://github.com/junegunn/fzf)
- [xclip](https://github.com/astrand/xclip) (if you're using X11/Xorg)
- [wl-clipboard](https://github.com/bugaevc/wl-clipboard) or
  [wl-clipboard-rs](https://github.com/YaLTeR/wl-clipboard-rs) (if you're using Wayland)

### Arch Linux

`pass-tessen` is available in the [Arch User
Repository](https://aur.archlinux.org/packages/pass-tessen/).

### Git Release

```
git clone https://github.com/ayushnix/pass-tessen.git
cd pass-tessen
sudo make install
```

You can also do `doas make install` if you're using [doas](https://github.com/Duncaen/OpenDoas),
which you probably should.

### Stable Release

```
wget https://github.com/ayushnix/pass-tessen/releases/download/v1.5.0/pass-tessen-1.5.0.tar.gz
tar xvzf pass-tessen-1.5.0.tar.gz
cd pass-tessen-1.5.0
sudo make install
```

or, you know, `doas make install`.

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

## Assumptions

`pass-tessen` works under several assumptions and tries to fail gracefully if they are not met.
Please report any unexpected behavior.

The data organization format is assumed to be the same as mentioned on this
[page](https://www.passwordstore.org/). If valid key-value pairs aren't found, `pass-tessen` will
not show them.

It is assumed that the name of the file itself is the username. For example, if you have a file
`bank/mybankusername.gpg` in your password store, the assumed default username is `mybankusername`.
However, if a valid username key value pair is present inside the file, `pass-tessen` will show them
for selection as well.

If there are multiple non-unique keys, the value of the last key will be considered.

## What does `tessen` mean?

[Here](https://en.wikipedia.org/wiki/Japanese_war_fan) you go.

## Why did you choose this weird name?

Because obvious names like pass-fzf and pass-clip are already taken by other projects? Also, for
some reason, the way how FZF's UI instantly opens up and displays relevant information reminded me
of Japanese hand fans. I guess I was thinking of some anime while coming up with this name.

## Contributions

Please see [this](https://github.com/ayushnix/pass-tessen/blob/master/CONTRIBUTING.md) file.
