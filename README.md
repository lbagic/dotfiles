# Dotfiles

zsh and git config for macOS, linked with [dotbot](https://github.com/anishathalye/dotbot), and `./setup`: macOS settings as small modules you can read before they run. Each module says what it changes, why, whether it needs the password, and how it is undone; `plan` shows every change before `apply` makes it, and `undo` puts back what was there.

> **Status: `apply` and `undo` have not yet run on a real Mac.** `plan` has, and the test script runs `apply` and `undo` against fakes. Read the plan first, and see [Tested, and not](#tested-and-not).

## Start

On a new Mac, install git first: `xcode-select --install` (a dialog; about 1.6 GB).

```sh
git clone --recurse-submodules https://github.com/lbagic/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./setup plan common              # dry run: nothing changes
./setup apply common             # the defaults that are safe on anyone's Mac
./setup apply dotfiles           # links ~/.zshrc and ~/.gitconfig with ./install
```

- **An existing `~/.zshrc` or `~/.gitconfig` is deleted** when the links are made (`install.conf.yaml` sets `force: true`), and `undo` cannot bring it back. `plan dotfiles` shows it as `replace: contents deleted`. Move what you want to keep into `~/.zshrc.local` and `~/.gitconfig.local` first.
- The clone must live at `~/.dotfiles`: `zsh/zshrc` sources that path, and `apply` refuses to link from any other checkout.
- **Password, once:** `apply` asks for the Mac login password before its first change that needs `sudo`, and keeps it valid for the run.
- `apply` ends with what is left: the hand steps, "log out and back in" where a setting needs it, and "restart the Mac" where a module says only a restart finishes the job.
- Any other module runs by name: `./setup plan keyboard dock`, then `./setup apply keyboard dock`. `keyboard`, `trackpad`, `dock`, `finder-view` and `quiet` carry the author's taste; read `./setup show <module>` first.

## Your own config

Nothing personal lives in this repo. Put it in files it reads but does not hold:

- `~/.gitconfig.local`: your name and email, and anything per machine; `gitconfig/gitconfig` includes it last. Write to it with `git config --file ~/.gitconfig.local user.email you@example.com`: `git config --global` writes through the link into this repo's `gitconfig/gitconfig`.
- `gitconfig/gitconfig` turns on Git LFS, which needs `brew install git-lfs` in any repo that uses LFS.
- `~/.zshrc.local`: aliases, paths and tools of your own. `zsh/zshrc` sources it last.
- `~/.dotfiles/.env.local`: tokens and other secrets as `export NAME=value`. It is gitignored, and `zsh/zshrc` sources it.

## Commands

```sh
./setup list                        # every module: who gets it, whether it needs sudo
./setup show <module>               # what, why, and each item with its undo
./setup plan <profile|module>...    # dry run: current value → target, nothing changes
./setup apply <profile|module>...   # prints the plan, asks, then writes
./setup undo <profile|module>...    # reverts what apply changed on this Mac
./setup readme                      # the module table below
```

A plan row reads `status  item  current → target`:

| Status | Meaning |
|---|---|
| `ok` | already at target; apply leaves it alone |
| `set` | apply will change it; `[sudo]` marks the ones that need the password |
| `todo` | done by hand; apply only checks it and lists the instructions at the end |
| `skip` | does not apply to this Mac (the row says what it needs) |
| `fail` | could not be read or done; the row carries the message |

`apply` writes only the `set` rows and keeps a receipt of each prior value in `~/Library/Application Support/dotfiles-setup/receipts.tsv`. `undo` restores from those receipts, so it never touches a setting that was already right before `apply` ran. For installs (Homebrew, apps, links) `undo` prints the commands and runs nothing.

## Someone else's Mac

The setup runs on a stock Mac under `/bin/bash` 3.2, from an unzipped copy, with no git:

1. Pack it: `git archive --format=zip --prefix=mac-setup/ -o ~/Desktop/mac-setup.zip HEAD setup setup.d`.
2. AirDrop `mac-setup.zip` to that Mac, open it, and drag the `mac-setup` folder from Downloads into the home folder. (Run from Downloads, Terminal would ask for permission to read that folder.)
3. In Terminal there: `cd ~/mac-setup && bash setup plan common`. Read the plan to the Mac's user in plain words and agree which modules they want; `bash setup show <module>` explains one.
4. Apply what was agreed: `bash setup apply common`, or only some modules, by name. `screen-lock` asks for the login password again at its own prompt, and Homebrew may ask when an app's installer needs it.
5. FileVault, Find My Mac and Time Machine are set up together with the Mac's user. Time Machine may offer to erase the drive it is given, so use an empty one.
6. Keep `~/mac-setup` if they may want `undo` later; the receipts live outside it and survive either way.

## Modules

Printed by `./setup readme`; `setup.d/test/run` fails if this table drifts from it.

<!-- modules:start -->
| Module | What it does | Why | Profiles | sudo | Undo |
|---|---|---|---|---|---|
| `homebrew` | Installs Homebrew if it is missing (with Apple's Command Line Tools, about 2 GB). | The package manager apps-common installs with. | common | yes | prints commands |
| `apps-common` | Installs Chrome, WhatsApp, Zoom and VLC with Homebrew. | Everyday apps. An app already installed outside Homebrew is left as it is. | common | no | prints commands |
| `files` | Finder shows every file extension, the path bar and the status bar; Save dialogs open expanded. | A visible extension unmasks an app posing as a document; the bars show where a file is and how much space is left; the expanded Save dialog shows which folder a file goes to. | common | no | yes |
| `desktop` | A click on the wallpaper no longer hides every window, and the bottom-right screen corner no longer opens Quick Note. | Both fire by accident and look like windows vanishing or a note appearing from nowhere. A corner set to anything else was chosen on purpose and is left alone. | common | no | yes |
| `menubar` | The menu bar shows the battery percentage, Bluetooth and Sound. | Battery left and the two controls reached for most are one click away. | common | no | yes |
| `security` | Turns the firewall on; checks FileVault and Find My, which are set up by hand. | Laptops travel and join public Wi-Fi. A lost Mac should be encrypted and findable; FileVault and Find My involve the user's Apple Account and a recovery key, so they are done together with that person. | common | yes | yes |
| `screen-lock` | The Mac asks for the password as soon as the screen saver starts or the display sleeps. | A laptop left open or lost should not stay usable for an hour. The delay does not stop running work: closing the lid sleeps the Mac whatever it is. | common | no | yes |
| `backup` | Checks that Time Machine has a backup drive; setting one up is done by hand. | A Mac with no backup loses everything with its disk. Time Machine can erase the drive it is given, so a person picks the drive and sets it up with whoever uses the Mac. | common | no | nothing to undo |
| `privacy` | AirDrop accepts only contacts, and Apple's personalised ads are off. | Strangers nearby cannot push files or pictures through AirDrop, and Apple stops using the user's activity for ads. | common | no | yes |
| `updates` | macOS checks for, downloads and installs system, security and App Store updates on its own. | A Mac nobody looks after stays patched. The settings live in a system file, so they need the password. | common | yes | yes |
| `dock` | The Dock hides and shows instantly, holds no recent apps, sits at size 42, no screen corner triggers anything, and its size slider is unlocked. | A layout preference. size-immutable is a management setting that greys out the size slider; this removes that lock. | none | no | yes |
| `dotfiles` | Links ~/.zshrc and the git config into this repo with dotbot. | The shell and git config live in this repo. | none | no | prints commands |
| `finder-view` | Finder opens folders in list view and deletes Trash items older than 30 days. | Preferences. Items in the Trash are gone for good after 30 days. | none | no | yes |
| `go-trimpath` | Go builds strip local file paths from binaries (GOFLAGS=-trimpath). | Offered and left out of every profile: reproducible builds with no home-folder paths in them. | none | no | yes |
| `keyboard` | Fast key repeat, and no automatic capitalisation, double-space period, spelling correction, smart quotes or smart dashes. | Typing preferences; curly quotes and dashes break shell commands and code pasted from documents. KeyRepeat 1 is faster than the fastest setting System Settings offers (2). | none | no | yes |
| `quiet` | No startup chime, and no Siri icon in the menu bar. | A preference. The chime setting lives in NVRAM, so it needs the password. | none | yes | yes |
| `raycast-hotkey` | Turns off the Spotlight shortcut so Command-Space opens Raycast. | For Raycast bound to Command-Space. The disabled shortcut keeps Spotlight's own keys, so turning it back on does not clash with Finder search. | none | no | yes |
| `touchid-sudo` | sudo accepts Touch ID. Inside tmux this also needs pam_reattach, which is not added. | For someone who runs sudo often. /etc/pam.d/sudo_local is the file Apple provides for this, and it survives macOS updates. | none | yes | yes |
| `trackpad` | Tap to click on the built-in trackpad and on a Magic Trackpad. | A preference. | none | no | yes |
<!-- modules:end -->

`go-trimpath` and the modules after `updates` are in no profile: run them by name.

## Tested, and not

```sh
bash setup.d/test/run
```

The test script runs `apply` and `undo` against a fake `defaults` store and a fake `brew`, with the real `sudo`, `killall` and `brew` out of reach, and checks that only `set` rows are written, that receipts restore the prior value and type, and that an item already at target is never touched.

Not tested: a real `apply` and a real `undo`. It was built on a Mac in daily use under a rule of no system writes, so `plan` has run for real and `apply` only against the fakes. In particular, nobody has yet seen:

- what `sysadminctl -screenLock status` prints once the lock is immediate (unknown text shows as a `fail` row, never as a change to repeat);
- the Homebrew installer running off the cached password, and `brew bundle` on a Mac whose apps were installed by hand;
- the menu bar and Software Update keys on macOS 26, where both modules skip and print a hand step instead.

Before the first real run, do one of these: try it in a throwaway user on your Mac (a standard account shows the administrator refusal, an administrator account the real writes; items marked `sudo` change the whole Mac, not only that user), or start with `plan` alone and apply one module at a time.

## Design

Why each choice was made, and how to add a module: [`setup.d/DESIGN.md`](setup.d/DESIGN.md).

## License

MIT, in [LICENSE](LICENSE).
