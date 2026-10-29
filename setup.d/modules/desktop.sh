# about: A click on the wallpaper no longer hides every window, and the bottom-right screen corner no longer opens Quick Note.
# why: Both fire by accident and look like windows vanishing or a note appearing from nowhere. A corner set to anything else was chosen on purpose and is left alone.

pref -if 'macos>=14' com.apple.WindowManager EnableStandardClickToShowDesktop bool false

quick_note_corner() {
  local v
  v=$(defaults read com.apple.dock wvous-br-corner 2>/dev/null) || v=absent
  echo "$v"
  case $v in
    14) return 1 ;;
    # macOS 12 and later put Quick Note on this corner when nothing is stored.
    absent) [ "$F_MAJOR" -lt 12 ] ;;
    *) return 0 ;;
  esac
}

step 'bottom-right corner is not Quick Note' quick_note_corner '0 (no action)' \
  'defaults write com.apple.dock wvous-br-corner -int 0' \
  'if [ "$PRIOR" = absent ]; then defaults delete com.apple.dock wvous-br-corner; else defaults write com.apple.dock wvous-br-corner -int "$PRIOR"; fi'
restart Dock
