# about: macOS checks for, downloads and installs system, security and App Store updates on its own.
# why: A Mac nobody looks after stays patched. The settings live in a system file, so they need the password.

on 'macos<=15' -- 'Turn on automatic updates in System Settings › General › Software Update' || return 0
pref /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled bool true
pref /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload bool true
pref /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates bool true
pref /Library/Preferences/com.apple.SoftwareUpdate CriticalUpdateInstall bool true
pref /Library/Preferences/com.apple.SoftwareUpdate ConfigDataInstall bool true
pref /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallAppUpdates bool true
