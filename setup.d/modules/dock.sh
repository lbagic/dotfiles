# about: The Dock hides and shows instantly, holds no recent apps, sits at size 42, no screen corner triggers anything, and its size slider is unlocked.
# why: A layout preference. size-immutable is a management setting that greys out the size slider; this removes that lock.

pref com.apple.dock autohide bool true
pref com.apple.dock autohide-delay float 0
pref com.apple.dock autohide-time-modifier float 0
pref com.apple.dock show-recents bool false
pref com.apple.dock tilesize int 42
pref com.apple.dock mru-spaces bool false
pref com.apple.dock wvous-tl-corner int 0
pref com.apple.dock wvous-tr-corner int 0
pref com.apple.dock wvous-bl-corner int 0
pref com.apple.dock wvous-br-corner int 0
pref com.apple.dock size-immutable bool unset
restart Dock
