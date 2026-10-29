#!/usr/bin/env zsh

COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[0;33m'
COLOR_DEFAULT='\033[0m'

function input_select() {
  local PS3="$1"
  local -a options=("${(@P)2}")
  local letters=("a" "b" "c" "d" "e" "f" "g" "h" "i" "j" "k" "l" "m" "n" "o" "p" "q" "r" "s" "t" "u" "v" "w" "x" "y" "z")
  local variable_to_mutate="$3"
  printf "${COLOR_GREEN}${PS3}${COLOR_DEFAULT}\n"

  for i in {1..$#options}; do
    currentLetter=${letters[$i]}
    currentOption=${options[$i]}
    echo "${currentLetter}) ${currentOption}"
  done

  read -sk 1 letter

  for i in {1..$#options}; do
    currentLetter=${letters[$i]}
    if [[ $letter == $currentLetter ]]; then
      selectedOption=${options[$i]}
      eval "$variable_to_mutate=\$selectedOption"  # Use indirect variable referencing to assign a new value
      return
    fi  
  done

  printf "${COLOR_RED}Invalid choice. Exiting.${COLOR_DEFAULT}\n"
  return 1
}

# commit_type_list=("build" "chore" "ci" "docs" "feat" "fix" "perf" "refactor" "revert" "style" "test")
# commit_type=""
# input_select "Select commit type:" "commit_type_list[@]" "commit_type"
# echo $commit_type
