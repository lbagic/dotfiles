#!/usr/bin/env zsh

# vim:ft=zsh
alias g="git"
alias glog="git log --decorate --oneline --graph --color=always --pretty=format:'%C(auto)%h%C(auto)%d %s %C(cyan)(%aN, %cr)'"
alias gloga="glog --all"
alias gp="git push origin HEAD"
alias gd="git diff --compact-summary"
alias ga="git add ."
alias gc="git commit"
alias gcm="git commit -m "
alias gca="git commit -a"
alias gco="git checkout"
alias gcb="git checkout -b"
alias gb="git branch"
alias gs="git status -sb" # upgrade your git if -sb breaks for you. it's fun.
alias grm="git status | grep deleted | awk '{print \$3}' | xargs git rm"
alias gac="git add -A; git commit"
alias gacm="git add -A; git commit -m "
alias g-="git checkout -" # quickly switch between branches.
alias gstash="git stash --include-untracked"

# clone git repos when bare link is pasted into shell
alias -s git="git clone" # this is a suffix alias.

greset() {
  git reset --soft HEAD~${1:-1}
}

# git commit browser by Junegunn Choi
# https://junegunn.kr/2015/03/browsing-git-commits-with-fzf
function gshow() {
  git log --graph --color=always \
    --format="%C(auto)%h%d %s %C(black)%C(bold)%cr" "$@" |
    fzf --ansi --no-sort --reverse --tiebreak=index --bind=ctrl-s:toggle-sort \
      --bind "ctrl-m:execute:
                (grep -o '[a-f0-9]\{7\}' | head -1 |
                xargs -I % sh -c 'git show --color=always % | less -R') << 'FZF-EOF'
                {}
FZF-EOF"
}
