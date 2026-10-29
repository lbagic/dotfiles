# about: Test fixture: one of each helper, against the fake defaults store.
# why: Lets setup.d/test/run check apply and undo without touching the Mac.

fixture_state() {
  local v
  v=$(defaults read test.fixture state 2>/dev/null) || v=absent
  echo "$v"
  [ "$v" = on ]
}

fixture_hand() {
  local v
  v=$(defaults read test.fixture hand 2>/dev/null) || v=absent
  echo "$v"
  [ "$v" = done ]
}

pref -currentHost test.fixture host int 3
pref test.fixture ratio float 0.5
pref test.fixture keep string same
pref /Library/Preferences/test.fixture system bool true
step -sudo 'fixture switch' fixture_state on 'fixture-apply --on' 'fixture-undo --to "$PRIOR"'
step -tty -admin 'fixture installer' fixture_state on fixture-install 'print:remove the fixture by hand'
manual 'fixture hand step' fixture_hand done 'Do the fixture thing by hand.'
restart FixtureApp
logout fixture

fixture_loaded() {
  local v
  v=$(defaults read test.fixture loaded 2>/dev/null) || v=no
  echo "$v"
  [ "$v" = yes ] || return 0
  # A restart helps only once the switch is on.
  fixture_state >/dev/null || return 3
  return 1
}

needs_restart 'fixture still loaded' fixture_loaded 'not loaded' 'Restart the Mac to unload the fixture.'
