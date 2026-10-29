# about: Fast key repeat, and no automatic capitalisation, double-space period, spelling correction, smart quotes or smart dashes.
# why: Typing preferences; curly quotes and dashes break shell commands and code pasted from documents. KeyRepeat 1 is faster than the fastest setting System Settings offers (2).

pref -g InitialKeyRepeat int 15
pref -g KeyRepeat int 1
pref -g NSAutomaticCapitalizationEnabled bool false
pref -g NSAutomaticPeriodSubstitutionEnabled bool false
pref -g NSAutomaticSpellingCorrectionEnabled bool false
pref -g NSAutomaticQuoteSubstitutionEnabled bool false
pref -g NSAutomaticDashSubstitutionEnabled bool false
logout keyboard
