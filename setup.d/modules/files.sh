# about: Finder shows every file extension, the path bar and the status bar; Save dialogs open expanded.
# why: A visible extension unmasks an app posing as a document; the bars show where a file is and how much space is left; the expanded Save dialog shows which folder a file goes to.

pref -g AppleShowAllExtensions bool true
pref com.apple.finder ShowPathbar bool true
pref com.apple.finder ShowStatusBar bool true
pref -g NSNavPanelExpandedStateForSaveMode bool true
restart Finder
