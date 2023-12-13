#!/usr/bin/env zsh

# Let aliases be sudo'ed
alias sudo="sudo "
alias python="python3"

# Detect which `ls` flavor is in use
if ls --color > /dev/null 2>&1; then
  colorflag="--color"
else
  colorflag="-G"
fi

# basic shortcuts
alias ~~="cd ~"
alias cl="clear"
alias c="code ."
alias e="open ."
alias q="exit"
alias r="clear; exec zsh -l"
# alias reload="source ~/.zshrc"
alias run="npm run"
alias dev="npm run dev"
alias npmlg="npm list -g --depth=0"

alias chosts="code /private/etc/hosts"
alias cssh="code ~/.ssh/config"
alias cgit="code ~/.gitconfig"

function myip() {
  echo "public - $(curl -s ifconfig.me)"
  echo "private - $(ifconfig | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}')"
}


## some OS dependent aliases ##
if [[ $OSTYPE == linux-* ]]; then
    alias update='sudo apt update'
    alias upgrade='sudo apt -y upgrade; sudo apt autoremove'
    alias ins='sudo apt install'
    alias rem='sudo apt remove'
    alias open='xdg-open'
    alias ll='ls -lha --color'
    alias cpuhogs='ps -Ao pcpu,pmem,comm,comm,pid --sort=-pcpu | head -n 6'
    alias copy='xclip -sel clip'
    alias paste='xclip -sel clip -o'
elif [[ $OSTYPE == darwin* ]]; then
    alias update='brew update'
    alias ins="osx_ins"
    alias ll='ls -lha'
    function upgrade() {
        # check for permissions
        if [[ "$(stat -f '%u' $(brew --prefix))" != "$(id -u)" || "$(stat -f '%u' /usr/local/bin)" != "$(id -u)"  ]];then
            echo "$(brew --prefix)/* is not owned by $(whoami)"
            sudo chown -R $(whoami):admin $(brew --prefix)/*
        fi
        # run upgrades
        brew upgrade
        brew cleanup
    }
    alias cpuhogs='ps -Aro pcpu,pmem,comm,comm,pid  | head -n 6'
    alias copy='pbcopy'
    alias paste='pbpaste'
fi

# find files fast
# unalias ff
# unalias fd
function ff () {
    find . -iname "*$@*" ;
}

# ram usage counter.
# Credit: https://github.com/nikitavoloboev/dotfiles/blob/master/zsh/functions/functions.zsh#L480
function ram() {
    local sum
    local items
    local app="$1"
    if [ -z "$app" ]; then
        echo "First argument - pattern to grep from processes"
    else
        sum=0
        for i in `ps aux | grep -i "$app" | grep -v "grep" | awk '{print $6}'`; do
            sum=$(($i + $sum))
        done
        sum=$(echo $sum | awk '{ split( "KB MB GB TB" , v ); s=1; while( $1>1024 ){ $1/=1024; s++ } printf("%0.2f %s", $1, v[s]) }')
        # sum=$(echo "scale=2; $sum / 1024.0" | bc)
        if [[ $sum != "0.00 KB" ]]; then
            echo "${fg[blue]}${app}${reset_color} uses ${fg[green]}${sum}s${reset_color} of RAM."
        else
            echo "There are no processes with pattern '${fg[blue]}${app}${reset_color}' are running."
        fi
    fi
}


# checks for existence of binary
# use in scripts like so: if (! exists "foo"); then echo "doesn't exist";fi
# https://www.topbug.net/blog/2016/10/11/speed-test-check-the-existence-of-a-command-in-bash-and-zsh/
function exists(){
  if [[ -z "$1" ]]; then
    echo "Usage: exists cmd_name"
    exit 1
  fi
  (( $+commands[$1] ))
  return $?
}



# if 'bat' exists on system, enhance cat.
if (exists bat);then
  alias cat='bat --style=plain --paging=never'
fi