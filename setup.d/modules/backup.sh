# about: Checks that Time Machine has a backup drive; setting one up is done by hand.
# why: A Mac with no backup loses everything with its disk. Time Machine can erase the drive it is given, so a person picks the drive and sets it up with whoever uses the Mac.

time_machine() {
  local out name
  out=$(tmutil destinationinfo 2>&1)
  name=$(printf '%s\n' "$out" | sed -n 's/^Name *: *//p' | head -1)
  if [ -n "$name" ]; then
    echo "$name"
    return 0
  fi
  case $out in
    *'No destinations'*)
      echo none
      return 1
      ;;
  esac
  printf '%s\n' "$out" | tail -1
  return 2
}

manual 'Time Machine destination' time_machine 'a backup drive' \
  "Use an empty drive at least twice the Mac's storage. Time Machine may offer to ERASE the drive. Never use a drive that holds photos or files. Set it up with the person who uses this Mac, in System Settings › General › Time Machine."
