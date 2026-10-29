# about: AirDrop accepts only contacts, and Apple's personalised ads are off.
# why: Strangers nearby cannot push files or pictures through AirDrop, and Apple stops using the user's activity for ads.

pref com.apple.sharingd DiscoverableMode string 'Contacts Only'
pref com.apple.AdLib allowApplePersonalizedAdvertising bool false
