# about: The Mac asks for the password as soon as the screen saver starts or the display sleeps.
# why: A laptop left open or lost should not stay usable for an hour. The delay does not stop running work: closing the lid sleeps the Mac whatever it is.

screen_lock() {
  local out n
  out=$(sysadminctl -screenLock status 2>&1)
  # Seen on macOS 15: "... screenLock delay is 3600 seconds". The wording for
  # an immediate or disabled lock is not verified. Text not matched here is a
  # fail row, never a set row, so apply cannot keep re-applying on it.
  case $out in
    *'screenLock delay is '*' seconds'*)
      n=$(printf '%s\n' "$out" | sed -n 's/.*screenLock delay is \([0-9][0-9]*\) seconds.*/\1/p' | head -1)
      echo "$n"
      [ -n "$n" ] || return 2
      [ "$n" -le 5 ]
      ;;
    *immediate*) echo immediate ;;
    *'screenLock is off'*)
      echo off
      return 1
      ;;
    *)
      printf '%s\n' "$out" | sed 's/^.*sysadminctl\[[0-9:]*\] //' | tail -1
      return 2
      ;;
  esac
}

step -tty -settarget 'immediate (asks for the login password)' 'password as soon as the screen locks' screen_lock immediate \
  'sysadminctl -screenLock immediate -password -' 'sysadminctl -screenLock "$PRIOR" -password -'
