# about: sudo accepts Touch ID. Inside tmux this also needs pam_reattach, which is not added.
# why: For someone who runs sudo often. /etc/pam.d/sudo_local is the file Apple provides for this, and it survives macOS updates.

on 'macos>=14' touchid -- 'Touch ID for sudo needs macOS 14 or later and an enrolled finger (System Settings › Touch ID & Password); then run: ./setup apply touchid-sudo' || return 0

pam_tid() {
  local f=/etc/pam.d/sudo_local
  if [ ! -e "$f" ]; then
    echo absent
    return 1
  fi
  if grep -Eq '^[[:space:]]*auth[[:space:]].*pam_tid\.so' "$f"; then
    echo present
    return 0
  fi
  # Someone else's sudo_local: edit it by hand rather than overwrite it.
  echo 'sudo_local exists without pam_tid'
  return 2
}

step -sudo 'Touch ID for sudo' pam_tid present \
  "sh -c \"sed 's/^#auth/auth/' /etc/pam.d/sudo_local.template > /etc/pam.d/sudo_local\"" \
  'rm /etc/pam.d/sudo_local'
