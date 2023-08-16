# Dotfiles

## Full install

Install Software Updates and Xcode Command Line Tools

```sh
sudo softwareupdate -i -a
xcode-select --install
softwareupdate --install-rosetta
```

Clone Dotfiles

```sh
git clone git@github.com:lbagic/dotfiles.git .dotfiles
cd .dotfiles
```

Setup System Settings

```sh
./setup-mac/setup
```

Install Software & Applications

```sh
./setup-homebrew/setup
```

Setup Symlinks

```sh
./install
```
