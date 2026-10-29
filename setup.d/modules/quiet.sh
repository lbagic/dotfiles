# about: No startup chime, and no Siri icon in the menu bar.
# why: A preference. The chime setting lives in NVRAM, so it needs the password.

startup_chime() {
  local out
  out=$(nvram StartupMute 2>&1)
  if [ $? -ne 0 ]; then
    case $out in
      *'not found'*)
        echo absent
        return 1
        ;;
    esac
    printf '%s\n' "$out" | tail -1
    return 2
  fi
  out=${out##*$TAB}
  echo "$out"
  case $out in
    %01) return 0 ;;
    %00) return 1 ;;
    *) return 2 ;;
  esac
}

chime_undo_args() { # PRIOR
  if [ "$1" = absent ]; then echo '-d StartupMute'; else echo "StartupMute=$1"; fi
}

step -sudo 'startup chime off' startup_chime %01 'nvram StartupMute=%01' 'nvram $(chime_undo_args "$PRIOR")'
pref com.apple.Siri StatusMenuVisible bool false
logout 'Siri menu'
