# shellcheck shell=bash
# Runner internals and item helpers, sourced by ./setup.
#
# This must run on the stock /bin/bash 3.2: no associative arrays, mapfile,
# ${x,,}, [[ -v ]] or declare -g, and no "${arr[@]}" on a possibly empty
# array. Lists are newline- or space-separated strings and files instead.

TAB=$(printf '\t')
RECEIPT_DIR="$HOME/Library/Application Support/dotfiles-setup"
RECEIPTS="$RECEIPT_DIR/receipts.tsv"
ACTIVATE_SETTINGS=/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings
LABEL_WIDTH=54

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m' C_GREEN=$'\033[32m' C_YELLOW=$'\033[33m' C_RED=$'\033[31m' C_DIM=$'\033[2m' C_BOLD=$'\033[1m'
else
  C_RESET='' C_GREEN='' C_YELLOW='' C_RED='' C_DIM='' C_BOLD=''
fi

die() {
  printf 'setup: %s\n' "$*" >&2
  exit 2
}

# ---------------------------------------------------------------- output

status_word() {
  local c=''
  case $1 in
    ok | done) c=$C_GREEN ;;
    set | todo | undo | run) c=$C_YELLOW ;;
    fail) c=$C_RED ;;
    skip | note) c=$C_DIM ;;
  esac
  printf '%s%-4s%s' "$c" "$1" "$C_RESET"
}

tildify() {
  local t='~'
  case $1 in
    "$HOME" | "$HOME"/*) printf '%s' "$t${1#"$HOME"}" ;;
    *) printf '%s' "$1" ;;
  esac
}

record_row() { # STATUS LABEL SUDO
  printf '%s\t%s\t%s\t%s\n' "$1" "$MODULE" "$2" "$3" >>"$SETUP_RUN/rows.$MODE"
  case $1 in
    set | undo) MOD_SET=1 ;;
    done) MOD_CHANGED=1 ;;
  esac
}

# row STATUS LABEL CURRENT TARGET [SUDO]
row() {
  local tag=''
  [ "${5:-0}" = 1 ] && tag='  [sudo]'
  printf '  %s  %-*s  %s → %s%s\n' "$(status_word "$1")" "$LABEL_WIDTH" "$2" "$3" "$4" "$tag"
  record_row "$1" "$2" "${5:-0}"
}

# row_text STATUS TEXT: a row with no current value (notes, whole-module skips)
row_text() {
  printf '  %s  %s\n' "$(status_word "$1")" "$2"
  record_row "$1" "$2" 0
}

queue() { # NAME LINE
  printf '%s\n' "$2" >>"$SETUP_RUN/q.$MODE.$1"
}

queued() { # MODE NAME: the queue, duplicates dropped, order kept
  [ -s "$SETUP_RUN/q.$1.$2" ] && awk '!seen[$0]++' "$SETUP_RUN/q.$1.$2"
}

count_rows() { # MODE STATUS
  [ -f "$SETUP_RUN/rows.$1" ] || {
    echo 0
    return
  }
  awk -F'\t' -v s="$2" '$1 == s { n++ } END { print n + 0 }' "$SETUP_RUN/rows.$1"
}

# ---------------------------------------------------------------- facts

facts_init() {
  local v n
  F_MACOS=${SETUP_FACT_MACOS:-$(sw_vers -productVersion 2>/dev/null)}
  F_MAJOR=${F_MACOS%%.*}
  case $F_MAJOR in '' | *[!0-9]*) F_MAJOR=0 ;; esac
  if [ -n "${SETUP_FACT_ARCH:-}" ]; then
    v=$SETUP_FACT_ARCH
  # uname -m says x86_64 when this shell runs under Rosetta; this sysctl does not.
  elif [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = 1 ]; then
    v=arm64
  else
    v=x86_64
  fi
  case $v in arm64) F_ARCH=arm64 ;; *) F_ARCH=intel ;; esac
  if [ -n "${SETUP_FACT_LAPTOP:-}" ]; then
    F_LAPTOP=$SETUP_FACT_LAPTOP
  elif pmset -g batt 2>/dev/null | grep -q InternalBattery; then
    F_LAPTOP=1
  else
    F_LAPTOP=0
  fi
  if [ -n "${SETUP_FACT_TOUCHID:-}" ]; then
    F_TOUCHID=$SETUP_FACT_TOUCHID
  else
    n=$(bioutil -c 2>/dev/null | sed -n 's/.*[^0-9]\([0-9][0-9]*\) biometric template.*/\1/p' | awk '{ s += $1 } END { print s + 0 }')
    if [ "$n" -gt 0 ]; then F_TOUCHID=1; else F_TOUCHID=0; fi
  fi
  export F_MACOS F_MAJOR F_ARCH F_LAPTOP F_TOUCHID
}

facts_line() {
  local s="macOS ${F_MACOS:-unknown} · $F_ARCH"
  [ "$F_LAPTOP" = 1 ] && s="$s · laptop"
  [ "$F_TOUCHID" = 1 ] && s="$s · Touch ID"
  printf '%s' "$s"
}

# Facts are comma-separated: macos>=N, macos<=N, arm64, intel, laptop, touchid.
# Modules must quote a fact holding < or >: unquoted, the shell reads it as a
# redirection and creates a file.
fact_syntax() {
  case $1 in
    'macos>='[0-9]* | 'macos<='[0-9]* | arm64 | intel | laptop | touchid) return 0 ;;
  esac
  die "$MODULE: unknown fact '$1'"
}

fact_ok() {
  case $1 in
    'macos>='*) [ "$F_MAJOR" -ge "${1#macos>=}" ] ;;
    'macos<='*) [ "$F_MAJOR" -le "${1#macos<=}" ] ;;
    arm64) [ "$F_ARCH" = arm64 ] ;;
    intel) [ "$F_ARCH" = intel ] ;;
    laptop) [ "$F_LAPTOP" = 1 ] ;;
    touchid) [ "$F_TOUCHID" = 1 ] ;;
    *) die "$MODULE: unknown fact '$1'" ;;
  esac
}

facts_each() { # FACTS FUNCTION: FUNCTION on each fact, stops at the first failure
  local f
  for f in $(printf '%s' "$1" | tr ',' ' '); do
    "$2" "$f" || return 1
  done
}

facts_ok() { facts_each "$1" fact_ok; }

facts_words() { # FACTS: plain words for skip rows
  local f out=''
  for f in $(printf '%s' "$1" | tr ',' ' '); do
    case $f in
      'macos>='*) f="macOS ${f#macos>=} or later" ;;
      'macos<='*) f="macOS ${f#macos<=} or earlier" ;;
      arm64) f='Apple silicon' ;;
      intel) f='an Intel Mac' ;;
      laptop) f='a laptop' ;;
      touchid) f='Touch ID with a finger enrolled' ;;
    esac
    out="$out${out:+ and }$f"
  done
  printf '%s' "$out"
}

# ---------------------------------------------------------------- system access

brew_path() {
  if [ "${SETUP_TEST:-}" = 1 ]; then
    # Tests never reach a real brew: only the fake in setup.d/test/, and only
    # once a test has marked it present in its state folder $SETUP_TEST_BREW.
    [ -n "${SETUP_TEST_BREW:-}" ] && [ -e "$SETUP_TEST_BREW/present" ] && [ -x "$SETUP_DIR/test/fake-brew" ] || return 1
    printf '%s\n' "$SETUP_DIR/test/fake-brew"
    return 0
  fi
  [ "${SETUP_FACT_BREW:-}" = none ] && return 1
  local b
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [ -x "$b" ]; then
      printf '%s\n' "$b"
      return 0
    fi
  done
  return 1
}

# sys_run TTY SUDO CMD: eval CMD, as root when SUDO=1, attached to the terminal
# when TTY=1 (otherwise its output goes to $SETUP_RUN/out). Under SETUP_TEST=1
# the command is recorded in $SETUP_TEST_LOG and not run.
sys_run() {
  local pre=''
  [ "$2" = 1 ] && pre='sudo '
  : >"$SETUP_RUN/out"
  if [ "${SETUP_TEST:-}" = 1 ]; then
    case $3 in
      *PRIOR*) printf 'run: %s%s  [PRIOR=%s]\n' "$pre" "$3" "$PRIOR" ;;
      *) printf 'run: %s%s\n' "$pre" "$3" ;;
    esac >>"$SETUP_TEST_LOG"
    return 0
  fi
  if [ "$1" = 1 ]; then
    eval "$pre$3"
  else
    eval "$pre$3" >"$SETUP_RUN/out" 2>&1
  fi
}

run_error() { # one line describing why the last sys_run failed
  local msg
  msg=$(grep -v '^[[:space:]]*$' "$SETUP_RUN/out" 2>/dev/null | tail -1)
  [ -n "$msg" ] || msg='failed (output above)'
  case $msg in
    *'Operation not permitted'*) msg="$msg: refused by System Integrity Protection" ;;
  esac
  printf '%s' "$msg"
}

# ---------------------------------------------------------------- receipts
# One line per change: module, item id, prior type, prior value (tab-separated).

receipt_add() { # ID TYPE VALUE
  mkdir -p "$RECEIPT_DIR" &&
    printf '%s\t%s\t%s\t%s\n' "$MODULE" "$1" "$2" "$3" >>"$RECEIPTS"
}

receipt_get() { # ID: sets R_TYPE and R_VALUE from the earliest receipt
  local line
  [ -f "$RECEIPTS" ] || return 1
  line=$(awk -F'\t' -v m="$MODULE" -v id="$1" '$1 == m && $2 == id { print; exit }' "$RECEIPTS")
  [ -n "$line" ] || return 1
  R_TYPE=$(printf '%s\n' "$line" | cut -f3)
  R_VALUE=$(printf '%s\n' "$line" | cut -f4-)
}

receipt_drop() { # ID: every receipt of this item
  awk -F'\t' -v m="$MODULE" -v id="$1" '!($1 == m && $2 == id)' "$RECEIPTS" >"$RECEIPTS.tmp" &&
    mv "$RECEIPTS.tmp" "$RECEIPTS"
  [ -s "$RECEIPTS" ] || rm -f "$RECEIPTS"
}

receipt_ids() { # this module's item ids, oldest first
  [ -f "$RECEIPTS" ] || return 0
  awk -F'\t' -v m="$MODULE" '$1 == m && !seen[$2]++ { print $2 }' "$RECEIPTS"
}

# ---------------------------------------------------------------- describe

# desc KIND LABEL GATE SUDO UNDOKIND DETAIL UNDOTEXT
# UNDOKIND is restore, revert, print or none; list and readme summarise it.
desc() {
  printf '%s\t%s\t%s\t%s\n' "$MODULE" "$1" "$4" "$5" >>"$SETUP_RUN/desc"
  [ "${SHOW:-0}" = 1 ] || return 0
  local extra=''
  [ -n "$3" ] && extra=" (only on $(facts_words "$3"))"
  [ "$4" = 1 ] && extra="$extra [sudo]"
  printf '    %-5s %s %s%s\n' "$1" "$2" "$6" "$extra"
  printf '          undo: %s\n' "$7"
}

undo_kind() {
  case $1 in print:*) echo print ;; *) echo revert ;; esac
}

undo_text() {
  case $1 in print:*) printf 'prints "%s"' "${1#print:}" ;; *) printf 'runs %s' "$1" ;; esac
}

# ---------------------------------------------------------------- pref

pref_tname() {
  case $1 in bool) echo boolean ;; int) echo integer ;; *) echo "$1" ;; esac
}

pref_flag() {
  case $1 in boolean) echo bool ;; integer) echo int ;; *) echo "$1" ;; esac
}

pref_fmt() { # VALUE TYPE
  case $2 in
    absent) echo absent ;;
    boolean) case $1 in 1 | true | yes) echo true ;; *) echo false ;; esac ;;
    *) printf '%s\n' "$1" ;;
  esac
}

bool01() {
  case $1 in true | TRUE | yes | YES | 1) echo 1 ;; *) echo 0 ;; esac
}

# defaults accepts only yes, true, no or false after -bool, never 1 or 0.
bool_word() {
  if [ "$(bool01 "$1")" = 1 ]; then echo true; else echo false; fi
}

pref_arg() { # TYPE VALUE: the value as defaults write takes it
  case $1 in bool | boolean) bool_word "$2" ;; *) printf '%s\n' "$2" ;; esac
}

pref_read() { # CH DOMAIN KEY: sets PV and PT; returns 1 with PV holding the error
  PV=$(defaults $1 read "$2" "$3" 2>"$SETUP_RUN/err")
  if [ $? -ne 0 ]; then
    if grep -q 'does not exist' "$SETUP_RUN/err"; then
      PV='' PT=absent
      return 0
    fi
    PV=$(grep -v '^[[:space:]]*$' "$SETUP_RUN/err" | tail -1)
    PT=error
    return 1
  fi
  PT=$(defaults $1 read-type "$2" "$3" 2>/dev/null)
  PT=${PT#Type is }
  [ -n "$PT" ] || PT=unknown
}

pref_at() { # WANT TYPE: whether PV/PT already hold it
  if [ "$1" = unset ]; then
    [ "$PT" = absent ]
    return
  fi
  [ "$PT" = "$(pref_tname "$2")" ] || return 1
  case $2 in
    bool) [ "$PV" = "$(bool01 "$1")" ] ;;
    float) awk -v a="$PV" -v b="$1" 'BEGIN { exit !(a + 0 == b + 0) }' ;;
    *) [ "$PV" = "$1" ] ;;
  esac
}

# pref [-if FACTS] [-currentHost] DOMAIN KEY TYPE VALUE|unset
# TYPE is bool, int, float or string. DOMAIN -g is the global domain; a DOMAIN
# starting with / is a file and needs sudo to write.
pref() {
  local gate='' ch=''
  while :; do
    case $1 in
      -if) gate=$2 && shift 2 ;;
      -currentHost) ch=-currentHost && shift ;;
      *) break ;;
    esac
  done
  [ $# -eq 4 ] || die "$MODULE: pref wants DOMAIN KEY TYPE VALUE|unset, got: $*"
  local dom=$1 key=$2 type=$3 want=$4 sudo=0 label wt tdisp cur tshow st pre=''
  case $type in bool | int | float | string) ;; *) die "$MODULE: pref type '$type' is not bool, int, float or string" ;; esac
  case $dom in /*) sudo=1 ;; esac
  label="${ch:+$ch }$dom $key"
  wt=$(pref_tname "$type")
  if [ "$want" = unset ]; then tdisp=absent; else tdisp=$(pref_fmt "$want" "$wt"); fi

  case $MODE in
    describe)
      [ -z "$gate" ] || facts_each "$gate" fact_syntax
      if [ "$want" = unset ]; then
        desc pref "$label" "$gate" "$sudo" restore 'deleted' 'restores the prior value'
      else
        desc pref "$label" "$gate" "$sudo" restore "= $tdisp ($type)" 'restores the prior value'
      fi
      return 0
      ;;
    undoplan | undo)
      pref_undo "$label" "$ch" "$dom" "$key" "$sudo"
      return 0
      ;;
  esac

  if [ -n "$gate" ] && ! facts_ok "$gate"; then
    [ "$MODE" = plan ] && row skip "$label" 'not checked' "$tdisp  (needs $(facts_words "$gate"))" "$sudo"
    return 0
  fi
  if ! pref_read "$ch" "$dom" "$key"; then
    [ "$MODE" = plan ] && row fail "$label" "$PV" "$tdisp" "$sudo"
    return 0
  fi
  case $PT in
    absent | boolean | integer | float | string) ;;
    *)
      [ "$MODE" = plan ] && row fail "$label" "stored as $PT" "$tdisp (left alone)" "$sudo"
      return 0
      ;;
  esac
  cur=$(pref_fmt "$PV" "$PT")
  tshow=$tdisp
  if [ "$PT" != absent ] && [ "$want" != unset ] && [ "$PT" != "$wt" ]; then
    cur="$cur ($PT)"
    tshow="$tdisp ($wt)"
  fi
  if pref_at "$want" "$type"; then st=ok; else st=set; fi

  case $MODE in
    plan) row "$st" "$label" "$cur" "$tshow" "$sudo" ;;
    apply)
      [ "$st" = set ] || return 0
      [ "$sudo" = 1 ] && pre=sudo
      if [ "$want" = unset ]; then
        $pre defaults $ch delete "$dom" "$key" >"$SETUP_RUN/out" 2>&1
      else
        $pre defaults $ch write "$dom" "$key" "-$type" "$(pref_arg "$type" "$want")" >"$SETUP_RUN/out" 2>&1
      fi
      if [ $? -eq 0 ]; then
        receipt_add "$label" "$PT" "$PV"
        row done "$label" "$cur" "$tshow" "$sudo"
      else
        row fail "$label" "$cur" "$(run_error)" "$sudo"
      fi
      ;;
  esac
}

pref_undo() { # LABEL CH DOMAIN KEY SUDO
  local prior cur pre=''
  receipt_get "$1" || return 0
  prior=$(pref_fmt "$R_VALUE" "$R_TYPE")
  if pref_read "$2" "$3" "$4"; then cur=$(pref_fmt "$PV" "$PT"); else cur=$PV; fi
  case $MODE in
    undoplan) row undo "$1" "$cur" "$prior" "$5" ;;
    undo)
      if [ "$PT" = "$R_TYPE" ] && [ "$PV" = "$R_VALUE" ]; then
        receipt_drop "$1"
        row done "$1" "$cur" "$prior (already)" "$5"
        return 0
      fi
      [ "$5" = 1 ] && pre=sudo
      if [ "$R_TYPE" = absent ]; then
        $pre defaults $2 delete "$3" "$4" >"$SETUP_RUN/out" 2>&1
      else
        $pre defaults $2 write "$3" "$4" "-$(pref_flag "$R_TYPE")" "$(pref_arg "$R_TYPE" "$R_VALUE")" >"$SETUP_RUN/out" 2>&1
      fi
      if [ $? -eq 0 ]; then
        receipt_drop "$1"
        row done "$1" "$cur" "$prior" "$5"
      else
        row fail "$1" "$cur" "$(run_error)" "$5"
      fi
      ;;
  esac
}

# ---------------------------------------------------------------- step

# step [-if FACTS] [-sudo] [-admin] [-tty] [-brew] [-settarget TEXT] LABEL CHECK TARGET APPLY UNDO
#   CHECK  a function printing the current value as one line; returns 0 at
#          target, 1 when a change is needed, 2 or more when it cannot tell.
#   APPLY, UNDO  command strings, eval'd. UNDO may use $PRIOR, the CHECK value
#          recorded at apply. "print:TEXT" as UNDO prints TEXT and runs nothing.
#   -sudo   APPLY and UNDO run under sudo.
#   -admin  APPLY runs as the user but needs the sudo timestamp the runner
#           caches up front (the Homebrew installer refuses to run as root).
#   -tty    APPLY and UNDO run attached to the terminal, for anything that prompts.
#   -brew   APPLY and UNDO are brew arguments, run with the brew found at
#           that moment; a step fails when there is none.
#   -settarget  the target shown when a change is needed, if it differs.
step() {
  local gate='' sudo=0 admin=0 tty=0 brew=0 settarget='' now nrc
  while :; do
    case $1 in
      -if) gate=$2 && shift 2 ;;
      -sudo) sudo=1 && shift ;;
      -admin) admin=1 && shift ;;
      -tty) tty=1 && shift ;;
      -brew) brew=1 && shift ;;
      -settarget) settarget=$2 && shift 2 ;;
      *) break ;;
    esac
  done
  [ $# -eq 5 ] || die "$MODULE: step wants LABEL CHECK TARGET APPLY UNDO, got $# arguments"
  local label=$1 check=$2 target=$3 apply=$4 undo=$5 pw=0 cur rc st tshow
  if [ "$sudo" = 1 ] || [ "$admin" = 1 ]; then pw=1; fi

  case $MODE in
    describe)
      [ -z "$gate" ] || facts_each "$gate" fact_syntax
      [ "$(type -t "$check")" = function ] || die "$MODULE: step '$label': CHECK '$check' is not a function"
      [ "$brew" = 1 ] && undo="brew $undo"
      desc step "$label" "$gate" "$pw" "$(undo_kind "$undo")" "→ ${settarget:-$target}" "$(undo_text "$undo")"
      return 0
      ;;
    undoplan | undo)
      step_undo "$label" "$check" "$undo" "$sudo" "$tty" "$brew"
      return 0
      ;;
  esac

  if [ -n "$gate" ] && ! facts_ok "$gate"; then
    [ "$MODE" = plan ] && row skip "$label" 'not checked' "${settarget:-$target}  (needs $(facts_words "$gate"))" "$pw"
    return 0
  fi
  cur=$("$check" 2>/dev/null)
  rc=$?
  cur=$(printf '%s\n' "$cur" | head -1)
  case $rc in
    0) st=ok tshow=$target ;;
    1) st=set tshow=${settarget:-$target} ;;
    *) st=fail tshow=$target ;;
  esac

  case $MODE in
    plan) row "$st" "$label" "$cur" "$tshow" "$pw" ;;
    apply)
      [ "$st" = set ] || return 0
      [ "$tty" = 1 ] && printf '  %s  %s: interactive, output follows\n' "$(status_word run)" "$label"
      if step_run "$brew" "$tty" "$sudo" "$apply"; then
        receipt_add "$label" step "$cur"
        # Some tools exit 0 without making the change, so CHECK decides. Under
        # SETUP_TEST the APPLY was only recorded, and CHECK would read the old state.
        nrc=0
        if [ "${SETUP_TEST:-}" != 1 ]; then
          now=$("$check" 2>/dev/null)
          nrc=$?
          now=$(printf '%s\n' "$now" | head -1)
        fi
        case $nrc in
          0) row done "$label" "$cur" "$tshow" "$pw" ;;
          1) row fail "$label" "$cur" "applied, but it reads $now" "$pw" ;;
          *)
            # The change may have landed, so its restart and logout notes stay.
            MOD_CHANGED=1
            row fail "$label" "$cur" "applied, but cannot tell whether it took${now:+: $now}" "$pw"
            ;;
        esac
      else
        row fail "$label" "$cur" "$(run_error)" "$pw"
      fi
      ;;
  esac
}

# step_run BREW TTY SUDO CMD: a step's APPLY or UNDO
step_run() {
  local b
  if [ "$1" != 1 ]; then
    sys_run "$2" "$3" "$4"
    return
  fi
  if ! b=$(brew_path); then
    echo 'Homebrew not found' >"$SETUP_RUN/out"
    return 1
  fi
  # shellcheck disable=SC2086
  brew_do "$2" "$b" $4
}

step_undo() { # LABEL CHECK UNDO SUDO TTY BREW
  local cur
  receipt_get "$1" || return 0
  case $3 in
    print:*)
      case $MODE in
        undoplan) row undo "$1" "$R_VALUE before" 'printed instructions' ;;
        undo)
          receipt_drop "$1"
          row done "$1" "$R_VALUE before" "by hand: ${3#print:}"
          ;;
      esac
      return 0
      ;;
  esac
  cur=$("$2" 2>/dev/null)
  cur=$(printf '%s\n' "$cur" | head -1)
  case $MODE in
    undoplan) row undo "$1" "$cur" "$R_VALUE" "$4" ;;
    undo)
      PRIOR=$R_VALUE
      if step_run "$6" "$5" "$4" "$3"; then
        receipt_drop "$1"
        row done "$1" "$cur" "$R_VALUE" "$4"
      else
        row fail "$1" "$cur" "$(run_error)" "$4"
      fi
      PRIOR=''
      ;;
  esac
}

# ---------------------------------------------------------------- manual

# manual [-if FACTS] LABEL CHECK TARGET INSTRUCTIONS
# Check only: a value off target becomes a "todo" row and INSTRUCTIONS go to
# the closing list.
manual() {
  local gate=''
  if [ "$1" = -if ]; then
    gate=$2
    shift 2
  fi
  [ $# -eq 4 ] || die "$MODULE: manual wants LABEL CHECK TARGET INSTRUCTIONS"
  local label=$1 check=$2 target=$3 instr=$4 cur rc st
  case $MODE in
    describe)
      [ -z "$gate" ] || facts_each "$gate" fact_syntax
      [ "$(type -t "$check")" = function ] || die "$MODULE: manual '$label': CHECK '$check' is not a function"
      desc hand "$label" "$gate" 0 none "→ $target" 'nothing (check only)'
      [ "${SHOW:-0}" = 1 ] && printf '          by hand: %s\n' "$instr"
      return 0
      ;;
    plan) ;;
    *) return 0 ;;
  esac
  if [ -n "$gate" ] && ! facts_ok "$gate"; then
    row skip "$label" 'not checked' "$target  (needs $(facts_words "$gate"))"
    return 0
  fi
  cur=$("$check" 2>/dev/null)
  rc=$?
  cur=$(printf '%s\n' "$cur" | head -1)
  case $rc in 0) st=ok ;; 1) st=todo ;; *) st=fail ;; esac
  row "$st" "$label" "$cur" "$target"
  [ "$st" = todo ] && queue manual "$label: $instr"
  return 0
}

# needs_restart LABEL CHECK TARGET TEXT
# Check only, like manual, for a state that only a restart clears. CHECK
# returns 0 (clear), 1 (a restart is needed now), 2 (cannot tell) or 3 (a
# restart will be needed once this module's changes take). Plan lists TEXT for
# 1 and 3, as what follows apply; apply checks again after the module's
# changes and lists it only for 1, so a change that did not take asks for no
# restart.
needs_restart() {
  [ $# -eq 4 ] || die "$MODULE: needs_restart wants LABEL CHECK TARGET TEXT"
  local label=$1 check=$2 target=$3 text=$4 cur rc st
  case $MODE in
    describe)
      [ "$(type -t "$check")" = function ] || die "$MODULE: needs_restart '$label': CHECK '$check' is not a function"
      desc boot "$label" '' 0 none "→ $target" 'nothing (check only)'
      [ "${SHOW:-0}" = 1 ] && printf '          while it holds: %s\n' "$text"
      return 0
      ;;
    plan | apply) ;;
    *) return 0 ;;
  esac
  cur=$("$check" 2>/dev/null)
  rc=$?
  cur=$(printf '%s\n' "$cur" | head -1)
  case $rc in 0) st=ok ;; 1 | 3) st=todo ;; *) st=fail ;; esac
  [ "$MODE" = plan ] && row "$st" "$label" "$cur" "$target"
  case $MODE$rc in plan1 | plan3 | apply1) queue reboot "$MODULE$TAB$text" ;; esac
  return 0
}

# ---------------------------------------------------------------- module-level

# on FACTS... [-- HINT]: gate a whole module. A module writes `on ... || return 0`.
on() {
  local facts='' hint=''
  while [ $# -gt 0 ]; do
    if [ "$1" = -- ]; then
      shift
      hint=$*
      break
    fi
    facts="$facts${facts:+,}$1"
    shift
  done
  case $MODE in
    describe)
      facts_each "$facts" fact_syntax
      [ "${SHOW:-0}" = 1 ] && printf '    gate  only on %s%s\n' "$(facts_words "$facts")" "${hint:+; otherwise by hand: $hint}"
      return 0
      ;;
    plan | apply) ;;
    *) return 0 ;;
  esac
  facts_ok "$facts" && return 0
  if [ "$MODE" = plan ]; then
    row_text skip "$MODULE: needs $(facts_words "$facts")"
    [ -n "$hint" ] && queue manual "$MODULE: $hint"
  fi
  return 1
}

restart_cmd() {
  case $1 in
    hotkeys) printf '%s -u' "$ACTIVATE_SETTINGS" ;;
    *) printf 'killall %s' "$1" ;;
  esac
}

restart() { # APP, or hotkeys: queued for the end of the run, after a change only
  case $MODE in
    describe) [ "${SHOW:-0}" = 1 ] && printf '    after a change: %s\n' "$(restart_cmd "$1")" ;;
    *) MOD_RESTART="$MOD_RESTART $1" ;;
  esac
  return 0
}

logout() { # WHAT: added to the closing "log out and back in" line, after a change only
  case $MODE in
    describe) [ "${SHOW:-0}" = 1 ] && printf '    after a change: log out and back in (%s)\n' "$*" ;;
    *) MOD_LOGOUT="$MOD_LOGOUT$*$TAB" ;;
  esac
  return 0
}

module_end() {
  local flag a
  case $MODE in
    plan | undoplan) flag=$MOD_SET ;;
    apply | undo) flag=$MOD_CHANGED ;;
    *) return 0 ;;
  esac
  [ "$flag" = 1 ] || return 0
  for a in $MOD_RESTART; do queue restart "$a"; done
  printf '%s' "$MOD_LOGOUT" | tr "$TAB" '\n' | while IFS= read -r a; do
    [ -n "$a" ] && queue logout "$a"
  done
  return 0
}

run_restarts() {
  local a
  [ -s "$SETUP_RUN/q.$MODE.restart" ] && echo
  queued "$MODE" restart | while IFS= read -r a; do
    case $a in
      hotkeys) sys_run 0 0 "$ACTIVATE_SETTINGS -u" ;;
      *) killall "$a" >/dev/null 2>&1 ;;
    esac
    printf '  restarted %s\n' "$a"
  done
}

# ---------------------------------------------------------------- brewfile

brew_entries() { # FILE: "kind<TAB>name" per tap/brew/cask line
  sed -E -n "s/^(tap|brew|cask) \"([^\"]+)\".*/\\1$TAB\\2/p" "$1"
}

brew_validate() { # FILE REL: plain lines only, so bash can read the file
  local bad
  bad=$(grep -n -v -E '^[[:space:]]*(#.*)?$|^(tap|brew|cask) "[A-Za-z0-9@._/+-]+"[[:space:]]*(#.*)?$' "$1" | head -1)
  [ -z "$bad" ] || die "$2:${bad%%:*}: only plain tap/brew/cask lines are allowed: ${bad#*:}"
}

# brew_do TTY BREW ARGS...: a brew command that changes things. Under
# SETUP_TEST=1 only the fake brew in setup.d/test/ is ever run.
brew_do() {
  local tty=$1 b=$2
  shift 2
  if [ "${SETUP_TEST:-}" = 1 ]; then
    case $b in "$SETUP_DIR/test/"*) ;; *) die "SETUP_TEST=1: refusing to run $b" ;; esac
  fi
  : >"$SETUP_RUN/out"
  if [ "$tty" = 1 ]; then
    HOMEBREW_NO_AUTO_UPDATE=1 "$b" "$@"
  else
    HOMEBREW_NO_AUTO_UPDATE=1 "$b" "$@" >"$SETUP_RUN/out" 2>&1
  fi
}

# cask_outside BREW CASK: what shows that a missing cask's app is already
# there outside Homebrew: its .app, or the receipt of its package. brew will
# not replace such an app, and would run a package installer over it.
# Best effort: needs jq.
cask_outside() {
  local jq json a id
  jq=$(command -v jq 2>/dev/null) || return 1
  json=$(HOMEBREW_NO_AUTO_UPDATE=1 "$1" info --cask --json=v2 "$2" 2>/dev/null) || return 1
  while IFS= read -r a; do
    [ -n "$a" ] || continue
    if [ -e "/Applications/$a" ] || [ -e "$HOME/Applications/$a" ]; then
      printf '%s present\n' "$a"
      return 0
    fi
  done <<EOF
$(printf '%s\n' "$json" | "$jq" -r '.casks[0].artifacts[]? | select(type == "object" and has("app")) | .app[] | select(type == "string")' 2>/dev/null)
EOF
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    if pkgutil --pkgs="^$id\$" 2>/dev/null | grep -q .; then
      printf 'package %s installed\n' "$id"
      return 0
    fi
  done <<EOF
$(printf '%s\n' "$json" | "$jq" -r '.casks[0].artifacts[]? | select(type == "object" and has("uninstall")) | .uninstall[]? | .pkgutil? // empty | if type == "array" then .[] else . end' 2>/dev/null)
EOF
  return 1
}

# brew_third_party FILE: "kind<TAB>name" (kind formula or cask) for each entry
# named tap/name from a tap outside homebrew/. Homebrew loads those only once
# trusted; each one is trusted by name, never its whole tap.
brew_third_party() {
  brew_entries "$1" | awk -F'\t' -v OFS='\t' '
    $1 != "tap" && split($2, part, "/") == 3 && part[1] != "homebrew" { print ($1 == "brew" ? "formula" : "cask"), $2 }'
}

# brew_trusted BREW: "key<TAB>name" per entry of `brew trust --json=v1`, whose
# keys are taps, formulae, casks and commands; returns 1 without that command.
brew_trusted() {
  local out
  out=$(HOMEBREW_NO_AUTO_UPDATE=1 "$1" trust --json=v1 2>/dev/null) || return 1
  printf '%s\n' "$out" | awk '
    /^  "[a-z]+": *\[/ { key = $1; gsub(/[":]/, "", key); next }
    /^    "/ { v = $1; gsub(/[",]/, "", v); print key "\t" v }'
}

# brew_status FILE BREW: writes b.set and b.skip ("kind<TAB>name<TAB>current")
# and b.trust ("kind<TAB>name<TAB>state") under $SETUP_RUN; sets B_TOTAL,
# B_OK, B_ERR.
brew_status() {
  local file=$1 b=$2 out rc kind name what cur why tap key
  : >"$SETUP_RUN/b.set"
  : >"$SETUP_RUN/b.skip"
  : >"$SETUP_RUN/b.trust"
  B_ERR=''
  B_TOTAL=$(brew_entries "$file" | grep -c .)
  if [ -z "$b" ]; then
    brew_entries "$file" | awk -F'\t' -v OFS='\t' '{ print $1, $2, "absent" }' >"$SETUP_RUN/b.set"
    brew_third_party "$file" | awk -F'\t' -v OFS='\t' '{ print $1, $2, "untrusted" }' >"$SETUP_RUN/b.trust"
    B_OK=0
    return 0
  fi
  out=$(HOMEBREW_NO_AUTO_UPDATE=1 "$b" bundle check --no-upgrade --verbose --file "$file" 2>&1)
  rc=$?
  printf '%s\n' "$out" |
    LC_ALL=C sed -E -n "s/.*(Cask|Formula|Tap) ([^ ]+) needs to be ([a-z ]+)\\.?\$/\\1$TAB\\2$TAB\\3/p" >"$SETUP_RUN/b.raw"
  if [ "$rc" -ne 0 ] && [ ! -s "$SETUP_RUN/b.raw" ]; then
    B_ERR=$(printf '%s\n' "$out" | grep -v '^[[:space:]]*$' | tail -1)
    return 1
  fi
  while IFS="$TAB" read -r kind name what; do
    case $kind in Cask) kind=cask ;; Formula) kind=brew ;; Tap) kind=tap ;; esac
    case $what in installed* | tapped*) cur=absent ;; linked*) cur=unlinked ;; *) cur=$what ;; esac
    if [ "$kind" = cask ] && why=$(cask_outside "$b" "$name"); then
      printf '%s\t%s\t%s\n' "$kind" "$name" "$why, not from Homebrew" >>"$SETUP_RUN/b.skip"
    else
      printf '%s\t%s\t%s\n' "$kind" "$name" "$cur" >>"$SETUP_RUN/b.set"
    fi
  done <"$SETUP_RUN/b.raw"
  B_OK=$((B_TOTAL - $(grep -c . "$SETUP_RUN/b.set") - $(grep -c . "$SETUP_RUN/b.skip")))
  brew_third_party "$file" >"$SETUP_RUN/b.third"
  [ -s "$SETUP_RUN/b.third" ] || return 0
  if ! brew_trusted "$b" >"$SETUP_RUN/b.trusted"; then
    awk -F'\t' -v OFS='\t' '{ print $1, $2, "no trust command" }' "$SETUP_RUN/b.third" >"$SETUP_RUN/b.trust"
    return 0
  fi
  while IFS="$TAB" read -r kind name; do
    tap=${name%/*}
    if [ "$kind" = formula ]; then key=formulae; else key=casks; fi
    if grep -qxF "$key$TAB$name" "$SETUP_RUN/b.trusted" || grep -qxF "taps$TAB$tap" "$SETUP_RUN/b.trusted"; then
      printf '%s\t%s\ttrusted\n' "$kind" "$name"
    else
      printf '%s\t%s\tuntrusted\n' "$kind" "$name"
    fi
  done <"$SETUP_RUN/b.third" >"$SETUP_RUN/b.trust"
}

BREW_LEFT_OUT='install  (left out: already installed outside Homebrew)'

brew_rows() { # REL: print the plan rows from the b.* files
  local kind name cur state
  while IFS="$TAB" read -r kind name cur; do
    row set "$kind $name" "$cur" install
  done <"$SETUP_RUN/b.set"
  while IFS="$TAB" read -r kind name cur; do
    row skip "$kind $name" "$cur" "$BREW_LEFT_OUT"
  done <"$SETUP_RUN/b.skip"
  [ "$B_OK" -gt 0 ] && row ok "${1##*/}: other entries" "$B_OK installed" installed
  while IFS="$TAB" read -r kind name state; do
    case $state in
      trusted) row ok "trust $kind $name" trusted trusted ;;
      untrusted) row set "trust $kind $name" untrusted trusted ;;
      *) row skip "trust $kind $name" 'not checked' "trusted  (this brew has no trust command)" ;;
    esac
  done <"$SETUP_RUN/b.trust"
}

# brewfile PATH: install what the Brewfile lists and is missing; never upgrades.
brewfile() {
  [ $# -eq 1 ] || die "$MODULE: brewfile wants PATH"
  local rel=$1 file="$ROOT/$1" b
  [ -f "$file" ] || die "$MODULE: no Brewfile at $rel"
  brew_validate "$file" "$rel"
  case $MODE in
    describe)
      desc brew "$rel" '' 0 print "($(brew_entries "$file" | grep -c .) entries)" 'prints the brew uninstall and untrust lines for what this tool added'
      [ "${SHOW:-0}" = 1 ] && printf '          %s\n' "$(brew_entries "$file" | tr '\t' ' ' | tr '\n' ',' | sed 's/,$//; s/,/, /g')"
      return 0
      ;;
    undoplan | undo)
      brew_undo
      return 0
      ;;
  esac
  b=$(brew_path)
  if ! brew_status "$file" "$b"; then
    row fail "$rel" "brew bundle check: $B_ERR" installed
    return 0
  fi
  case $MODE in
    plan) brew_rows "$rel" ;;
    apply) brew_apply "$rel" "$file" ;;
  esac
}

brew_apply() { # REL FILE
  local rel=$1 file=$2 b kind name cur state list
  if [ ! -s "$SETUP_RUN/b.set" ] && ! grep -q "${TAB}untrusted\$" "$SETUP_RUN/b.trust"; then
    return 0
  fi
  if ! b=$(brew_path); then
    row fail "$rel" 'Homebrew not found' 'install (the homebrew module installs it)'
    return 0
  fi
  if [ ! -e "$SETUP_RUN/brew-updated" ]; then
    brew_do 1 "$b" update || row fail 'brew update' 'failed' 'up to date'
    : >"$SETUP_RUN/brew-updated"
    brew_status "$file" "$b" || {
      row fail "$rel" "brew bundle check: $B_ERR" installed
      return 0
    }
  fi
  while IFS="$TAB" read -r kind name cur; do
    row skip "$kind $name" "$cur" "$BREW_LEFT_OUT"
  done <"$SETUP_RUN/b.skip"
  while IFS="$TAB" read -r kind name state; do
    [ "$state" = untrusted ] || continue
    if brew_do 0 "$b" trust "--$kind" "$name"; then
      receipt_add "trust $kind $name" untrusted ''
      row done "trust $kind $name" untrusted trusted
    else
      row fail "trust $kind $name" untrusted "$(run_error)"
    fi
  done <"$SETUP_RUN/b.trust"
  [ -s "$SETUP_RUN/b.set" ] || return 0
  # Only the missing entries go to brew bundle, so apply does what plan showed.
  list="$SETUP_RUN/apply.Brewfile"
  {
    brew_entries "$file" | awk -F'\t' '$1 == "tap" { printf "tap \"%s\"\n", $2 }'
    awk -F'\t' '$1 != "tap" { printf "%s \"%s\"\n", $1, $2 }' "$SETUP_RUN/b.set"
  } >"$list"
  cp "$SETUP_RUN/b.set" "$SETUP_RUN/b.before"
  brew_do 1 "$b" bundle --no-upgrade --file "$list"
  if ! brew_status "$file" "$b"; then
    row fail "$rel" "brew bundle check: $B_ERR" 'installed (not verified; no receipts kept)'
    return 0
  fi
  while IFS="$TAB" read -r kind name cur; do
    if grep -qF "$kind$TAB$name$TAB" "$SETUP_RUN/b.set" "$SETUP_RUN/b.skip"; then
      row fail "$kind $name" "$cur" 'still missing after brew bundle'
    else
      receipt_add "$kind $name" "$cur" ''
      row done "$kind $name" "$cur" installed
    fi
  done <"$SETUP_RUN/b.before"
}

brew_undo() {
  local id cmd ids
  ids=$(receipt_ids)
  while IFS= read -r id; do
    case $id in
      'cask '*) cmd="brew uninstall --cask ${id#cask }" ;;
      'brew '*) cmd="brew uninstall ${id#brew }" ;;
      'tap '*) cmd="brew untap ${id#tap }" ;;
      'trust formula '*) cmd="brew untrust --formula ${id#trust formula }" ;;
      'trust cask '*) cmd="brew untrust --cask ${id#trust cask }" ;;
      *) continue ;;
    esac
    receipt_get "$id" || continue
    case $MODE in
      undoplan) row undo "$id" "added by this tool" "printed command" ;;
      undo)
        receipt_drop "$id"
        row done "$id" "added by this tool" "by hand: $cmd"
        ;;
    esac
  done <<EOF
$ids
EOF
}

# ---------------------------------------------------------------- links

# link_dest LINK: where LINK points, absolute, with the part that exists
# resolved physically (dotbot compares realpath results).
link_dest() {
  local t d rest=''
  t=$(readlink "$1")
  case $t in /*) ;; *) t="$(dirname "$1")/$t" ;; esac
  d=$t
  while [ ! -d "$d" ] && [ "$d" != / ] && [ "$d" != . ]; do
    rest="/${d##*/}$rest"
    d=$(dirname "$d")
  done
  printf '%s%s\n' "$(cd "$d" 2>/dev/null && pwd -P)" "$rest"
}

# clean_scan CONF: the links dotbot's clean directive would delete: broken
# symlinks directly in each target folder that point into this repo. Only the
# one-line form `- clean: [targets]` is understood; returns 1 on any other.
clean_scan() {
  local conf=$1 list t dir p dest
  if grep -E '(^|[[:space:]-])clean[[:space:]]*:' "$conf" | grep -q -v -E '^- clean: \[[^]]*\][[:space:]]*$'; then
    L_ERR="the clean directive in $conf is not the one-line '- clean: [...]' form; the plan cannot preview it"
    return 1
  fi
  list=$(sed -n 's/^- clean: \[\([^]]*\)\].*/\1/p' "$conf" | tr ',' '\n' | tr -d "\"' ")
  for t in $list; do
    case $t in
      '~') dir=$HOME ;;
      '~/'*) dir="$HOME/${t#\~/}" ;;
      /*) dir=$t ;;
      *)
        L_ERR="clean target '$t' in $conf is not understood; the plan cannot preview it"
        return 1
        ;;
    esac
    [ -d "$dir" ] || continue
    for p in "$dir"/* "$dir"/.[!.]* "$dir"/..?*; do
      [ -L "$p" ] && [ ! -e "$p" ] || continue
      dest=$(link_dest "$p")
      case $dest in
        "$ROOT"/*) printf 'clean\t%s\tremove\tbroken link to %s\t\n' "$p" "$dest" ;;
      esac
    done
  done
}

# links_scan CONF: dotbot runs against an empty temporary HOME; every link and
# folder it creates there is compared with the same path in the real HOME.
# Writes $SETUP_RUN/l.rows ("kind<TAB>path<TAB>class<TAB>current<TAB>target").
links_scan() {
  local conf=$1 tmp rel real want class cur
  [ -x "$ROOT/dotbot/bin/dotbot" ] || {
    L_ERR='dotbot is not fetched; run: git submodule update --init --recursive'
    return 1
  }
  # dotbot needs python; without the Command Line Tools /usr/bin/python3 opens an install dialog.
  xcode-select -p >/dev/null 2>&1 || {
    L_ERR='needs the Command Line Tools: xcode-select --install'
    return 1
  }
  tmp=$(mktemp -d "$SETUP_RUN/home.XXXXXX")
  if ! HOME=$tmp PYTHONDONTWRITEBYTECODE=1 "$ROOT/dotbot/bin/dotbot" -d "$ROOT" -c "$ROOT/$conf" --except shell >"$SETUP_RUN/dotbot.log" 2>&1; then
    L_ERR="dotbot dry run failed: $(tail -1 "$SETUP_RUN/dotbot.log")"
    return 1
  fi
  clean_scan "$ROOT/$conf" >"$SETUP_RUN/l.clean" || return 1
  (cd "$tmp" && find . -mindepth 1 \( -type l -o -type d \) | sed 's|^\./||' | sort) >"$SETUP_RUN/l.paths"
  while IFS= read -r rel; do
    real="$HOME/$rel"
    if [ -L "$tmp/$rel" ]; then
      want=$(readlink "$tmp/$rel")
      if [ -L "$real" ]; then
        cur="link to $(readlink "$real")"
        if [ "$(readlink "$real")" = "$want" ]; then class=ok; else class=relink; fi
      elif [ -d "$real" ]; then
        class=replace cur='real folder'
      elif [ -e "$real" ]; then
        class=replace cur='real file'
      else
        class=create cur=missing
      fi
      printf 'link\t%s\t%s\t%s\t%s\n' "$rel" "$class" "$cur" "$want"
    else
      if [ -d "$real" ]; then
        class=ok cur=folder
      elif [ -e "$real" ] || [ -L "$real" ]; then
        class=blocked cur='not a folder'
      else
        class=create cur=missing
      fi
      printf 'dir\t%s\t%s\t%s\tfolder\n' "$rel" "$class" "$cur"
    fi
  done <"$SETUP_RUN/l.paths" >"$SETUP_RUN/l.rows"
  cat "$SETUP_RUN/l.clean" >>"$SETUP_RUN/l.rows"
}

links_rows() { # STATUS-FOR-CHANGES, reading l.rows lines on stdin
  local kind rel class cur want st tgt
  while IFS="$TAB" read -r kind rel class cur want; do
    case $class in ok) st=ok ;; blocked) st=fail ;; *) st=$1 ;; esac
    case $cur in 'link to '* | 'broken link to '*) cur="${cur%% to *} to $(tildify "${cur#* to }")" ;; esac
    if [ "$kind" = clean ]; then
      row "$st" "$(tildify "$rel")" "$cur" removed
      continue
    elif [ "$kind" = link ]; then
      want=$(tildify "$want")
      case $class in
        ok) tgt="link to $want" ;;
        relink) tgt="relink to $want" ;;
        replace) tgt="replace: contents deleted, then link to $want" ;;
        *) tgt="create link to $want" ;;
      esac
    else
      case $class in
        ok) tgt=folder ;;
        blocked) tgt='folder (dotbot cannot create it)' ;;
        *) tgt='create folder' ;;
      esac
    fi
    row "$st" "~/$rel" "$cur" "$tgt"
  done
}

# links CONF: symlinks and folders from a dotbot config, applied with ./install.
links() {
  [ $# -eq 1 ] || die "$MODULE: links wants CONFIG"
  local conf=$1 home_root='' kind rel class cur want
  case $MODE in
    describe)
      desc links "$conf" '' 0 print '(symlinks and folders, applied with ./install)' 'prints the links to remove and what was there before'
      return 0
      ;;
    undoplan | undo)
      links_undo
      return 0
      ;;
  esac
  if [ ! -f "$ROOT/$conf" ]; then
    [ "$MODE" = plan ] && row fail "links from $conf" "no $conf in this copy" linked
    return 0
  fi
  if ! links_scan "$conf"; then
    row fail "links from $conf" "$L_ERR" 'linked'
    return 0
  fi
  [ -d "$HOME/.dotfiles" ] && home_root=$(cd "$HOME/.dotfiles" && pwd -P)
  case $MODE in
    plan)
      if [ "$home_root" != "$ROOT" ]; then
        row_text note "planned from $(tildify "$ROOT"), not ~/.dotfiles: apply refuses here, because zsh/zshrc sources ~/.dotfiles by path. The rows show what an apply from this checkout would do."
      fi
      links_rows set <"$SETUP_RUN/l.rows"
      ;;
    apply)
      grep -q -v -E "^[^$TAB]*$TAB[^$TAB]*$TAB(ok|blocked)$TAB" "$SETUP_RUN/l.rows" || return 0
      if [ "$home_root" != "$ROOT" ]; then
        row fail "links from $conf" "run from $(tildify "$ROOT")" 'run from ~/.dotfiles (refused)'
        return 0
      fi
      if grep -q -E "^[^$TAB]*$TAB[^$TAB]*${TAB}blocked$TAB" "$SETUP_RUN/l.rows"; then
        row fail "links from $conf" 'a row is blocked' 'fix the blocked rows first (refused)'
        return 0
      fi
      printf '  %s  ./install: output follows\n' "$(status_word run)"
      if ! sys_run 1 0 "\"$ROOT/install\""; then
        # dotbot goes on past a failure, so some planned changes may have been
        # made: scan again, and show and keep a receipt for each one now in place.
        cp "$SETUP_RUN/l.rows" "$SETUP_RUN/l.plan"
        if ! links_scan "$conf"; then
          row fail "links from $conf" "./install failed; no receipts kept: $L_ERR" linked
          return 0
        fi
        : >"$SETUP_RUN/l.done"
        while IFS="$TAB" read -r kind rel class cur want; do
          case $class in ok | blocked) continue ;; esac
          links_in_place "$kind" "$rel" "$SETUP_RUN/l.rows" || continue
          printf '%s\t%s\t%s\t%s\t%s\n' "$kind" "$rel" "$class" "$cur" "$want" >>"$SETUP_RUN/l.done"
          links_receipt "$kind" "$rel" "$class" "$cur"
        done <"$SETUP_RUN/l.plan"
        links_rows done <"$SETUP_RUN/l.done"
        row fail "links from $conf" './install failed' linked
        return 0
      fi
      while IFS="$TAB" read -r kind rel class cur want; do
        case $class in ok | blocked) continue ;; esac
        links_receipt "$kind" "$rel" "$class" "$cur"
      done <"$SETUP_RUN/l.rows"
      grep -v -E "^[^$TAB]*$TAB[^$TAB]*$TAB(ok|blocked)$TAB" "$SETUP_RUN/l.rows" >"$SETUP_RUN/l.done"
      links_rows done <"$SETUP_RUN/l.done"
      ;;
  esac
}

links_in_place() { # KIND REL ROWS: is that planned change in place in a fresh scan?
  K=$1 R=$2 awk -F'\t' '
    $1 == ENVIRON["K"] && $2 == ENVIRON["R"] { seen = 1; if ($3 == "ok") ok = 1 }
    END { if (ENVIRON["K"] == "clean") exit seen; exit !ok }' "$3"
}

links_receipt() { # KIND REL CLASS CURRENT
  local id
  if [ "$1" = clean ]; then id="clean $(tildify "$2")"; else id="$1 ~/$2"; fi
  receipt_add "$id" "$3" "$4"
}

links_undo() {
  local id cmd ids path
  ids=$(receipt_ids)
  while IFS= read -r id; do
    case $id in 'link '* | 'dir '* | 'clean '*) ;; *) continue ;; esac
    receipt_get "$id" || continue
    path=${id#* }
    case $id in
      'dir '*) cmd="rmdir $path (if empty)" ;;
      'clean '*) cmd="ln -s ${R_VALUE#broken link to } $path (it was already broken)" ;;
      *)
        case $R_VALUE in
          'link to '*) cmd="ln -sfn ${R_VALUE#link to } $path" ;;
          missing) cmd="rm $path" ;;
          *) cmd="rm $path; it was a $R_VALUE that dotbot deleted, so restore it from a backup" ;;
        esac
        ;;
    esac
    case $MODE in
      undoplan) row undo "$id" "$R_VALUE before" 'printed command' ;;
      undo)
        receipt_drop "$id"
        row done "$id" "$R_VALUE before" "by hand: $cmd"
        ;;
    esac
  done <<EOF
$ids
EOF
}

# ---------------------------------------------------------------- names

profile_file() { printf '%s/profiles/%s' "$SETUP_DIR" "$1"; }
module_file() { printf '%s/modules/%s.sh' "$SETUP_DIR" "$1"; }

# resolve NAME [DEPTH]: the modules NAME stands for, in order, one per line
resolve() {
  local n=$1 depth=${2:-0} line
  case $n in '' | *[!a-z0-9-]*) die "not a profile or module name: '$n'" ;; esac
  [ "$depth" -lt 8 ] || die "profiles nest too deep at '$n' (does a profile include itself?)"
  if [ -f "$(profile_file "$n")" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      line=$(printf '%s' "${line%%#*}" | tr -d '[:space:]')
      [ -n "$line" ] || continue
      resolve "$line" $((depth + 1)) || return 1
    done <"$(profile_file "$n")"
  elif [ -f "$(module_file "$n")" ]; then
    printf '%s\n' "$n"
  else
    printf 'setup: unknown profile or module: %s (./setup list shows them)\n' "$n" >&2
    return 1
  fi
}

resolve_all() { # NAMES...: sets MODULES, each module once at its first position
  local n m out
  MODULES=''
  [ $# -gt 0 ] || die 'name at least one profile or module (./setup list shows them)'
  for n in "$@"; do
    out=$(resolve "$n") || exit 2
    for m in $out; do
      case " $MODULES " in *" $m "*) ;; *) MODULES="$MODULES $m" ;; esac
    done
  done
  MODULES=${MODULES# }
}

module_meta() { # NAME: sets M_ABOUT and M_WHY
  local f
  f=$(module_file "$1")
  M_ABOUT=$(sed -n 's/^# about: *//p' "$f" | head -1)
  M_WHY=$(sed -n 's/^# why: *//p' "$f" | head -1)
  [ -n "$M_ABOUT" ] || die "module $1 has no '# about:' line"
  [ -n "$M_WHY" ] || die "module $1 has no '# why:' line"
}

run_module() { # NAME MODE
  (
    MODULE=$1 MODE=$2 MOD_SET=0 MOD_CHANGED=0 MOD_RESTART='' MOD_LOGOUT=''
    # shellcheck disable=SC1090
    . "$(module_file "$1")"
    module_end
  )
}

validate() { # MODULES...: load each in describe mode, which reads nothing
  local m
  for m in "$@"; do
    module_meta "$m"
    run_module "$m" describe >/dev/null || die "module $m failed to load"
  done
}

all_modules() { # every module: profile order first, then the rest by name
  local p m f out order=''
  for f in "$SETUP_DIR"/profiles/*; do
    p=${f##*/}
    out=$(resolve "$p") || return 1
    for m in $out; do
      case " $order " in *" $m "*) ;; *) order="$order $m" ;; esac
    done
  done
  for f in "$SETUP_DIR"/modules/*.sh; do
    m=${f##*/}
    m=${m%.sh}
    case " $order " in *" $m "*) ;; *) order="$order $m" ;; esac
  done
  printf '%s\n' "${order# }"
}

profiles_of() { # MODULE: profiles that reach it, comma-separated, or "none"
  local f p out=''
  for f in "$SETUP_DIR"/profiles/*; do
    p=${f##*/}
    [ -f "$SETUP_RUN/prof.$p" ] || resolve "$p" >"$SETUP_RUN/prof.$p" || exit 2
    grep -qx "$1" "$SETUP_RUN/prof.$p" && out="$out${out:+, }$p"
  done
  printf '%s' "${out:-none}"
}

module_sudo() { # MODULE: yes/no, from its describe records
  if awk -F'\t' -v m="$1" '$1 == m && $3 == 1 { f = 1 } END { exit !f }' "$SETUP_RUN/desc"; then echo yes; else echo no; fi
}

module_undo() { # MODULE: one phrase, from its items' undo kinds
  local kinds
  kinds=$(awk -F'\t' -v m="$1" '$1 == m { print $4 }' "$SETUP_RUN/desc" | sort -u | tr '\n' ' ')
  case $kinds in
    *print*) case $kinds in *restore* | *revert*) echo 'partly; prints the rest' ;; *) echo 'prints commands' ;; esac ;;
    *restore* | *revert*) echo yes ;;
    *) echo 'nothing to undo' ;;
  esac
}

check_names() {
  local f p
  for f in "$SETUP_DIR"/profiles/*; do
    p=${f##*/}
    [ ! -f "$(module_file "$p")" ] || die "'$p' is both a profile and a module"
  done
}

# ---------------------------------------------------------------- commands

usage() {
  cat <<'EOF'
usage: ./setup list                         modules, who gets them, sudo
       ./setup show <module>                what, why, and every item
       ./setup plan <profile|module>...     dry run: current value → target
       ./setup apply [--yes] <profile|module>...
       ./setup undo [--yes] <profile|module>...
       ./setup readme                       the README module table
EOF
}

cmd_list() {
  local m all
  check_names
  all=$(all_modules) || exit 2
  set -- $all
  validate "$@"
  printf '%-15s %-5s %-18s %s\n' MODULE SUDO PROFILES ABOUT
  for m in "$@"; do
    module_meta "$m"
    printf '%-15s %-5s %-18s %s\n' "$m" "$(module_sudo "$m")" "$(profiles_of "$m")" "$M_ABOUT"
  done
}

cmd_readme() {
  local m all
  check_names
  all=$(all_modules) || exit 2
  set -- $all
  validate "$@"
  printf '| Module | What it does | Why | Profiles | sudo | Undo |\n'
  printf '|---|---|---|---|---|---|\n'
  for m in "$@"; do
    module_meta "$m"
    printf '| `%s` | %s | %s | %s | %s | %s |\n' "$m" "$M_ABOUT" "$M_WHY" "$(profiles_of "$m")" "$(module_sudo "$m")" "$(module_undo "$m")"
  done
}

cmd_show() {
  [ $# -eq 1 ] || die 'usage: ./setup show <module>'
  local m=$1
  case $m in '' | *[!a-z0-9-]*) die "not a module name: '$m'" ;; esac
  if [ -f "$(profile_file "$m")" ]; then
    printf '%s is a profile: %s\n' "$m" "$(resolve "$m" | tr '\n' ' ')"
    return 0
  fi
  [ -f "$(module_file "$m")" ] || die "unknown module: $m (./setup list shows them)"
  module_meta "$m"
  run_module "$m" describe >/dev/null || exit 2
  printf '%s%s%s: %s\n' "$C_BOLD" "$m" "$C_RESET" "$M_ABOUT"
  printf '  why:      %s\n' "$M_WHY"
  printf '  profiles: %s\n' "$(profiles_of "$m")"
  printf '  sudo:     %s\n' "$(module_sudo "$m")"
  printf '  undo:     %s (only items this tool changed, from its receipts)\n' "$(module_undo "$m")"
  printf '  items:\n'
  SHOW=1 run_module "$m" describe
}

plan_pass() { # print the plan of every module in $MODULES
  local m
  printf 'This Mac: %s\n' "$(facts_line)"
  env | grep -q '^SETUP_FACT_' && printf 'Facts overridden: %s\n' "$(env | grep '^SETUP_FACT_' | tr '\n' ' ')"
  for m in $MODULES; do
    module_meta "$m"
    printf '\n%s%s%s: %s\n' "$C_BOLD" "$m" "$C_RESET" "$M_ABOUT"
    run_module "$m" plan || exit 2
  done
}

plan_summary() { # TITLE
  local line
  printf '\n%s: %s ok · %s set · %s todo · %s skip · %s fail\n' "$1" \
    "$(count_rows plan ok)" "$(count_rows plan set)" "$(count_rows plan todo)" "$(count_rows plan skip)" "$(count_rows plan fail)"
  if [ "$(awk -F'\t' '$1 == "set" && $4 == 1' "$SETUP_RUN/rows.plan" | grep -c .)" -gt 0 ]; then
    printf 'Changes that need the Mac login password [sudo]:\n'
    awk -F'\t' '$1 == "set" && $4 == 1 { print "  " $2 ": " $3 }' "$SETUP_RUN/rows.plan"
  fi
  line=$(queued plan restart | tr '\n' ' ')
  [ -n "$line" ] && printf 'Restarted after apply: %s\n' "${line% }"
  line=$(queued plan logout | awk '{ printf "%s%s", (NR > 1 ? ", " : ""), $0 }')
  [ -n "$line" ] && printf 'Log out and back in after apply, for: %s\n' "$line"
  queued plan reboot | cut -f2- | sed 's/^/After apply: /'
  if [ -s "$SETUP_RUN/q.plan.manual" ]; then
    printf 'By hand:\n'
    queued plan manual | sed 's/^/  - /'
  fi
  return 0
}

# reboot_lines RERUN: restart lines from the apply pass, plus those the plan
# found in modules the apply pass did not run again.
reboot_lines() {
  {
    queued apply reboot
    queued plan reboot | while IFS="$TAB" read -r m t; do
      case " $1 " in *" $m "*) ;; *) printf '%s\t%s\n' "$m" "$t" ;; esac
    done
  } | cut -f2- | awk '!seen[$0]++'
}

closing_lists() { # MODE [RERUN]: MODE's logout queue; for apply, RERUN is the modules applied
  local line
  line=$(queued "$1" logout | awk '{ printf "%s%s", (NR > 1 ? ", " : ""), $0 }')
  [ -n "$line" ] && printf '\nLog out and back in to apply: %s\n' "$line"
  if [ "$1" = apply ]; then
    line=$(reboot_lines "$2")
    [ -n "$line" ] && printf '\n%s\n' "$line"
  fi
  if [ -s "$SETUP_RUN/q.plan.manual" ]; then
    printf '\nStill to do by hand:\n'
    queued plan manual | sed 's/^/  - /'
  fi
  return 0
}

cmd_plan() {
  resolve_all "$@"
  validate $MODULES
  facts_init
  printf 'Plan for: %s. Nothing is changed.\n' "$*"
  plan_pass
  plan_summary "Plan $*"
  printf 'Nothing was changed. To apply: ./setup apply %s\n' "$*"
  [ "$(count_rows plan fail)" -eq 0 ]
}

refuse_unsafe() { # VERB
  local v c p d
  # As root, defaults would write root's preferences and the Homebrew installer would refuse.
  [ "$(id -u)" -ne 0 ] || die "refusing to $1 as root: run it without sudo; it asks for the password when it needs it"
  v=$(env | sed -n 's/^\(SETUP_FACT_[A-Z_]*\)=.*/\1/p' | tr '\n' ' ')
  [ -z "$v" ] || die "refusing to $1 while fact overrides are set (${v% }): they are for plan only"
  [ "${SETUP_TEST:-}" = 1 ] || return 0
  [ -n "${SETUP_TEST_LOG:-}" ] || die "refusing to $1: SETUP_TEST=1 needs SETUP_TEST_LOG"
  for c in defaults sudo killall; do
    p=$(command -v "$c" 2>/dev/null)
    d=''
    [ -n "$p" ] && d=$(cd "$(dirname "$p")" 2>/dev/null && pwd -P)
    case "$d/" in
      "$SETUP_DIR/test/"*) ;;
      *) die "refusing to $1 under SETUP_TEST=1: $c resolves to '${p:-nothing}', not a shim in setup.d/test/" ;;
    esac
  done
}

confirm() { # PROMPT
  local a
  [ "$YES" = 1 ] && return 0
  [ -t 0 ] || die 'not a terminal; rerun with --yes to go ahead without asking'
  printf '%s [y/N] ' "$1"
  read -r a
  case $a in y | Y | yes | YES) return 0 ;; esac
  return 1
}

need_admin() { # COUNT
  id -Gn 2>/dev/null | tr ' ' '\n' | grep -qx admin && return 0
  die "$1 of these changes need an administrator account (marked [sudo]), and $(id -un) is not one. Log in as an administrator, or name only modules without sudo (./setup list shows them). Nothing was changed."
}

sudo_begin() {
  printf 'Your Mac login password is needed. Nothing appears while you type; press Return when done.\n'
  sudo -v || die 'sudo did not accept the password; stopped before the first change'
  (
    while sleep 50; do
      kill -0 $$ 2>/dev/null || exit 0
      sudo -n true 2>/dev/null || exit 0
    done
  ) >/dev/null 2>&1 &
  KEEPALIVE_PID=$!
}

modules_with() { # MODE STATUS: modules in $MODULES order having a row of STATUS
  local m
  for m in $MODULES; do
    awk -F'\t' -v m="$m" -v s="$2" '$1 == s && $2 == m { f = 1 } END { exit !f }' "$SETUP_RUN/rows.$1" 2>/dev/null && printf '%s ' "$m"
  done
}

cmd_apply() {
  local n npw m rerun
  refuse_unsafe apply
  resolve_all "$@"
  validate $MODULES
  facts_init
  printf 'Apply: %s. First, the plan:\n' "$*"
  plan_pass
  plan_summary "Plan $*"
  n=$(count_rows plan set)
  if [ "$n" -eq 0 ]; then
    printf '\nNothing to change.\n'
    [ "$(count_rows plan fail)" -eq 0 ]
    return
  fi
  npw=$(awk -F'\t' '$1 == "set" && $4 == 1' "$SETUP_RUN/rows.plan" | grep -c .)
  echo
  [ "$npw" -gt 0 ] && need_admin "$npw"
  confirm "Apply $n changes?" || {
    printf 'Nothing was changed.\n'
    return 0
  }
  killall 'System Settings' >/dev/null 2>&1
  [ "$npw" -gt 0 ] && sudo_begin
  printf '\nApplying:\n'
  rerun=$(modules_with plan set)
  for m in $rerun; do
    printf '\n%s%s%s\n' "$C_BOLD" "$m" "$C_RESET"
    run_module "$m" apply || exit 2
  done
  MODE=apply
  run_restarts
  closing_lists apply "$rerun"
  printf '\nDone: %s changed, %s failed.\n' "$(count_rows apply done)" "$(($(count_rows apply fail) + $(count_rows plan fail)))"
  [ "$(count_rows apply fail)" -eq 0 ] && [ "$(count_rows plan fail)" -eq 0 ]
}

cmd_undo() {
  local n npw m
  refuse_unsafe undo
  resolve_all "$@"
  validate $MODULES
  facts_init
  if [ ! -f "$RECEIPTS" ]; then
    printf 'Nothing to undo: no receipts at %s\n' "$(tildify "$RECEIPTS")"
    return 0
  fi
  printf 'Undo: %s. Only items this tool changed are reverted, to their state before its first change.\n' "$*"
  for m in $MODULES; do
    run_module "$m" undoplan >"$SETUP_RUN/undo.$m" || exit 2
    if [ -s "$SETUP_RUN/undo.$m" ]; then
      printf '\n%s%s%s\n' "$C_BOLD" "$m" "$C_RESET"
      cat "$SETUP_RUN/undo.$m"
    fi
  done
  n=$(count_rows undoplan undo)
  if [ "$n" -eq 0 ]; then
    printf 'Nothing to undo for: %s\n' "$*"
    return 0
  fi
  npw=$(awk -F'\t' '$1 == "undo" && $4 == 1' "$SETUP_RUN/rows.undoplan" | grep -c .)
  echo
  [ "$npw" -gt 0 ] && need_admin "$npw"
  confirm "Undo $n changes?" || {
    printf 'Nothing was changed.\n'
    return 0
  }
  killall 'System Settings' >/dev/null 2>&1
  [ "$npw" -gt 0 ] && sudo_begin
  printf '\nUndoing:\n'
  for m in $(modules_with undoplan undo); do
    printf '\n%s%s%s\n' "$C_BOLD" "$m" "$C_RESET"
    run_module "$m" undo || exit 2
  done
  MODE=undo
  run_restarts
  closing_lists undo
  printf '\nDone: %s reverted, %s failed.\n' "$(count_rows undo done)" "$(count_rows undo fail)"
  [ "$(count_rows undo fail)" -eq 0 ]
}

run_exit() {
  [ -n "${KEEPALIVE_PID:-}" ] && kill "$KEEPALIVE_PID" 2>/dev/null
  case ${SETUP_RUN:-} in */setup-run.??????) rm -rf "$SETUP_RUN" ;; esac
}

main() {
  local cmd=${1:-} a names=''
  [ $# -gt 0 ] && shift
  YES=0
  for a in "$@"; do
    case $a in
      --yes | -y) YES=1 ;;
      -*) die "unknown option: $a" ;;
      *) names="$names $a" ;;
    esac
  done
  SETUP_RUN=$(mktemp -d "${TMPDIR:-/tmp}/setup-run.XXXXXX") || die 'cannot create a temporary directory'
  export SETUP_RUN
  trap run_exit EXIT
  trap 'exit 130' INT TERM
  case $cmd in
    list) cmd_list ;;
    show) cmd_show $names ;;
    plan) cmd_plan $names ;;
    apply) cmd_apply $names ;;
    undo) cmd_undo $names ;;
    readme) cmd_readme ;;
    help | -h | --help) usage ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
}
