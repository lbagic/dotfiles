# about: Turns the firewall on; checks FileVault and Find My, which are set up by hand.
# why: Laptops travel and join public Wi-Fi. A lost Mac should be encrypted and findable; FileVault and Find My involve the user's Apple Account and a recovery key, so they are done together with that person.

FIREWALL=/usr/libexec/ApplicationFirewall/socketfilterfw

firewall_state() {
  local out n
  out=$($FIREWALL --getglobalstate 2>&1)
  n=$(printf '%s\n' "$out" | sed -n 's/.*State = \([0-9]\).*/\1/p' | head -1)
  case $n in
    1 | 2) echo "$n" ;;
    0)
      echo 0
      return 1
      ;;
    *)
      printf '%s\n' "$out" | tail -1
      return 2
      ;;
  esac
}

filevault() {
  local out
  out=$(fdesetup status 2>&1)
  case $out in
    *'FileVault is On'*) echo on ;;
    *'Encryption in progress'*) echo encrypting ;;
    *'FileVault is Off'*)
      echo off
      return 1
      ;;
    *)
      printf '%s\n' "$out" | head -1
      return 2
      ;;
  esac
}

find_my() {
  local v
  v=$(defaults read /Library/Preferences/com.apple.FindMyMac FMMEnabled 2>/dev/null) || v=absent
  case $v in
    1) echo on ;;
    *)
      echo off
      return 1
      ;;
  esac
}

step -sudo 'firewall on' firewall_state '1 (on; 2, block all, also counts)' \
  "$FIREWALL --setglobalstate on" "$FIREWALL --setglobalstate off"
manual 'FileVault' filevault on \
  'Do this with the person who uses this Mac: System Settings › Privacy & Security › FileVault. They choose Apple Account or a recovery key; a key goes on paper, somewhere safe.'
manual 'Find My Mac' find_my on \
  'With the person who uses this Mac: System Settings › [their name] › iCloud › Find My Mac.'
