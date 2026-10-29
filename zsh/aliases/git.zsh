#!/usr/bin/env zsh

source ~/.dotfiles/scripts/input_select.zsh

# vim:ft=zsh
alias glog="git log --decorate --oneline --graph --color=always --pretty=format:'%C(auto)%h%C(auto)%d %s %C(cyan)(%aN, %cr)'"
alias gloga="glog --all"
alias gd="git diff --compact-summary"
alias gdiff="git diff -- . ':(exclude)package-lock.json'"
alias gco="git checkout"
alias gs="git status -sb"

function gadd() { git add ${1:+*$1*} ${1:-.}; git status -sb; }
function grestore() { git restore --staged ${1:+*$1*} ${1:-.}; git status -sb; }
function gcheckout() { git checkout -- ${@:-.}; git status -sb; }

alias gclean="git clean -fd"
alias gprune="git add .;git restore --staged .; git checkout -- .; git clean -fd; git status -sb"
gcommit() {
  commit_type_list=("build" "chore" "ci" "docs" "feat" "fix" "perf" "refactor" "revert" "style" "test")
  commit_type=""
  
  input_select "Select commit type:" "commit_type_list[@]" "commit_type"

  if [[ -z "$commit_type" ]]; then
    return 1
  fi
  
  printf $COLOR_GREEN
  printf "\n${commit_type}: "
  read commit_message
  printf $COLOR_DEFAULT

  command="git commit -m \"$commit_type: $commit_message\""
  print -s "$command"
  eval "$command"
  
  git status -sb
}

gstash() {
  if [[ $# -eq 0 ]]; then
    git stash --include-untracked
  else
    git stash push --include-untracked -- "$@"
  fi
}
gapply() {
  git stash apply "stash@{${1:-0}}"
}
alias gpush="git push"
alias gpull="git pull"
alias gamend="git commit --amend"
alias -s git="git clone" # this is a suffix alias - clone git repos when bare link is pasted into shell
gpullhard() {
  local branch=${1:-$(git branch --show-current)}
  if [[ -z "$branch" ]]; then
    echo "Error: no branch specified and not on a branch (detached HEAD)."
    return 1
  fi

  print -n "This will reset branch '$branch' to origin/$branch and discard local changes. Continue? (y/N) "
  read -r REPLY
  [[ $REPLY =~ ^[Yy]$ ]] || return 1

  git fetch origin "$branch" || return 1
  git reset --hard "origin/$branch"
}

gtag() {
  # Usage:
  # gtag patch|minor|major       -> increments latest semver tag (asks for confirmation)
  # gtag push <tagname>          -> push an existing tag
  # gtag <explicit_tag>          -> create & optionally push an explicit tag (vX.Y.Z)

  if [[ "$1" == "push" ]]; then
    if [[ -z "$2" ]]; then
      echo "Usage: gtag push <tag>"
      return 1
    fi
    git push origin "$2"
    echo "Pushed tag $2"
    return 0
  fi

  local part=$1
  local latest

  # Find highest semver tag vX.Y.Z
  latest=$(git tag | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
    | sed 's/^v//' \
    | sort -t. -k1,1n -k2,2n -k3,3n \
    | tail -n1)

  if [[ -z "$latest" ]]; then
    latest="0.0.0"
  fi

  local major minor patch
  IFS='.' read -r major minor patch <<< "$latest"

  local new

  case "$part" in
    patch)
      ((patch++))
      new="v${major}.${minor}.${patch}"
      ;;
    minor)
      ((minor++))
      patch=0
      new="v${major}.${minor}.${patch}"
      ;;
    major)
      ((major++))
      minor=0
      patch=0
      new="v${major}.${minor}.${patch}"
      ;;
    v*.*.*)
      # explicit tag like v1.2.3
      new="$part"
      ;;
    *)
      echo "Usage: gtag [patch|minor|major|vX.Y.Z|push <tag>]"
      return 1
      ;;
  esac

  # Confirm creating tag
  echo "Detected latest tag: v$latest"
  echo "Proposed new tag: $new"
  read "create_confirm?Create this tag? (y/N): "
  if [[ "$create_confirm" =~ ^[Yy]$ ]]; then
    git tag -a "$new" -m "Release $new"
    echo "Tag $new created."

    # Ask about pushing
    read "push_confirm?Push this tag to origin? (y/N): "
    if [[ "$push_confirm" =~ ^[Yy]$ ]]; then
      git push origin "$new"
      echo "Tag $new pushed."
    else
      echo "Tag $new not pushed."
    fi

  else
    echo "Aborted."
  fi
}

function greset() {
  git reset --soft HEAD~${1:-1}
  git status -sb
}
grevert() {
  if [[ -z "$1" ]]; then
    # No argument → revert last commit
    git revert HEAD
  elif [[ "$1" =~ ^[0-9]+$ ]]; then
    # Numeric argument → revert last N commits
    git revert "HEAD~$1..HEAD"
  else
    # Otherwise assume it's a commit hash or ref
    git revert "$1"
  fi
}

function gb() {
  if [[ -z "$1" ]]; then
    git branch
  else
    git branch | grep "$1"
  fi
}
function gba() {
  if [[ -z "$1" ]]; then
    git branch -a
  else
    git branch -a | grep "$1"
  fi
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
