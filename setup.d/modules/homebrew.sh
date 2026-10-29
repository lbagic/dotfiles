# about: Installs Homebrew if it is missing (with Apple's Command Line Tools, about 2 GB).
# why: The package manager apps-common installs with.

HOMEBREW_INSTALLER=https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh

brew_state() {
  local b v
  if ! b=$(brew_path); then
    echo absent
    return 1
  fi
  v=$(HOMEBREW_NO_AUTO_UPDATE=1 "$b" --version 2>/dev/null | head -1)
  echo "${v:-Homebrew} at ${b%/bin/brew}"
}

# The installer refuses to run as root; NONINTERACTIVE makes it use the sudo
# timestamp the runner caches instead of asking for a password itself.
# `bash -c "$(curl …)"` would exit 0 on a failed download, so it is fetched to
# a file first, and success means brew is there afterwards.
install_homebrew() {
  local f="$SETUP_RUN/homebrew-install.sh"
  curl -fsSL "$HOMEBREW_INSTALLER" -o "$f" || return 1
  if [ ! -s "$f" ]; then
    echo 'the Homebrew installer download is empty' >&2
    return 1
  fi
  NONINTERACTIVE=1 /bin/bash "$f" || return 1
  if ! brew_path >/dev/null; then
    echo 'the installer finished, but brew is in neither /opt/homebrew nor /usr/local' >&2
    return 1
  fi
}

step -tty -admin -settarget 'install (~2 GB: Command Line Tools ~1.6 GB + Homebrew ~0.3 GB)' \
  Homebrew brew_state installed install_homebrew \
  'print:Homebrew stays installed. To remove it: /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)"'
