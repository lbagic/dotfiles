# about: Test fixture: installs a Brewfile with a third-party tap, and links libpq through brew.
# why: Exercises per-formula trust, skipped casks and -brew steps against the fake brew, without a real Brewfile.

brewfile setup.d/test/fixture.Brewfile

psql_linked() {
  local b p
  if b=$(brew_path) && p=$(HOMEBREW_NO_AUTO_UPDATE=1 "$b" --prefix 2>/dev/null) && [ -x "$p/bin/psql" ]; then
    echo linked
  else
    echo absent
    return 1
  fi
}

step -brew 'psql on PATH' psql_linked linked 'link --force libpq' 'unlink libpq'
