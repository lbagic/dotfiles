# about: The menu bar shows the battery percentage, Bluetooth and Sound.
# why: Battery left and the two controls reached for most are one click away.

on 'macos<=15' -- 'Show Battery percentage, Sound and Bluetooth in System Settings › Menu Bar' || return 0
pref -if laptop -currentHost com.apple.controlcenter BatteryShowPercentage bool true
# 18 is "show in menu bar".
pref -currentHost com.apple.controlcenter Bluetooth int 18
pref -currentHost com.apple.controlcenter Sound int 18
logout 'menu bar icons'
