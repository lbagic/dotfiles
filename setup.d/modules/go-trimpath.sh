# about: Go builds strip local file paths from binaries (GOFLAGS=-trimpath).
# why: Offered and left out of every profile: reproducible builds with no home-folder paths in them.

go_flags() {
  local v
  command -v go >/dev/null 2>&1 || {
    echo 'go is not installed'
    return 2
  }
  v=$(go env GOFLAGS 2>/dev/null) || {
    echo 'go env failed'
    return 2
  }
  case " $v " in *' -trimpath '*)
    echo "$v"
    return 0
    ;;
  esac
  echo "${v:-empty}"
  return 1
}

step 'GOFLAGS has -trimpath' go_flags -trimpath 'go env -w GOFLAGS=-trimpath' \
  'if [ "$PRIOR" = empty ]; then go env -u GOFLAGS; else go env -w GOFLAGS="$PRIOR"; fi'
