# about: Turns off the Spotlight shortcut so Command-Space opens Raycast.
# why: For Raycast bound to Command-Space. The disabled shortcut keeps Spotlight's own keys, so turning it back on does not clash with Finder search.

spotlight_shortcut() {
  local f="$HOME/Library/Preferences/com.apple.symbolichotkeys.plist" pb=/usr/libexec/PlistBuddy k=:AppleSymbolicHotKeys:64 en p
  if [ ! -f "$f" ] || ! en=$($pb -c "Print $k:enabled" "$f" 2>/dev/null); then
    echo 'absent (Spotlight on Command-Space)'
    return 1
  fi
  p="$($pb -c "Print $k:value:parameters:0" "$f" 2>/dev/null),$($pb -c "Print $k:value:parameters:1" "$f" 2>/dev/null),$($pb -c "Print $k:value:parameters:2" "$f" 2>/dev/null)"
  echo "enabled=$en $p"
  [ "$en" = false ] && [ "$p" = 32,49,1048576 ]
}

spotlight_dict() { # ENABLED P0 P1 P2: hotkey 64 as defaults -dict-add takes it
  printf '<dict><key>enabled</key><%s/><key>value</key><dict><key>type</key><string>standard</string><key>parameters</key><array><integer>%s</integer><integer>%s</integer><integer>%s</integer></array></dict></dict>' "$1" "$2" "$3" "$4"
}

# The dict to restore from PRIOR, a value spotlight_shortcut printed. defaults
# cannot delete one key inside this dictionary, so an absent prior is restored
# as Apple's default for it, which macOS treats the same.
spotlight_dict_from() {
  local en p a b c
  case $1 in
    'enabled=true '* | 'enabled=false '*)
      en=${1#enabled=}
      en=${en%% *}
      p=${1#* },
      a=${p%%,*} p=${p#*,}
      b=${p%%,*} p=${p#*,}
      c=${p%%,*}
      case "$a$b$c" in '' | *[!0-9]*) ;; *)
        spotlight_dict "$en" "$a" "$b" "$c"
        return 0
        ;;
      esac
      ;;
  esac
  spotlight_dict true 32 49 1048576
}

# Hotkey 64 is "Show Spotlight search": space (32), key code 49, Command (1048576).
step 'Spotlight shortcut off' spotlight_shortcut 'enabled=false 32,49,1048576' \
  "defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 64 '$(spotlight_dict false 32 49 1048576)'" \
  'defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 64 "$(spotlight_dict_from "$PRIOR")"'
restart hotkeys
