# Setup design: decisions and why

How to use the setup is in the [README](../README.md). This file records what was decided and why, so a later change can tell a deliberate choice from an accident.

## Goals and constraints

- **A Mac in daily use.** `common` is written for a Mac someone already uses, with their own settings and apps. It is not a blank Mac, so nothing may assume Apple defaults.
- **Dry run first.** `plan` prints each item's live value next to its target and changes nothing. It is what gets read to the Mac's user before anything is applied.
- **Self-describing.** For each module the runner prints what it does, why, which profiles list it, whether it needs sudo, and how it is undone. Sudo and undo are derived from the module's items, and the README table is printed from the same source, so none of it can drift.
- **The shell and git config are not touched.** `zsh/zshrc` and `gitconfig/` are linked only by `./install`, which the `dotfiles` module runs; `scripts/` is sourced from `zsh/aliases/`.
- **Runs on a stock Mac.** `common` runs under `/bin/bash` 3.2 from an unzipped copy of `setup` and `setup.d`, with no git, python or dotbot. The runner needs no network; only `homebrew` and `apps-common` download.

Bash 3.2 rules the code follows: no associative arrays, `mapfile`, `${x,,}`, `[[ -v ]]` or `declare -g`, and no `"${arr[@]}"` on an array that may be empty. Lists are strings and files.

## Layout

```
setup                          entry point
setup.d/lib.sh                 the runner and the item helpers
setup.d/modules/<name>.sh      "# about:" and "# why:" lines, then helper calls and CHECK functions
setup.d/profiles/<name>        ordered names, one per line; each is a profile or a module
setup.d/brew/*.Brewfile        plain tap/brew/cask lines
setup.d/test/                  shims and the test script
install, install.conf.yaml     dotbot; the dotfiles module calls them
```

"The old script" below means the plain list of `defaults write` lines this setup replaced.

## Runner

### Names and profiles

- A name is a profile if `profiles/<name>` exists, otherwise a module. Profile lines resolve the same way, so a profile can include another. A module reached twice runs once, at its first position.
- **Who gets a module is recorded in one place: the profile files.** Module names say what a module does, not who it is for, and modules do not list their profiles. Recording it in several places is how they come to disagree.
- `list` fails if a name is both a profile and a module, or if a module has no `about` or `why`.

### Items

Every helper implements every mode (describe, plan, apply, undo), so a module is only a list of items.

| Helper | For | Undo |
|---|---|---|
| `pref` | one `defaults` key | restores the prior value and type, or deletes the key if it was absent |
| `step` | anything else, through a CHECK function and APPLY/UNDO commands | runs UNDO with `$PRIOR`, or prints text for `print:` |
| `manual` | something a person must do; check only | nothing |
| `needs_restart` | a state only a restart clears; check only. Plan lists its line as what follows apply; apply checks again and lists it only if the module's change took | nothing |
| `brewfile` | a Brewfile | prints the uninstall commands |
| `links` | the dotbot config | prints the links to remove |
| `on` | gates a whole module on machine facts, with a hint for the hand route | |
| `restart`, `logout` | what must restart, or needs a logout, after a change | |

Decisions behind them:

- **CHECK functions print one normalised value and return 0 (at target), 1 (needs a change) or 2 and up (cannot tell).** Raw command output never equals a wanted string, and several tools exit non-zero for "not set yet" (`nvram` on an unset variable), which is a value, not an error. "Cannot tell" is a `fail` row and is never applied.
- **For `pref`, the stored type counts.** An integer stored where a boolean is wanted is a `set` row. The old script wrote several booleans as integers.
- **Booleans are written as `true`/`false`**, in apply and in undo. `defaults` reads a boolean back as `1`/`0` but accepts only yes, true, no or false after `-bool`; anything else prints its usage and writes nothing.
- **An UNDO that can face more than one prior state uses `$PRIOR`.** A fixed UNDO is used only where the CHECK marks a single state as needing a change (firewall off, `sudo_local` absent, daemon enabled), so the fixed command restores exactly that state.
- **A step's APPLY must fail when its work fails.** The Homebrew installer is downloaded to a file and checked before it runs, because `bash -c "$(curl …)"` exits 0 when the download fails, and the step succeeds only if brew is there afterwards.
- **CHECK runs again after APPLY.** Some tools exit 0 without making the change, so a step whose CHECK does not then return 0 is a `fail` row, its receipt kept for undo. Under `SETUP_TEST=1` the APPLY is only recorded, so this second CHECK is skipped there and the harness does not reach it.
- **A `pref` whose current value is a dictionary, array, date or data is a `fail` row** and is left alone: it could not be restored from a one-line receipt.
- **Gates take machine facts only**: macOS major version, chip, laptop, Touch ID enrolled. They never test for Homebrew or an app, because those change during a run. Homebrew is looked up each time it is needed.
- **Sudo comes in two forms.** `-sudo` runs the command under `sudo`. `-admin` runs it as the user but still counts as a password item, for commands that refuse to run as root and use the cached sudo timestamp themselves: the Homebrew installer. Both make the runner ask for the password once, up front.
- **`-tty`** runs a command attached to the terminal, for anything that prompts: the Homebrew installer, `sysadminctl … -password -`.
- **`-brew`** makes a step's APPLY and UNDO brew arguments, run with the brew found at that moment through the same guarded path as the Brewfile commands (the test fixture's `psql on PATH`: `brew link --force libpq`).
- **A module body runs in a subshell**, so anything that must outlive it (row counts, the restart, logout and manual queues) lives in files under a per-run temporary directory.
- **Describe mode reads nothing from the Mac.** A module's top level holds only helper calls, assignments, function definitions and `on`, which is what makes `list`, `show` and `readme` safe anywhere.

### Apply

1. Print the plan. Stop if nothing is `set`.
2. If any `set` row needs sudo: check the account is an administrator, and stop with an explanation if not. Otherwise say that the login password is needed and that nothing appears while typing.
3. Ask `Apply N changes?`.
4. Close System Settings with `killall`. Not `osascript`, which raises an Automation permission prompt.
5. `sudo -v` once, kept alive for the run.
6. Write the `set` rows, module by module. Modules with no `set` row are not run again.
7. Run the queued restarts, then print the hand steps and the logout list.

Restarts and logout notes are queued only by a module that changed something.

### Receipts and undo

- Each write appends a line to `~/Library/Application Support/dotfiles-setup/receipts.tsv`: module, item, prior type, prior value. The file sits outside the setup folder so it survives deleting an unzipped copy.
- `undo` restores the **earliest** receipt of an item, the state before this tool first touched it, then drops that item's receipts.
- **An item with no receipt is left alone.** Undoing `security` on a Mac whose firewall was already on does not turn it off.
- Resetting to Apple's defaults instead was rejected: on a laptop in use, its user's prior value is not Apple's default.
- For installs (Homebrew, Brewfile entries, links) undo prints the commands and runs nothing. Uninstalling apps or removing links is not something to do unasked.

### Homebrew

- Brewfiles hold plain `tap`/`brew`/`cask` lines so the runner can read them in bash; `list` rejects anything else.
- Plan runs `brew bundle check --no-upgrade` and shows one row per missing entry. Without Homebrew, every entry reads `absent → install`. These reads change no package, tap or trust state; brew itself moves the timestamp of its own `.git` folder on every command it runs, including `brew --version`.
- **Apply never upgrades.** `brew bundle` upgrades by default; apply passes `--no-upgrade` and hands it only the missing entries, so it does what the plan showed.
- **Trust is per formula, never per tap.** Homebrew 6 refuses to load anything from an untrusted third-party tap. For each Brewfile entry named `tap/name` from a tap outside `homebrew/`, plan compares `brew trust --json=v1` and apply runs `brew trust --formula <tap>/<name>` (or `--cask`). Trusting the whole tap would also trust whatever that tap adds later. Undo prints the matching `brew untrust`.
- **A failed `brew bundle check` is a `fail` row in apply as in plan.** On a Mac where Homebrew is installed mid-run, apply's check is the first one that runs; staying silent there would end the run with "0 failed" and no apps.
- **An app installed outside Homebrew is left out**, shown as a `skip` row. Homebrew refuses to replace an app it did not install, and would run a package installer over one that came from a package; on a laptop in use that would be most of `apps-common`. A missing cask counts as present when its `.app` is in `/Applications` or `~/Applications`, or when the package it installs has a receipt (`pkgutil`; Zoom and Tailscale are such casks). The check needs `jq`, which macOS 15 ships.

### Links

- Plan runs dotbot against an empty temporary HOME and compares every link and folder it creates there with the real HOME: `create`, `relink`, or `replace: contents deleted`. The last one exists because `install.conf.yaml` sets `force: true`, which deletes a real file or folder in the way.
- **Apply refuses while a links row is blocked** (a path dotbot must create a folder at is a file). dotbot would still replace files before failing on it, and the run would end in a failed `./install`.
- **After a failed `./install`, links are scanned again.** dotbot goes on past a failure, so each planned change now in place is shown as `done` and gets its receipt. A replace dotbot did only in part is not in place and gets none; dotbot's own output above names it. Under `SETUP_TEST=1` `./install` is only recorded and never fails, so the harness does not reach this.
- **Apply refuses unless the checkout is `~/.dotfiles`.** `zsh/zshrc` sources `~/.dotfiles/…` by path; links into another checkout would cut the live shell off from that tree. Plan from elsewhere prints a note and still shows the rows.
- **The plan shows what dotbot's `clean` would delete**: each broken symlink directly in `~` that points into the repo is a `set` row, `broken link → removed`. Only the one-line `- clean: [...]` form in `install.conf.yaml` is understood; any other form is a `fail` row rather than an unseen deletion.

### Test hooks

- `plan` and `list` accept fact overrides: `SETUP_FACT_MACOS=26.1`, `SETUP_FACT_ARCH=x86_64`, `SETUP_FACT_LAPTOP=0`, `SETUP_FACT_TOUCHID=0`, `SETUP_FACT_BREW=none`. One Mac can then show the other branches. `apply` and `undo` refuse to run while any is set.
- `apply` and `undo` refuse to run as root: `defaults` would then write root's preferences. They ask for the password themselves.
- Under `SETUP_TEST=1` step commands are recorded instead of run, the real Homebrew is never found, and `apply`/`undo` refuse unless `defaults`, `sudo` and `killall` resolve to the shims in `setup.d/test/`. `setup.d/test/run` uses this to check apply and undo without writing to the Mac. Its Homebrew cases run against `setup.d/test/fake-brew`, the only brew the runner can find or run in that mode.
- The `defaults` shim rejects what the real tool rejects for the types used here (a `-bool` value other than yes, true, no or false), and is stricter for `-int` and `-float`, where the real tool silently writes 0 for text. A recorded command carries `[PRIOR=…]` only when its text uses `$PRIOR`, so the test can tell an UNDO that restores the prior from one that ignores it.

## Modules

Profiles: `common` is the one profile, the defaults that are safe on anyone's Mac; every other module is run by name. There is no aerials module: disabling the aerial video daemon did not stop its downloads, since launchd still started it at every login.

| Module | Decisions |
|---|---|
| `homebrew` | In `common`: Homebrew is a default. The plan row shows the cost when it is missing, about 2 GB with the Command Line Tools. The installer runs as the user with `NONINTERACTIVE=1`, after the runner's `sudo -v`; it is downloaded to a file first, and the step fails unless brew exists afterwards. |
| `apps-common` | Chrome, WhatsApp, Zoom, VLC. |
| `files` | `AppleShowAllExtensions` is written as a boolean, which is what Finder's checkbox writes. Only `NSNavPanelExpandedStateForSaveMode` is set; the `…2` variant has no trace in macOS 15. |
| `desktop` | The bottom-right corner is cleared only when it is Quick Note (value 14, or unset on macOS 12 and later). Any other value was chosen by the user and stays. |
| `menubar` | Bluetooth and Sound are the `-currentHost com.apple.controlcenter` integers, 18 meaning shown. The old script wrote `NSStatusItem Visible …`, which does not govern them. On macOS 26 these controls moved to a Menu Bar pane and the keys are unverified, so the module skips there and prints the hand route. |
| `security` | The firewall CHECK accepts state 1 or 2, so "block all" is never weakened. FileVault and Find My are `manual`: they involve the user's Apple Account and a recovery-key decision. Their hand texts speak of "the person who uses this Mac", who may not be the one running the setup. |
| `screen-lock` | Its own module, so a profile can leave it out. It uses `sysadminctl -screenLock`, because the old `askForPassword` defaults keys stopped working in macOS 13. Only the "delay is N seconds" output has been seen; any other text is a `fail` row, so apply cannot repeat itself on output it does not understand. |
| `backup` | `manual`. Time Machine may offer to erase the drive it is given, so the instructions ask for an empty drive, set up with its user. |
| `privacy` | AirDrop Contacts Only and no personalised ads. |
| `updates` | The keys live in `/Library/Preferences/com.apple.SoftwareUpdate`, not the user domain, so each needs sudo. Apple's matching management payload is deprecated in macOS 26; the module skips there and prints the hand route. |
| `keyboard` | `KeyRepeat 1` is the author's value and faster than anything System Settings offers (2). Smart quotes and dashes join the three auto-correct keys the old script already turned off. `ApplePressAndHoldEnabled` is left alone: press-and-hold is how č, ć, š and ž are typed. |
| `trackpad` | `Clicking` as a boolean, plus the `-currentHost` `com.apple.mouse.tapBehavior` key the old script missed. |
| `dock` | `size-immutable` is deleted. The old script set it to true; it is a management key that locks the Dock size slider. |
| `finder-view` | Emptying the Trash after 30 days is here, not in `common`, because it deletes files. |
| `quiet` | The Siri menu bar key is `StatusMenuVisible`. The old script wrote the stash key that only matters when Siri is switched back on. |
| `dotfiles` | See Links above. |
| `touchid-sudo` | Writes `/etc/pam.d/sudo_local` from Apple's template (macOS 14 and later; it survives updates). An existing `sudo_local` without the `pam_tid` line is a `fail` row and is not overwritten. Inside tmux, Touch ID also needs `pam_reattach`, which this does not add. |
| `raycast-hotkey` | Disables hotkey 64 (Spotlight) with its real parameters `32, 49, 1048576`. The old script stored hotkey 65's binding there, which would clash with Finder search if 64 were turned back on. Undo restores the prior enabled flag and parameters from the receipt. `defaults` cannot delete one key inside that dictionary, so an absent prior is restored as Apple's default for it (on, at Command-Space), which macOS treats the same. |
| `go-trimpath` | Offered, in no profile. |

### Dropped from the old setup script

- `sudo mdutil -i off`: with no volume named it does nothing and still asks for the password; with one it breaks Spotlight, Finder and Mail search. Raycast only needs the hotkey.
- `_HIHideMenuBar 0`: the default.
- `NSStatusItem Visible Bluetooth` and `… Sound`: the wrong keys.
- `SiriPrefStashedStatusMenuVisible`: the stash, not the setting.
- `VoiceTriggerUserEnabled 0`: the default for anyone who has not enrolled, and it silently undoes the choice of someone who has.
- `size-immutable true`: now deleted instead.

### Considered and left out

- Finder search scope "current folder": a search started from the wrong window finds nothing.
- `DSDontWriteNetworkStores`: it matters only with network shares, and it costs a logout.
- `DSDontWriteUSBStores` and the expanded print panel: no trace of either key in macOS 15.
- A lock-screen message and the computer name: per-machine values, set by hand.
- `pmset` values, low power mode, the default browser, native window tiling, the screenshot folder: taste with no clear default.

## Brewfiles

`common.Brewfile` holds Chrome, WhatsApp, Zoom and VLC. The taps `homebrew/bundle` and `homebrew/cask-versions` are left out: both are deprecated, and tapping them is now a fatal error.

`setup.d/test/fixture.Brewfile`, with the test module `setup.d/test/fixture-apps.sh`, covers what `common` does not: a third-party tap, per-formula trust, casks installed outside Homebrew, and a `-brew` step.

## Adding a module

1. Create `setup.d/modules/<name>.sh`. Start with `# about:` (what it does) and `# why:`, one line each, in words that can be read aloud.
2. Add items with the helpers; `./setup show dock` and the existing modules show the forms. Keep the top level to helper calls, assignments, function definitions and `on`. Quote any fact that holds `<` or `>`.
3. Add the name to a profile, or leave it to be run by name.
4. Run `./setup list` and `./setup plan <name>`, paste the output of `./setup readme` into the README table, and run `bash setup.d/test/run`.
