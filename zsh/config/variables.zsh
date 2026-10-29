# One copy of each folder: nested shells prepend and append again.
typeset -U path

export HOMEBREW_NO_AUTO_UPDATE=1

# Homebrew first, so the tools below are found in its bin.
[[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"

# GO
if (( $+commands[go] )); then
  export GO111MODULE=on
  export GOPATH=$(go env GOPATH)
  export PATH=$PATH:$GOPATH/bin
fi

# JAVA
export SDKMAN_DIR="$HOME/.sdkman"
if [[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]]; then
  # sdkman-init adds a candidate only when PATH lacks it, so an inherited copy
  # that path_helper put behind /usr/bin would stay there.
  path=(${path:#$SDKMAN_DIR/candidates/*})
  source "$SDKMAN_DIR/bin/sdkman-init.sh"
  export JAVA_HOME="$SDKMAN_DIR/candidates/java/current"
fi

# ANDROID SDK
if [[ -d $HOME/Library/Android/sdk ]]; then
  export ANDROID_HOME=$HOME/Library/Android/sdk
  export PATH=$PATH:$ANDROID_HOME/emulator
  export PATH=$PATH:$ANDROID_HOME/platform-tools
  export PATH=$PATH:$ANDROID_HOME/tools
  export PATH=$PATH:$ANDROID_HOME/tools/bin
fi

# fnm
(( $+commands[fnm] )) && eval "$(fnm env --use-on-cd)"
