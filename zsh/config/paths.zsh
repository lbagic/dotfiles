SYSTEM="/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin"

# Homebrew 3.0
BREW="/opt/homebrew/bin"

# export final result
export PATH="$USER_BIN:$BREW:$SYSTEM"

# fnm
eval "$(fnm env --use-on-cd)"

# homebrew
eval "$(/opt/homebrew/bin/brew shellenv)"