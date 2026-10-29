# about: Finder opens folders in list view and deletes Trash items older than 30 days.
# why: Preferences. Items in the Trash are gone for good after 30 days.

pref com.apple.finder FXPreferredViewStyle string Nlsv
pref com.apple.finder FXRemoveOldTrashItems bool true
restart Finder
