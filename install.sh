#!/usr/bin/env bash
# =============================================================================
#  i3wm-dots installer  -  installs i3 + everything it needs + the dotfiles
#  Port of LinuxBeginnings/Hyprland-Dots (GPL-3.0-or-later)
#
#  Works from KDE, GNOME, or any other desktop: it installs i3 and Xorg next to
#  your current desktop, so you can pick "i3" at the login screen.
#
#  Usage:  ./install.sh [options]
#    (default)       install i3 + dependencies, then the dotfiles
#    --no-packages   only copy the dotfiles (you already have the programs)
#    --wallpapers    also download the full KooL wallpaper bank (large)
#    --no-pokemon    skip pokescript and the shiny Mimikyu fastfetch greeting in the terminal
#    --no-ghostty    do not install Ghostty (kitty is used as the terminal instead)
#    --no-backup     overwrite existing configs instead of moving them aside
#    --no-auto-update do not check for a newer desktop config after system updates (pacman -Syu / dnf upgrade / apt upgrade)
#    --update        quick re-install of the config files only (used by i3dots-update: no packages, no password)
#    --restore       put back the newest *.bak-* backups and exit
#    --dry-run       show what would happen without changing anything
#    -h, --help      show this help
#
#  One-liner on Linux (no clone needed):
#    bash <(curl -fsSL https://raw.githubusercontent.com/OmitGhostly/i3/main/install.sh)
#
#  Package managers: dnf (Fedora - the main target), pacman (Arch & derivatives),
#  apt (Debian, Ubuntu, Mint, Pop!_OS). Anything else: install the programs
#  yourself, then run with --no-packages.
#  FreeBSD, GhostBSD, OpenBSD and NetBSD have their own version of these dots:
#  https://github.com/OmitGhostly/i3-bsd
#  A log of every run is written to ~/.cache/i3wm-dots-install.log
# =============================================================================
set -uo pipefail

REPO_URL="${I3DOTS_REPO:-https://github.com/OmitGhostly/i3.git}"
# the repo moved from OmitGhostly/i3wm-config to OmitGhostly/i3: an address of the old one means the new one
repo_moved() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    *github.com[:/]omitghostly/i3wm-config|*github.com[:/]omitghostly/i3wm-config.git|*github.com[:/]omitghostly/i3wm-config/)
      printf '%s\n' "https://github.com/OmitGhostly/i3.git" ;;
    *) printf '%s\n' "$1" ;;
  esac
}
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo /)"
cfg="${XDG_CONFIG_HOME:-$HOME/.config}"
stamp="$(date +%Y%m%d-%H%M%S)"
do_packages=1; do_wallpapers=0; do_pokemon=1; do_ghostty=1; do_backup=1; do_restore=0; dry=0
do_autoupdate=1; update_mode=0
orig_path="$PATH"
export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"

say()  { printf '\033[1;35m::\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }
usage() { sed -n '3,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

for arg in "$@"; do
  case "$arg" in
    --no-packages) do_packages=0 ;;
    --packages)    do_packages=1 ;;           # kept for old instructions; now the default
    --wallpapers)  do_wallpapers=1 ;;
    --no-pokemon)  do_pokemon=0 ;;
    --no-ghostty)  do_ghostty=0 ;;
    --no-backup)   do_backup=0 ;;
    --restore)     do_restore=1 ;;
    --dry-run)     dry=1 ;;
    --no-auto-update) do_autoupdate=0 ;;
    --update)      update_mode=1; do_packages=0; do_pokemon=0 ;;   # (pokemon: keep whatever was chosen at install)
    -h|--help)     usage; exit 0 ;;
    *) die "unknown option: $arg (try --help)" ;;
  esac
done

# The config lives in ~/.config: i3's config and the scripts point there. A config folder moved elsewhere with
# XDG_CONFIG_HOME would leave a desktop whose keys and bar find nothing, so stop with what to do instead.
xdg_real="$(cd "${XDG_CONFIG_HOME:-/nonexistent/}" 2>/dev/null && pwd -P)"
if [ -n "${XDG_CONFIG_HOME:-}" ] && [ "${XDG_CONFIG_HOME%/}" != "$HOME/.config" ] \
   && { [ -z "$xdg_real" ] || [ "$xdg_real" != "$(cd "$HOME/.config" 2>/dev/null && pwd -P)" ]; }; then
  die "XDG_CONFIG_HOME is set to $XDG_CONFIG_HOME, but this config lives in ~/.config (i3 and its scripts look there).
   Run the installer with it pointing there:   XDG_CONFIG_HOME=\"\$HOME/.config\" $0 $*
   and remove the XDG_CONFIG_HOME line from your shell or session settings, so i3 finds its config too."
fi

# run a command, or just print it in --dry-run mode
run() { if [ "$dry" -eq 1 ]; then printf '   + %s\n' "$*"; return 0; fi; "$@"; }

# temporary files and folders: removed on the way out, also after Ctrl+C or a closed terminal
CLEANUP=()
cleanup() { [ "${#CLEANUP[@]}" -eq 0 ] || rm -rf -- "${CLEANUP[@]}" 2>/dev/null; return 0; }
trap cleanup EXIT

# ---- log everything (not in dry-run) -----------------------------------------
if [ "$dry" -eq 0 ]; then
  mkdir -p "$HOME/.cache" 2>/dev/null || true
  LOG="$HOME/.cache/i3wm-dots-install.log"
  exec > >(tee -a "$LOG") 2>&1
  say "log: $LOG"
fi

# ---- privileges ---------------------------------------------------------------
# Packages are installed as root: through sudo, else doas (it needs a rule in /etc/doas.conf), else su (asks
# for root's password). $SUDO is put in front of those commands.
as_root() {
  if [ "$(id -u)" -eq 0 ]; then "$@"
  elif command -v sudo >/dev/null 2>&1; then sudo "$@"
  elif command -v doas >/dev/null 2>&1 && [ -f /etc/doas.conf ]; then doas "$@"
  else su root -c "$(printf '%q ' "$@")"; fi
}
if [ "$(id -u)" -eq 0 ]; then
  [ "${I3DOTS_ALLOW_ROOT:-0}" = 1 ] || die "run as your normal user, not root (sudo is asked for only when installing packages)"
  SUDO=""
else
  SUDO="as_root"
  if [ "$do_packages" -eq 1 ] && ! command -v sudo >/dev/null 2>&1 && ! command -v doas >/dev/null 2>&1 && ! command -v su >/dev/null 2>&1; then
    die "sudo (or doas / su) is required to install packages. Install it, or run with --no-packages"
  fi
fi

# ---- FreeBSD, GhostBSD, OpenBSD and NetBSD: their own version of these dots ------------------------------------
# A BSD desktop installed from here before the split gets its updates from the BSD repo from now on, and that repo's
# installer takes over right away; a new install there is pointed to it.
BSD_REPO="${I3DOTS_BSD_REPO:-https://github.com/OmitGhostly/i3-bsd.git}"
bsd_moved() {
  local u="${XDG_DATA_HOME:-$HOME/.local/share}/i3wm-dots-updater/repo-url" tmp rc
  if [ "$update_mode" -eq 1 ]; then
    if [ -f "$u" ]; then printf '%s\n' "$BSD_REPO" >"$u"; fi
    tmp="$(mktemp -d)"
    if command -v git >/dev/null 2>&1 && git clone -q --depth 1 "$BSD_REPO" "$tmp/i3-bsd" >/dev/null 2>&1 \
       && [ -f "$tmp/i3-bsd/install.sh" ]; then
      say "this is $(uname -s): FreeBSD, GhostBSD, OpenBSD and NetBSD have their own version now - continuing with it"
      say "(updates come from $BSD_REPO from now on)"
      bash "$tmp/i3-bsd/install.sh" "$@"; rc=$?
      # (the version installed now, for the updater - it wrote down this repo's)
      [ "$rc" -eq 0 ] && [ -d "${u%/*}" ] && git -C "$tmp/i3-bsd" rev-parse HEAD >"${u%/*}/handoff" 2>/dev/null
      rm -rf "$tmp"; exit "$rc"
    fi
    rm -rf "$tmp"
    die "could not download the BSD version ($BSD_REPO) - updates come from there from now on: try i3dots-update again later"
  fi
  die "This is the Linux version. FreeBSD, GhostBSD, OpenBSD and NetBSD have their own:
   https://github.com/OmitGhostly/i3-bsd   (README.md there has the install command for each system)"
}
case "${I3DOTS_OS:-$(uname -s)}" in FreeBSD|OpenBSD|NetBSD|DragonFly) bsd_moved "$@" ;; esac

# ---- distro detection -----------------------------------------------------------
detect_family() {
  local f="${I3DOTS_OS_RELEASE:-/etc/os-release}" id="" like=""
  if [ -r "$f" ]; then
    # shellcheck source=/dev/null
    id="$( . "$f"; echo "${ID:-}" )"
    # shellcheck source=/dev/null
    like="$( . "$f"; echo "${ID_LIKE:-}" )"
  fi
  case " $id $like " in
    *" fedora "*|*" rhel "*|*" centos "*)          echo fedora ;;
    *" arch "*|*" archlinux "*)                    echo arch ;;
    *" debian "*|*" ubuntu "*)                     echo debian ;;
    *)                                             echo unknown ;;
  esac
}
FAMILY="$(detect_family)"

# ---- bootstrap: script was run without the repo next to it (curl | bash) -------
# (piped from curl the script has no folder of its own: never treat the current directory as the repo by accident)
if [ ! -f "$here/install.sh" ] || [ ! -f "$here/config/i3/config" ]; then
  say "repository files not found next to the script - fetching them"
  if ! command -v git >/dev/null 2>&1; then
    case "$FAMILY" in
      fedora) run $SUDO dnf install -y git ;;
      arch)   run $SUDO pacman -S --needed --noconfirm git ;;
      debian) run $SUDO apt-get update; run $SUDO apt-get install -y git ;;
      *) die "git is needed to download the dotfiles - install git and re-run" ;;
    esac
  fi
  dest="${XDG_DATA_HOME:-$HOME/.local/share}/i3wm-dots"
  if [ -d "$dest/.git" ]; then
    # (a copy made from the old repo address follows the new one)
    run git -C "$dest" remote set-url origin "$(repo_moved "$(git -C "$dest" config --get remote.origin.url 2>/dev/null)")" 2>/dev/null || true
    run git -C "$dest" pull --ff-only || warn "could not update $dest, using what is there"
  else run git clone --depth=1 "$REPO_URL" "$dest" || die "clone failed: $REPO_URL"; fi
  [ "$dry" -eq 1 ] && { say "dry-run: would continue with $dest/install.sh"; exit 0; }
  exec bash "$dest/install.sh" "$@"
fi

# ---- restore --------------------------------------------------------------------
if [ "$do_restore" -eq 1 ]; then
  restored=0
  for d in "$here"/config/*/; do
    name="$(basename "$d")"
    latest="$(find "$cfg" -maxdepth 1 -name "$name.bak-*" ! -name '*.part' 2>/dev/null | sort | tail -n1)"
    if [ -n "$latest" ]; then
      # (the current one moved aside first and deleted last: stopped halfway, nothing is lost)
      run rm -rf "${cfg:?}/.i3dots-removing-$name"
      if [ -e "$cfg/$name" ] || [ -L "$cfg/$name" ]; then run mv "$cfg/$name" "$cfg/.i3dots-removing-$name"; fi
      run mv "$latest" "$cfg/$name" && run rm -rf "${cfg:?}/.i3dots-removing-$name"
      say "restored $name from $(basename "$latest")"
      restored=$((restored + 1))
    fi
  done
  [ "$restored" -gt 0 ] || say "no backups (*.bak-*) found in $cfg - nothing to restore"
  exit 0
fi

# =============================================================================
#  Packages.  "a|b" = use a if the repo has it, otherwise b.  A leading "/" is a
#  file path (dnf resolves it to whichever package ships it - robust to renames).
#  Every entry is checked against the repos first; entries that do not exist on
#  your distro are skipped and reported at the end, so one bad name can never
#  abort the installation of everything else.
# =============================================================================
packages_for() {
  local common="polybar picom dunst rofi kitty feh maim xdotool xclip xss-lock i3lock imagemagick
    brightnessctl pamixer playerctl pavucontrol redshift numlockx jq curl unzip arandr git mpv xdg-utils
    fontconfig lxappearance fastfetch python3 bluez blueman clipmenu|copyq touchegg file"
  case "$FAMILY" in
    fedora) echo "i3 xsettingsd dbus-tools|/usr/bin/dbus-update-activation-environment xorg-x11-server-Xorg xset|/usr/bin/xset xrdb|/usr/bin/xrdb xsetroot|/usr/bin/xsetroot adwaita-cursor-theme xrandr|/usr/bin/xrandr
                  xprop|/usr/bin/xprop xdpyinfo|/usr/bin/xdpyinfo setxkbmap|/usr/bin/setxkbmap xinput|/usr/bin/xinput
                  network-manager-applet NetworkManager-openvpn-gnome|NetworkManager-openvpn thunar mate-polkit|polkit-gnome|lxpolkit
                  libnotify|/usr/bin/notify-send libqalculate|/usr/bin/qalc google-noto-color-emoji-fonts|google-noto-emoji-color-fonts
                  swappy python3-gobject python3-cairo gtk3 glx-utils|/usr/bin/glxinfo pulseaudio-utils|/usr/bin/pactl sound-theme-freedesktop $common" ;;
    arch)   echo "i3-wm xsettingsd xorg-server xorg-xset xorg-xrdb xorg-xsetroot adwaita-icon-theme xorg-xrandr xorg-xprop xorg-xdpyinfo xorg-setxkbmap xorg-xinput
                  network-manager-applet networkmanager-openvpn thunar polkit-gnome libnotify libqalculate swappy bluez-utils
                  noto-fonts-emoji python-gobject python-cairo gtk3 mesa-utils libpulse sound-theme-freedesktop $common" ;;
    debian) echo "i3 xsettingsd xserver-xorg x11-xserver-utils x11-utils x11-xkb-utils xinput network-manager-gnome
                  network-manager-openvpn-gnome|network-manager-openvpn thunar
                  policykit-1-gnome|polkit-gnome|mate-polkit|lxpolkit libnotify-bin qalc|libqalculate-utils
                  fonts-noto-color-emoji python3-gi python3-gi-cairo gir1.2-gtk-3.0 mesa-utils pulseaudio-utils sound-theme-freedesktop
                  swappy|flameshot $common" ;;
  esac
}

pkg_available() {
  case "$FAMILY" in
    fedora) dnf -q repoquery --whatprovides "$1" 2>/dev/null | grep -q . ;;
    arch)   pacman -Si "$1" >/dev/null 2>&1 ;;
    debian) [ -n "$(apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/{print $2}' | grep -v '^(none)$')" ] ;;
    *)      return 1 ;;
  esac
}

pkg_install() {   # pkg_install pkg...
  case "$FAMILY" in
    fedora) run $SUDO dnf install -y "$@" ;;
    arch)   run $SUDO pacman -S --needed --noconfirm "$@" ;;
    debian) run $SUDO apt-get install -y "$@" ;;
  esac
}

missing=()

# ---- what the installer added: uninstall.sh reads this, so it only removes what was not there before ---------------
MANIFEST="${XDG_STATE_HOME:-$HOME/.local/state}/i3wm-dots/installed"
record() {   # record KIND VALUE   (pkg NAME | copr NAME | snap NAME | path PATH | rc PATH)
  [ "$dry" -eq 1 ] && return 0
  mkdir -p "$(dirname "$MANIFEST")" 2>/dev/null || return 0
  grep -qxF "$1 $2" "$MANIFEST" 2>/dev/null || printf '%s %s\n' "$1" "$2" >>"$MANIFEST"
}
pkg_installed() {   # is it installed? (Fedora: also a file path or anything a package provides)
  case "$FAMILY" in
    fedora) rpm -q --whatprovides "$1" >/dev/null 2>&1 ;;
    arch)   pacman -Qq "$1" >/dev/null 2>&1 ;;
    debian) dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'ok installed' ;;
    *)      return 1 ;;
  esac
}
pkg_name() {   # the real package name (Fedora: ImageMagick for imagemagick, dbus-tools for /usr/bin/...)
  case "$FAMILY" in
    fedora) rpm -q --whatprovides "$1" --qf '%{NAME}\n' 2>/dev/null | head -n1 ;;
    *)      printf '%s\n' "$1" ;;
  esac
}
record_new_pkgs() {   # record_new_pkgs PKG...  (the ones that were missing before: those now installed are ours)
  local p
  [ "$dry" -eq 1 ] && return 0
  for p in "$@"; do pkg_installed "$p" && record pkg "$(pkg_name "$p")"; done
  return 0
}

# pinned to a reviewed commit: the sprite is printed straight into your terminal, so it must not change under you
POKESCRIPT_REV="efb573d81beacf629d981b4997ed304ce3c34b8c"
install_pokemon() {   # acxz/pokescript: the shiny Mimikyu sprite shown by fastfetch in the terminal
  [ "$do_pokemon" -eq 1 ] || return 0
  command -v git >/dev/null 2>&1 || return 0
  local dest="${XDG_DATA_HOME:-$HOME/.local/share}/pokescript"
  if [ "$dry" -eq 0 ] && [ "$(git -C "$dest" rev-parse HEAD 2>/dev/null)" = "$POKESCRIPT_REV" ]; then return 0; fi
  say "installing pokescript (acxz/pokescript @ ${POKESCRIPT_REV:0:7}) for the Mimikyu greeting"
  run rm -rf "$dest"
  run mkdir -p "$dest"
  if run git -C "$dest" init -q \
     && run git -C "$dest" fetch -q --depth 1 https://github.com/acxz/pokescript.git "$POKESCRIPT_REV" \
     && run git -C "$dest" checkout -q FETCH_HEAD; then :
  else
    warn "could not download pokescript - the bundled Mimikyu sprite is used instead"
    run rm -rf "$dest"
  fi
}

# ---- which shell: the greeting, the prompt and the asciiquarium line go into ~/.bashrc and/or ~/.zshrc ---------
# Every rc file you already have gets them, and so does the one of your login shell (from /etc/passwd) - created if
# it does not exist yet (a new zsh user has no ~/.zshrc), so the greeting always shows in your own shell.
RC_FILES=()
login_shell() {
  local s="${I3DOTS_SHELL:-}"
  [ -n "$s" ] || s="$(getent passwd "$(id -un)" 2>/dev/null | cut -d: -f7)"
  [ -n "$s" ] || s="${SHELL:-}"
  basename "${s:-bash}"
}
prepare_shell_rc() {
  local sh rc
  sh="$(login_shell)"
  case "$sh" in
    zsh|bash)
      rc="$HOME/.${sh}rc"
      if [ ! -f "$rc" ] && [ "$update_mode" -eq 0 ]; then
        say "your shell is $sh and there is no ~/.${sh}rc yet - creating it"
        if [ "$dry" -eq 0 ]; then
          if [ -f "/etc/skel/.${sh}rc" ]; then cp "/etc/skel/.${sh}rc" "$rc"      # your distro's default one
          else printf '# ~/.%src - created by the i3wm-dots installer\n' "$sh" >"$rc"; fi
          record rc "$rc"
        fi
      fi
      say "your shell is $sh: the fastfetch greeting, the prompt and asciiquarium are set up in ~/.${sh}rc" ;;
    fish)      # the greeting goes into fish's own conf.d; the prompt is for bash / zsh
      say "your shell is fish: the fastfetch greeting is set up in ~/.config/fish/conf.d (the prompt is for bash and zsh)" ;;
    *)
      warn "your shell is $sh: the fastfetch greeting and the prompt are made for bash and zsh"
      warn "  (they are still added to ~/.bashrc / ~/.zshrc if you have them; in $sh run ~/.config/i3/scripts/PokeFetch.sh yourself)" ;;
  esac
  RC_FILES=()
  for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
    [ -f "$rc" ] && RC_FILES+=("$rc")
  done
  # (dry run: the rc file that would be created)
  [ "$dry" -eq 1 ] && case "$sh" in zsh|bash) [ -f "$HOME/.${sh}rc" ] || RC_FILES+=("$HOME/.${sh}rc") ;; esac
  return 0
}

# add the Pokemon fastfetch line to the shell rc files (once; an older kitty-only line is upgraded).
# In ~/.zshrc it goes on the very first lines: prompt themes with an "instant prompt" (Powerlevel10k - CachyOS's
# default zsh setup, many oh-my-zsh ones) draw the prompt before the rest of ~/.zshrc runs and warn about anything
# printed after that, and fastfetch also asks the terminal things, which only works above that point.
# An update (--update) moves a greeting you already have to the top, but never adds one you did not choose.
install_shell_hook() {
  [ "$do_pokemon" -eq 1 ] || [ "$update_mode" -eq 1 ] || return 0
  local rc real tmp top marker='# i3wm-dots: pokemon fastfetch'
  # I3DOTS_POKEFETCH (not exported) makes sure the greeting shows only once per shell, even if the line is sourced twice
  # another greeting the shell file runs itself (KoolDots' .zshrc: "pokemon-colorscripts ... | fastfetch ...", or a
  # plain "fastfetch" line) would show a second one: it is turned off, marked so the uninstaller can put it back
  local other='^[[:space:]]*(fastfetch|pokemon-colorscripts[^#]*[|][[:space:]]*fastfetch)([[:space:]]|$)' off='#i3wm-dots-off# '
  local line='[ -z "$I3DOTS_POKEFETCH" ] && { [ -n "$KITTY_WINDOW_ID" ] || [ "$TERM_PROGRAM" = ghostty ]; } && [ -x "$HOME/.config/i3/scripts/PokeFetch.sh" ] && { I3DOTS_POKEFETCH=1; "$HOME/.config/i3/scripts/PokeFetch.sh"; }'
  for rc in "${RC_FILES[@]}"; do
    top=0; [ "${rc##*/}" = .zshrc ] && top=1
    if grep -qF "$marker" "$rc" 2>/dev/null; then
      # already there, once, the current version, and (zsh) on the first line: nothing to do
      if grep -qF 'I3DOTS_POKEFETCH' "$rc" && [ "$(grep -cF "$marker" "$rc")" -eq 1 ] \
         && { [ "$top" -eq 0 ] || [ "$(head -n 1 "$rc")" = "$marker" ]; } && ! grep -qE "$other" "$rc"; then
        continue
      fi
      if grep -qE "$other" "$rc"; then
        say "turning off the other fastfetch greeting in $rc (it showed a second one; i3dots-uninstall puts it back):"
        grep -nE "$other" "$rc" | sed 's/^/     line /'
      elif [ "$top" -eq 1 ]; then say "moving the pokemon fastfetch greeting to the top of $rc (before the prompt theme starts)"
      else say "refreshing the pokemon fastfetch greeting in $rc (one greeting per terminal)"; fi
    else
      [ "$update_mode" -eq 1 ] && continue
      say "adding the pokemon fastfetch greeting to $rc (kitty and ghostty only)"
    fi
    [ "$dry" -eq 1 ] && continue
    # write the real file (a ~/.zshrc linked from a dotfiles folder stays a link), through a copy that keeps its
    # permissions; every old copy of the greeting (marker line + the line after it, and the blank line before it)
    # goes, and a single fresh one is added: first thing in ~/.zshrc, last thing in ~/.bashrc
    real="$(readlink -f -- "$rc" 2>/dev/null)"; [ -n "$real" ] || real="$rc"
    tmp="$real.i3tmp"; CLEANUP+=("$tmp")
    cp -p -- "$real" "$tmp" || continue
    {
      [ "$top" -eq 1 ] && printf '%s\n%s\n' "$marker" "$line"
      awk -v m="$marker" -v o="$other" -v off="$off" 'skip { skip = 0; next }
           index($0, m) == 1 { skip = 1; blank = 0; next }
           $0 ~ o { $0 = off $0 }
           { if (blank) print ""; blank = 0 }
           /^$/ { blank = 1; next }
           { print }
           END { if (blank) print "" }' "$real"
      [ "$top" -eq 1 ] || printf '\n%s\n%s\n' "$marker" "$line"
    } >"$tmp" && mv -f -- "$tmp" "$real"
  done
}

# fish: the same greeting as a fish conf.d file (written for the login shell fish, or a fish set up already)
install_fish_hook() {
  [ "$do_pokemon" -eq 1 ] || return 0
  local d="$cfg/fish/conf.d" f
  f="$d/i3wm-dots.fish"
  [ "$(login_shell)" = fish ] || [ -d "$d" ] || return 0
  [ -f "$f" ] && grep -qF 'I3DOTS_POKEFETCH' "$f" && return 0
  say "adding the pokemon fastfetch greeting for fish ($f, kitty and ghostty only)"
  [ "$dry" -eq 1 ] && return 0
  mkdir -p "$d" || return 0
  record path "$f"
  cat >"$f" <<'FISH'
# i3wm-dots: pokemon fastfetch greeting (kitty and ghostty, once per terminal). Remove this file to turn it off.
if status is-interactive; and not set -q I3DOTS_POKEFETCH
    if set -q KITTY_WINDOW_ID; or test "$TERM_PROGRAM" = ghostty
        set -g I3DOTS_POKEFETCH 1
        test -x "$HOME/.config/i3/scripts/PokeFetch.sh"; and "$HOME/.config/i3/scripts/PokeFetch.sh"
    end
end
FISH
}

# "asciiquarium" in the terminal: run it see-through (its own background is solid black) - once per rc file
install_aquarium_alias() {
  local rc marker='# i3wm-dots: see-through asciiquarium'
  local line='[ -x "$HOME/.config/i3/scripts/Aquarium.sh" ] && alias asciiquarium="$HOME/.config/i3/scripts/Aquarium.sh"'
  for rc in "${RC_FILES[@]}"; do
    grep -qF "$marker" "$rc" 2>/dev/null && continue
    say "making asciiquarium see-through in $rc"
    [ "$dry" -eq 1 ] || printf '\n%s\n%s\n' "$marker" "$line" >> "$rc"
  done
}

# the black / grey / white prompt (~/.config/i3/scripts/Prompt.sh) in bash and zsh - once per rc file.
# It steps aside by itself when another prompt theme (starship, oh-my-zsh, powerlevel10k...) is in charge.
install_prompt() {
  local rc marker='# i3wm-dots: black / grey / white prompt (turn off: export I3DOTS_PROMPT=off above this line)'
  local line='[ -r "$HOME/.config/i3/scripts/Prompt.sh" ] && . "$HOME/.config/i3/scripts/Prompt.sh"'
  for rc in "${RC_FILES[@]}"; do
    grep -qF '# i3wm-dots: black / grey / white prompt' "$rc" 2>/dev/null && continue
    say "adding the black / grey / white prompt to $rc"
    [ "$dry" -eq 1 ] || printf '\n%s\n%s\n' "$marker" "$line" >> "$rc"
  done
}

# ---- terminals: Ghostty (the default) and kitty (the fallback) ----------------------------------------------
# Both are checked; whichever is missing is installed - from your distro's own repos first.
install_ghostty() {
  # the distro's own package: Arch, Ubuntu 26.04 and newer, openSUSE, ...
  local had=0
  pkg_installed ghostty && had=1          # (installed, but not on PATH: never record it as ours)
  if pkg_available ghostty; then
    say "installing Ghostty from your distro's repos"
    pkg_install ghostty && { [ "$had" -eq 1 ] || record_new_pkgs ghostty; return 0; }
  fi
  case "$FAMILY" in
    fedora)
      # Fedora has no official package: the community COPR that ghostty.org points to, then a second one
      local copr
      for copr in scottames/ghostty pgdev/ghostty; do
        say "installing Ghostty from the community COPR $copr (Fedora has no official package)"
        if run $SUDO dnf copr enable -y "$copr" \
           || { { run $SUDO dnf install -y dnf5-plugins || run $SUDO dnf install -y dnf-plugins-core; } \
                && run $SUDO dnf copr enable -y "$copr"; }; then
          if run $SUDO dnf install -y ghostty; then record copr "$copr"; [ "$had" -eq 1 ] || record_new_pkgs ghostty; return 0; fi
          run $SUDO dnf copr disable -y "$copr" >/dev/null 2>&1 || true     # it did not work: do not leave it on
        fi
      done ;;
    debian)
      # no apt package before Ubuntu 26.04 / on Debian: the Snap Store (listed on ghostty.org), then the community
      # .deb ghostty.org lists - the way in on Linux Mint, which has no Snap
      if command -v snap >/dev/null 2>&1; then
        say "installing Ghostty from the Snap Store (your release has no apt package)"
        run $SUDO snap install ghostty --classic && { record snap ghostty; return 0; }
      fi
      install_ghostty_deb && { [ "$had" -eq 1 ] || record_new_pkgs ghostty; return 0; } ;;
  esac
  return 1
}

# The community .deb that ghostty.org lists for Ubuntu and Debian (github.com/mkasberg/ghostty-ubuntu), straight from
# its GitHub releases. It is installed with apt (so "apt remove ghostty", and the uninstaller, take it out again);
# no repository is added. Ubuntu 24.04 and what is built on it (Linux Mint 22, Pop!_OS, Zorin...) get Ghostty 1.3.1,
# the last version that runs there; Debian 13 / 14 and LMDE 7 the newest one.
ghostty_deb_target() {   # the release file's ending (amd64_24.04, arm64_trixie...); nothing when there is none
  local arch id ver uver ucode dcode vcode c
  arch="$(dpkg --print-architecture 2>/dev/null)"
  case "$arch" in amd64|arm64) ;; *) return 0 ;; esac
  # shellcheck source=/dev/null
  read -r id ver uver ucode dcode vcode <<<"$( . "${I3DOTS_OS_RELEASE:-/etc/os-release}" 2>/dev/null
    echo "${ID:--} ${VERSION_ID:--} ${UBUNTU_VERSION_ID:--} ${UBUNTU_CODENAME:--} ${DEBIAN_CODENAME:--} ${VERSION_CODENAME:--}")"
  case "$ucode" in
    noble)    echo "${arch}_24.04"; return 0 ;;
    resolute) echo "${arch}_26.04"; return 0 ;;
    stonking) echo "${arch}_26.10"; return 0 ;;
  esac
  case "$id:$ver" in ubuntu:24.04|ubuntu:26.04|ubuntu:26.10) echo "${arch}_$ver"; return 0 ;; esac
  case "$uver" in 24.04|26.04|26.10) echo "${arch}_$uver"; return 0 ;; esac
  for c in "$dcode" "$vcode"; do
    case "$c" in trixie|forky) echo "${arch}_$c"; return 0 ;; esac
  done
}

install_ghostty_deb() {
  local target tag url tmp file rc=1 gh=https://github.com/mkasberg/ghostty-ubuntu/releases
  target="$(ghostty_deb_target)"
  [ -n "$target" ] && command -v curl >/dev/null 2>&1 && command -v dpkg-deb >/dev/null 2>&1 || return 1
  if [ "${target##*_}" = 24.04 ]; then
    tag=1.3.1-0-ppa2                                 # (Ghostty 1.4 and newer need more than Ubuntu 24.04 has)
  else
    # the newest release: where github.com sends .../releases/latest (.../releases/tag/1.4.0-0-ppa2)
    tag="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "$gh/latest" 2>/dev/null)"; tag="${tag##*/tag/}"
    case "$tag" in [0-9]*-*) ;; *) return 1 ;; esac
  fi
  # (the files are named after the tag with its last "-" as ".": tag 1.3.1-0-ppa2 -> ghostty_1.3.1-0.ppa2_amd64_24.04.deb)
  file="ghostty_${tag%-*}.${tag##*-}_${target}.deb"; url="$gh/download/$tag/$file"
  say "installing Ghostty from the community .deb on ghostty.org's list (github.com/mkasberg/ghostty-ubuntu, $tag)"
  [ "$dry" -eq 1 ] && return 0
  tmp="$(mktemp -d)"; CLEANUP+=("$tmp"); chmod 755 "$tmp"   # (apt reads it as its own user)
  if curl -fsSL --retry 2 -o "$tmp/$file" "$url" && chmod 644 "$tmp/$file" \
     && [ "$(dpkg-deb -f "$tmp/$file" Package 2>/dev/null)" = ghostty ] \
     && run $SUDO apt-get install -y "$tmp/$file"; then
    rc=0
  fi
  rm -rf "$tmp"
  return $rc
}

install_kitty() {
  local had=0
  pkg_installed kitty && had=1
  if pkg_available kitty; then
    say "installing kitty from your distro's repos"
    pkg_install kitty && { [ "$had" -eq 1 ] || record_new_pkgs kitty; return 0; }
  fi
  # kitty's own installer (official builds from its author) into ~/.local/kitty.app, linked into ~/.local/bin
  command -v curl >/dev/null 2>&1 || return 1
  say "installing kitty with its official installer (sw.kovidgoyal.net) into ~/.local/kitty.app"
  # (written down first, so a stopped install still has them listed - uninstall skips any that were never made)
  record path "$HOME/.local/kitty.app"; record path "$HOME/.local/bin/kitty"; record path "$HOME/.local/bin/kitten"
  record path "$HOME/.local/share/applications/kitty.desktop"
  run sh -c 'curl -fsSL https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin launch=n' || return 1
  run mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications"
  run ln -sf "$HOME/.local/kitty.app/bin/kitty" "$HOME/.local/kitty.app/bin/kitten" "$HOME/.local/bin/"
  run cp -f "$HOME/.local/kitty.app/share/applications/kitty.desktop" "$HOME/.local/share/applications/" 2>/dev/null || true
  return 0
}

ensure_terminals() {
  local t
  say "checking the terminals: Ghostty (the default) and kitty (the fallback)"
  for t in ghostty kitty; do
    if [ "$t" = ghostty ] && [ "$do_ghostty" -eq 0 ]; then
      echo "   ghostty: skipped (--no-ghostty)"
    elif command -v "$t" >/dev/null 2>&1; then
      # (asked with a throwaway config folder: kitty creates ~/.config/kitty just by starting, which would then
      #  look like a config of your own and be backed up)
      local vt; vt="$(mktemp -d)"; CLEANUP+=("$vt")
      echo "   $t: already installed ($(env XDG_CONFIG_HOME="$vt" XDG_CACHE_HOME="$vt" XDG_STATE_HOME="$vt" KITTY_CONFIG_DIRECTORY="$vt" \
        "$t" --version 2>/dev/null | head -n1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1))"
      rm -rf "$vt"
    elif [ "$do_packages" -eq 0 ]; then
      echo "   $t: not installed (--no-packages: install it yourself, e.g. with your package manager)"
    elif "install_$t" && { [ "$dry" -eq 1 ] || command -v "$t" >/dev/null 2>&1; }; then
      echo "   $t: installed"
    elif [ "$t" = ghostty ]; then
      warn "Ghostty could not be installed - kitty will be your terminal (other ways: ghostty.org/docs/install/binary)"
    else
      warn "kitty could not be installed - install it yourself (sw.kovidgoyal.net/kitty/binary)"
    fi
  done
}

# ---- the file manager: yazi (opens in the terminal; Thunar stays installed as the graphical one) -------------------
# From your distro's repos when it has it (Arch, openSUSE, ...); Fedora: the community COPR that
# yazi's install page names; Debian/Ubuntu: the Snap Store; otherwise yazi's own release build (Linux x86_64/arm64).
have_yazi() { command -v yazi >/dev/null 2>&1 || [ -x "$HOME/.local/bin/yazi" ] || [ -x /snap/bin/yazi ]; }
yazi_version() {
  local y; y="$(command -v yazi 2>/dev/null || { [ -x "$HOME/.local/bin/yazi" ] && echo "$HOME/.local/bin/yazi"; } || echo /snap/bin/yazi)"
  "$y" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1
}

install_yazi() {
  local had=0
  pkg_installed yazi && had=1
  if pkg_available yazi; then
    say "installing yazi from your distro's repos"
    pkg_install yazi && { [ "$had" -eq 1 ] || record_new_pkgs yazi; return 0; }
  fi
  case "$FAMILY" in
    fedora)
      local copr=lihaohong/yazi
      say "installing yazi from the community COPR $copr (Fedora has no official package; yazi's install page names it)"
      if run $SUDO dnf copr enable -y "$copr" \
         || { { run $SUDO dnf install -y dnf5-plugins || run $SUDO dnf install -y dnf-plugins-core; } \
              && run $SUDO dnf copr enable -y "$copr"; }; then
        if run $SUDO dnf install -y yazi; then record copr "$copr"; [ "$had" -eq 1 ] || record_new_pkgs yazi; return 0; fi
        run $SUDO dnf copr disable -y "$copr" >/dev/null 2>&1 || true     # it did not work: do not leave it on
      fi ;;
    debian)
      if command -v snap >/dev/null 2>&1; then
        say "installing yazi from the Snap Store (your release has no apt package)"
        run $SUDO snap install yazi --classic && { record snap yazi; return 0; }
      fi ;;
  esac
  install_yazi_release
}

# yazi's own release build (github.com/sxyazi/yazi: static, for x86_64 and arm64 Linux) into ~/.local/bin
install_yazi_release() {
  local arch dir tmp rc=1
  case "$(uname -m)" in
    x86_64|amd64)  arch=x86_64 ;;
    aarch64|arm64) arch=aarch64 ;;
    *) return 1 ;;
  esac
  command -v curl >/dev/null 2>&1 && command -v unzip >/dev/null 2>&1 || return 1
  say "installing yazi's official release build (github.com/sxyazi/yazi) into ~/.local/bin"
  # (written down first, so a stopped install still has them listed - uninstall skips any that were never made)
  record path "$HOME/.local/bin/yazi"; record path "$HOME/.local/bin/ya"
  [ "$dry" -eq 1 ] && return 0
  tmp="$(mktemp -d)"; CLEANUP+=("$tmp"); dir="$tmp/yazi-$arch-unknown-linux-musl"
  if curl -fsSL --retry 2 -o "$tmp/yazi.zip" \
          "https://github.com/sxyazi/yazi/releases/latest/download/yazi-$arch-unknown-linux-musl.zip" \
     && unzip -qo "$tmp/yazi.zip" -d "$tmp" && "$dir/yazi" --version >/dev/null 2>&1 \
     && mkdir -p "$HOME/.local/bin" \
     && cp "$dir/yazi" "$HOME/.local/bin/.yazi.new" && cp "$dir/ya" "$HOME/.local/bin/.ya.new" \
     && chmod 755 "$HOME/.local/bin/.yazi.new" "$HOME/.local/bin/.ya.new" \
     && mv -f "$HOME/.local/bin/.yazi.new" "$HOME/.local/bin/yazi" && mv -f "$HOME/.local/bin/.ya.new" "$HOME/.local/bin/ya"; then
    rc=0
  fi
  rm -rf "$tmp" "$HOME/.local/bin/.yazi.new" "$HOME/.local/bin/.ya.new"
  return $rc
}

# what makes yazi's previews and search work: PDFs (poppler), archives (7-Zip), find (fd), search in files (ripgrep),
# fuzzy find and jump to folders (fzf, zoxide). Best effort: whatever your repos have; none of it is required.
yazi_extras() {
  case "$FAMILY" in
    arch)    echo "poppler 7zip|p7zip fd ripgrep fzf zoxide" ;;
    fedora)  echo "poppler-utils 7zip|p7zip fd-find ripgrep fzf zoxide" ;;
    debian)  echo "poppler-utils 7zip|p7zip-full fd-find ripgrep fzf zoxide" ;;
  esac
}

install_yazi_extras() {
  local item alt pick want=() new=() skipped=() p alts=()
  for item in $(yazi_extras); do
    IFS='|' read -ra alts <<<"$item"; pick=""
    for alt in "${alts[@]}"; do pkg_installed "$alt" && { pick="$alt"; break; }; done
    if [ -z "$pick" ]; then
      for alt in "${alts[@]}"; do
        if [ "$dry" -eq 1 ] || pkg_available "$alt"; then pick="$alt"; break; fi
      done
    fi
    if [ -n "$pick" ]; then want+=("$pick"); else skipped+=("${alts[0]}"); fi
  done
  [ "${#skipped[@]}" -gt 0 ] && echo "   yazi extras not in your repos (fine - yazi works without them): ${skipped[*]}"
  for p in "${want[@]}"; do pkg_installed "$p" || new+=("$p"); done
  [ "${#new[@]}" -gt 0 ] || return 0
  say "installing yazi's preview and search helpers: ${new[*]}"
  if ! pkg_install "${new[@]}"; then
    for p in "${new[@]}"; do pkg_install "$p" >/dev/null 2>&1 || echo "   (could not install $p - yazi works without it)"; done
  fi
  record_new_pkgs "${new[@]}"
}

# fastfetch (the terminal greeting) is not packaged before Ubuntu 24.10 / Debian 13 - Ubuntu 24.04, Linux Mint 22:
# its official .deb from github.com/fastfetch-cli/fastfetch then, installed with apt (so the uninstaller removes it)
install_fastfetch_deb() {
  local arch tmp rc=1 had=0
  [ "$FAMILY" = debian ] && ! command -v fastfetch >/dev/null 2>&1 || return 0
  case "$(dpkg --print-architecture 2>/dev/null)" in
    amd64) arch=amd64 ;; arm64) arch=aarch64 ;; *) return 0 ;;
  esac
  command -v curl >/dev/null 2>&1 && command -v dpkg-deb >/dev/null 2>&1 || return 0
  pkg_installed fastfetch && had=1
  say "installing fastfetch from its official .deb (github.com/fastfetch-cli/fastfetch - your release has no package)"
  [ "$dry" -eq 1 ] && return 0
  tmp="$(mktemp -d)"; CLEANUP+=("$tmp"); chmod 755 "$tmp"
  if curl -fsSL --retry 2 -o "$tmp/fastfetch.deb" \
          "https://github.com/fastfetch-cli/fastfetch/releases/latest/download/fastfetch-linux-$arch.deb" \
     && chmod 644 "$tmp/fastfetch.deb" && [ "$(dpkg-deb -f "$tmp/fastfetch.deb" Package 2>/dev/null)" = fastfetch ] \
     && run $SUDO apt-get install -y "$tmp/fastfetch.deb"; then
    rc=0; [ "$had" -eq 1 ] || record_new_pkgs fastfetch
  else
    warn "fastfetch could not be installed - the terminal greeting stays off until you install it"
  fi
  rm -rf "$tmp"
  return $rc
}

ensure_file_manager() {
  say "checking the file manager: yazi (the default - it opens in the terminal)"
  if have_yazi; then
    echo "   yazi: already installed ($(yazi_version))"
  elif [ "$do_packages" -eq 0 ]; then
    echo "   yazi: not installed (--no-packages: Thunar opens instead until you install yazi)"
    return 0
  elif install_yazi && { [ "$dry" -eq 1 ] || have_yazi; }; then
    echo "   yazi: installed"
  else
    warn "yazi could not be installed - Thunar is your file manager (other ways: yazi-rs.github.io/docs/installation)"
    return 0
  fi
  [ "$do_packages" -eq 1 ] && install_yazi_extras
  return 0
}

# sed_file SED-ARGUMENTS... FILE: edit a file in place, keeping the file itself (its permissions, a link to it)
sed_file() {
  local f="${*: -1}" t rc
  t="$f.i3tmp.$$"; CLEANUP+=("$t")
  sed "${@:1:$#-1}" "$f" >"$t" 2>/dev/null && cat "$t" >"$f"
  rc=$?
  rm -f "$t"
  return $rc
}

# use ghostty as the terminal when it is installed, otherwise kitty (the configs ship with ghostty)
choose_terminal() {
  local t=ghostty
  command -v ghostty >/dev/null 2>&1 || t=kitty
  [ "$dry" -eq 1 ] && { say "terminal: ghostty if it installs, otherwise kitty"; return 0; }
  say "default terminal: $t"
  sed_file "s/^term=.*/term=\"$t\"/" "$cfg/i3/defaults.conf" 2>/dev/null || true
  sed_file "s/^\( *terminal: \).*/\1\"$t\";/" "$cfg/i3/rofi/00-terminal.rasi" 2>/dev/null || true
}

# yazi as the file manager when it is installed, otherwise Thunar (Settings > Keybindings changes it)
choose_file_manager() {
  [ "$dry" -eq 1 ] && { say "file manager: yazi if it is installed, otherwise Thunar"; return 0; }
  if have_yazi; then say "default file manager: yazi (opens in the terminal)"; return 0; fi
  command -v thunar >/dev/null 2>&1 || return 0
  say "default file manager: Thunar (yazi is not installed)"
  sed_file 's/^files=.*/files="thunar"/' "$cfg/i3/defaults.conf" 2>/dev/null || true
}

# Folders opened from other programs (xdg-open, a browser's "Show in folder"...) go to the same file manager
# (yazi by default), through a small launcher entry. It becomes the default for folders on a first install, or
# when you had not picked one yourself; uninstall puts back what was set before.
FOLDERS_DESKTOP=i3wm-dots-folders.desktop
mime_default() {   # mime_default TYPE: the program ~/.config/mimeapps.list sets for it (nothing: none set there)
  awk -v t="$1" '/^\[/ { s = ($0 == "[Default Applications]") }
                 s && index($0, t "=") == 1 { print substr($0, length(t) + 2); exit }' "$cfg/mimeapps.list" 2>/dev/null
}
set_mime_default() {   # set_mime_default TYPE DESKTOP-ID  (in [Default Applications] of ~/.config/mimeapps.list)
  local f="$cfg/mimeapps.list" real tmp src=/dev/null
  real="$(readlink -f -- "$f" 2>/dev/null)"; [ -n "$real" ] || real="$f"     # (a linked file stays a link)
  tmp="$real.i3tmp"; CLEANUP+=("$tmp")
  if [ -f "$real" ]; then cp -p -- "$real" "$tmp" || return 1; src="$real"; fi
  awk -v t="$1" -v d="$2" '
    /^\[/ { if (s && !done) { print t "=" d ";"; done = 1 }
            s = ($0 == "[Default Applications]"); if (s) seen = 1 }
    s && index($0, t "=") == 1 { if (!done) { print t "=" d ";"; done = 1 } next }
    { print }
    END { if (!done) { if (!seen) { if (NR) print ""; print "[Default Applications]" } print t "=" d ";" } }' "$src" >"$tmp" \
    && mv -f -- "$tmp" "$real"
}
install_folder_handler() {
  local apps="${XDG_DATA_HOME:-$HOME/.local/share}/applications" launcher="$cfg/i3/scripts/LaunchFileManager.sh" cur exec
  case "$launcher" in
    *[\"\`\$\\%]*|*$'\n'*) warn "folders from other programs keep opening as before (your home folder's name has characters a launcher entry cannot hold)"; return 0 ;;
  esac
  [ -f "$apps/$FOLDERS_DESKTOP" ] || record path "$apps/$FOLDERS_DESKTOP"
  # quoted only when it has to be (a space in the path): xdg-open before 1.2 cannot run a quoted program path
  exec="$launcher"; case "$launcher" in *[!A-Za-z0-9/._+-]*) exec="\"$launcher\"" ;; esac
  cur="$(mime_default inode/directory)"
  if [ "$dry" -eq 1 ]; then
    say "folders from other programs open in your file manager ($apps/$FOLDERS_DESKTOP)"; return 0
  fi
  mkdir -p "$apps" && printf '%s\n' '[Desktop Entry]' 'Type=Application' 'Name=Folders (i3wm-dots)' \
    'Comment=Opens folders in the file manager chosen in the i3 Settings window (yazi by default)' \
    "Exec=$exec --open %u" 'Icon=system-file-manager' 'Terminal=false' 'NoDisplay=true' \
    'MimeType=inode/directory;' >"$apps/$FOLDERS_DESKTOP" || return 0
  case "$cur" in "$FOLDERS_DESKTOP"*) return 0 ;; esac
  if [ "$first_install" -eq 1 ] || [ -z "$cur" ]; then
    say "folders opened from other programs now go to your file manager too (before: ${cur:-the system default})"
    record mime "inode/directory ${cur:--}"
    set_mime_default inode/directory "$FOLDERS_DESKTOP" || warn "could not set the default for folders in $cfg/mimeapps.list"
  fi
}

install_packages() {
  if [ "$FAMILY" = unknown ]; then
    warn "Unsupported distro (automated: Fedora, Arch and Debian/Ubuntu families; the BSDs: github.com/OmitGhostly/i3-bsd)."
    warn "Install yourself:  i3 (>=4.22) xorg polybar picom dunst rofi kitty feh maim xdotool xclip xss-lock i3lock"
    warn "  imagemagick brightnessctl pamixer playerctl pavucontrol nm-applet redshift clipmenu|copyq numlockx xinput"
    warn "  xrandr xprop xdpyinfo setxkbmap libnotify mpv qalc jq curl arandr thunar polkit-gnome|mate-polkit lxappearance fastfetch bluez blueman pactl touchegg"
    warn "  yazi file (the file manager: yazi-rs.github.io/docs/installation)"
    warn "then re-run with --no-packages"
    return 0
  fi
  say "$FAMILY-based system detected - checking which packages your repos provide"
  [ "$FAMILY" = debian ] && run $SUDO apt-get update

  local have=() item pick alt alts
  # shellcheck disable=SC2046
  for item in $(packages_for); do
    pick=""
    IFS='|' read -ra alts <<<"$item"
    # one of the choices you already have (copyq instead of clipmenu, your polkit agent...) - else the first there is
    if [ "${#alts[@]}" -gt 1 ]; then
      for alt in "${alts[@]}"; do pkg_installed "$alt" && { pick="$alt"; break; }; done
    fi
    if [ -z "$pick" ]; then
      for alt in "${alts[@]}"; do
        if [ "$dry" -eq 1 ] || pkg_available "$alt"; then pick="$alt"; break; fi
      done
    fi
    if [ -n "$pick" ]; then have+=("$pick"); else missing+=("${item//|/ or }"); fi
  done

  local new=() p
  for p in "${have[@]}"; do pkg_installed "$p" || new+=("$p"); done      # (not installed yet: ours if it gets installed)
  say "installing ${#have[@]} packages"
  if ! pkg_install "${have[@]}"; then
    warn "bulk install failed - retrying one package at a time so a single problem cannot block the rest"
    [ "$FAMILY" = arch ] && warn "(if pacman reported 404s, run 'sudo pacman -Syu' once and re-run this script)"
    for p in "${have[@]}"; do pkg_install "$p" || missing+=("$p"); done
  fi
  record_new_pkgs "${new[@]}"

  # Arch: try the AUR for anything the official repos did not have
  if [ "$FAMILY" = arch ] && [ "${#missing[@]}" -gt 0 ]; then
    local helper="" h m still=()
    for h in paru yay; do command -v "$h" >/dev/null 2>&1 && { helper="$h"; break; }; done
    if [ -n "$helper" ]; then
      say "trying the AUR with $helper for: ${missing[*]}"
      for m in "${missing[@]}"; do
        if run "$helper" -S --needed --noconfirm "$m"; then record_new_pkgs "$m"; else still+=("$m"); fi
      done
      missing=("${still[@]}")
    fi
  fi

  # Bluetooth needs its background service (the Bluetooth tab in the settings window and the bar icon use it)
  if command -v bluetoothctl >/dev/null 2>&1 && command -v systemctl >/dev/null 2>&1 \
     && ! systemctl is-enabled bluetooth >/dev/null 2>&1; then
    say "enabling the bluetooth service"
    run $SUDO systemctl enable --now bluetooth || warn "could not enable bluetooth - run: sudo systemctl enable --now bluetooth"
  fi
  # three-finger swipes: Touchégg reads the touchpad in a system service; your session runs its client (Gestures.sh)
  if command -v touchegg >/dev/null 2>&1 && command -v systemctl >/dev/null 2>&1 \
     && systemctl cat touchegg.service >/dev/null 2>&1 && ! systemctl is-enabled touchegg >/dev/null 2>&1; then
    say "enabling the touchegg service (touchpad swipe gestures)"
    run $SUDO systemctl enable --now touchegg || warn "could not enable touchegg - run: sudo systemctl enable --now touchegg"
  fi
}

install_font() {
  command -v fc-list >/dev/null 2>&1 || return 0
  # (grep reads all of fc-list's output: with -q it would stop early, and pipefail would count that as a failure)
  if fc-list 2>/dev/null | grep -iE 'fantasque.*nerd|nerd.*fantasque' >/dev/null; then return 0; fi
  if command -v curl >/dev/null 2>&1 && command -v unzip >/dev/null 2>&1; then
    say "installing FantasqueSansM Nerd Font (icons in the bar and terminal)"
    local fd="${XDG_DATA_HOME:-$HOME/.local/share}/fonts/FantasqueSansMNerd" tmp
    tmp="$(mktemp -d)"; CLEANUP+=("$tmp")
    # (the folder is written down before unpacking into it, so a stopped install still leaves it recorded)
    if run curl -fsSL -o "$tmp/f.zip" "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FantasqueSansMono.zip" \
       && { [ -e "$fd" ] || record path "$fd"; } && run mkdir -p "$fd" && run unzip -qo "$tmp/f.zip" -d "$fd"; then
      run fc-cache -f "$fd" >/dev/null 2>&1
    else
      warn "font download failed - install 'FantasqueSansM Nerd Font' yourself (nerdfonts.com) or icons will look broken"
    fi
    rm -rf "$tmp"
  else
    warn "FantasqueSansM Nerd Font missing and curl/unzip not available - install it from nerdfonts.com"
  fi
}

if [ "$do_packages" -eq 1 ]; then install_packages; install_fastfetch_deb || true; install_font; fi
[ "$update_mode" -eq 1 ] || ensure_terminals
[ "$update_mode" -eq 1 ] || ensure_file_manager
install_pokemon

# ---- copy configs ---------------------------------------------------------------
# a first install (not a re-install over our own files): only then does the first login pick a wallpaper
first_install=1
[ -f "$cfg/i3/.i3wm-dots-installed" ] && first_install=0
say "installing configs into $cfg"
run mkdir -p "$cfg"

# ~/.config/gtk-3.0 is shared: lxappearance keeps your GTK theme there and file managers keep their sidebar
# bookmarks there. It is never replaced - our settings (dark style, font) are merged into settings.ini instead.
# First install: they are set (a copy of your folder is kept as a backup); later installs and updates only add
# a setting that is missing, so a theme or font you picked yourself stays.
merge_gtk() {   # merge_gtk SRC_DIR TARGET_DIR
  local src="$1" target="$2" ini="$2/settings.ini" first=1 resumed=0 line key val
  [ -f "$target/.i3wm-dots-installed" ] && first=0
  # (the mark says "merging" while this runs: an install stopped halfway is finished by the next one, which then
  # neither makes a second backup nor treats the folder as already done)
  [ "$(cat "$target/.i3wm-dots-installed" 2>/dev/null)" = merging ] && { first=1; resumed=1; }
  rm -rf "$target".bak-*.part 2>/dev/null                # (a backup copy that a stopped install left unfinished)
  if [ "$first" -eq 1 ] && [ "$resumed" -eq 0 ] && [ -e "$target" ] && [ "$do_backup" -eq 1 ]; then
    # copied under a temporary name and renamed when complete: a half-made copy never looks like a backup
    run cp -a "$target" "$target.bak-$stamp.part" && run mv "$target.bak-$stamp.part" "$target.bak-$stamp" \
      && echo "   backup: $(basename "$target") -> $(basename "$target").bak-$stamp (copied; your bookmarks stay)"
  fi
  [ -L "$target" ] && run rm -f "$target"
  run mkdir -p "$target"
  [ "$dry" -eq 1 ] && return 0
  [ "$first" -eq 1 ] && printf 'merging\n' >"$target/.i3wm-dots-installed"
  [ -f "$src/settings.ini" ] || { : >"$target/.i3wm-dots-installed"; return 0; }
  [ -f "$ini" ] || printf '[Settings]\n' >"$ini"
  [ -s "$ini" ] && [ -n "$(tail -c1 "$ini")" ] && printf '\n' >>"$ini"      # (a last line without a newline)
  grep -q '^\[Settings\]' "$ini" || printf '[Settings]\n' >>"$ini"
  CLEANUP+=("$ini.tmp")
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*|';'*|'['*) continue ;; esac
    key="${line%%=*}"; key="${key%"${key##*[! ]}"}"; val="${line#*=}"
    [ -n "$key" ] || continue
    if grep -qE "^[[:space:]]*${key}[[:space:]]*=" "$ini"; then
      [ "$first" -eq 1 ] && KEY="$key" VAL="$val" awk 'BEGIN{k=ENVIRON["KEY"]; v=ENVIRON["VAL"]}
        { t=$0; sub(/^[ \t]*/,"",t); split(t,a,"="); s=a[1]; sub(/[ \t]*$/,"",s); if (s==k) { print k "=" v; next } } {print}' \
        "$ini" >"$ini.tmp" && mv -f "$ini.tmp" "$ini"
    else
      KEY="$key" VAL="$val" awk 'BEGIN{k=ENVIRON["KEY"]; v=ENVIRON["VAL"]} {print} /^\[Settings\]/ && !d {print k "=" v; d=1}' \
        "$ini" >"$ini.tmp" && mv -f "$ini.tmp" "$ini"
    fi
  done <"$src/settings.ini"
  : >"$target/.i3wm-dots-installed"
}

# What the Settings window saved is parked here while ~/.config/i3 is replaced (not in /tmp: an install or update
# stopped right then - Ctrl+C, a closed terminal - leaves it where the next run finds and puts it back)
keep_settings="${XDG_STATE_HOME:-$HOME/.local/state}/i3wm-dots/settings.json.keep"
for d in "$here"/config/*/; do
  name="$(basename "$d")"
  target="$cfg/$name"
  if [ "$name" = gtk-3.0 ]; then merge_gtk "$d" "$target"; continue; fi
  if [ -e "$target" ] || [ -L "$target" ]; then
    if [ -f "$target/.i3wm-dots-installed" ] && [ ! -L "$target" ]; then
      # Our own earlier install: replace it in place. Do NOT make another backup, or
      # --restore would give back the previous install instead of your original config.
      if [ "$dry" -eq 0 ] && [ "$name" = i3 ] && [ -f "$target/settings.json" ]; then
        { mkdir -p "${keep_settings%/*}" && cp -a "$target/settings.json" "$keep_settings.new" \
            && mv -f "$keep_settings.new" "$keep_settings"; } \
          || die "could not keep a copy of your Settings ($target/settings.json) - nothing was changed"
      fi
      run rm -rf "$target"
    elif [ "$do_backup" -eq 1 ]; then
      run mv "$target" "$target.bak-$stamp"; echo "   backup: $name -> $name.bak-$stamp"
    else
      run rm -rf "$target"
    fi
  fi
  run mkdir -p "$target"
  # marked as ours before anything is copied in: an install stopped halfway (Ctrl+C) then leaves a folder the next
  # run knows is its own - it replaces it, instead of backing it up as yours, so the backup of YOUR config stays the
  # one that uninstall / --restore gives back
  [ "$dry" -eq 0 ] && : > "$target/.i3wm-dots-installed"
  run cp -a "$d." "$target/" || die "could not copy $name to $target"
  # keep what the settings window saved (mouse, monitors, opacity, gaps, bar) across re-installs
  if [ "$name" = i3 ] && [ "$dry" -eq 0 ]; then
    if [ -f "$keep_settings" ]; then
      cp -a "$keep_settings" "$target/settings.json" && rm -f "$keep_settings"
    elif [ -f "$target.bak-$stamp/settings.json" ]; then
      cp -a "$target.bak-$stamp/settings.json" "$target/settings.json"
    fi
  fi
done

# the default terminal first (ghostty if installed, else kitty): the saved settings below come after it, so a
# terminal you picked in Settings > Apps is never reset by a re-install or an update
choose_terminal
choose_file_manager

if [ "$dry" -eq 0 ]; then
  find "$cfg/i3/scripts" -type f \( -name '*.sh' -o -name '*.py' \) -exec chmod +x {} + 2>/dev/null || true
  chmod +x "$cfg/polybar/launch.sh" 2>/dev/null || true
  # the fresh files have the default look: write your saved settings (accent colour, gaps, keybinds, opacity,
  # terminal theme and text size, cursor, apps) back into them, so restarting i3 (SUPER+SHIFT+R) shows them at once
  if [ -f "$cfg/i3/settings.json" ] && command -v python3 >/dev/null 2>&1; then
    if python3 "$cfg/i3/scripts/SettingsGUI.py" --refresh-files >/dev/null 2>&1; then
      say "kept your saved settings (Settings window) in the new files"
    else
      warn "could not re-apply your saved settings now - they come back at your next login"
    fi
  fi
fi
prepare_shell_rc
install_shell_hook
install_fish_hook
install_aquarium_alias
install_prompt
install_folder_handler

# ---- wallpapers / folders ---------------------------------------------------------
run mkdir -p "$HOME/Pictures/wallpapers" "$HOME/Pictures/Screenshots"
if [ -d "$here/wallpapers" ]; then
  for w in "$here"/wallpapers/*; do
    [ -f "$w" ] || continue
    t="$HOME/Pictures/wallpapers/${w##*/}"
    [ -e "$t" ] && continue                          # (yours, or copied earlier: never overwritten)
    record path "$t" && run cp "$w" "$t"           # (written down first: a stopped install still has it listed)
  done
  say "copied bundled wallpapers to ~/Pictures/wallpapers"
fi
if [ "$do_wallpapers" -eq 1 ]; then
  command -v git >/dev/null 2>&1 || die "git is required for --wallpapers"
  say "downloading wallpaper bank (this can take a while)"
  tmp="$(mktemp -d)"; CLEANUP+=("$tmp")
  if run git clone --depth=1 https://github.com/LinuxBeginnings/Wallpaper-Bank.git "$tmp/wb"; then
    for w in "$tmp"/wb/wallpapers/*; do
      [ -f "$w" ] && [ ! -e "$HOME/Pictures/wallpapers/${w##*/}" ] || continue
      record path "$HOME/Pictures/wallpapers/${w##*/}" && run cp "$w" "$HOME/Pictures/wallpapers/${w##*/}"
    done
  else
    warn "wallpaper download failed"
  fi
  rm -rf "$tmp"
fi

# ---- the mouse cursor: Capitaine Cursors, the default (Settings > Mouse > Mouse cursor picks another) --------------
# Unpacked into your home folder on every system (no package, no password); also linked into ~/.icons for programs
# that only look there. A copy that is already there (yours, or from an earlier install) is kept as it is.
install_cursor() {
  local tarball="$here/assets/cursors/capitaine-cursors.tar.gz"
  local icons="${XDG_DATA_HOME:-$HOME/.local/share}/icons" tmp
  local dest="$icons/capitaine-cursors"
  [ -f "$tarball" ] || return 0
  if [ ! -e "$dest" ] && [ ! -L "$dest" ]; then
    if [ "$dry" -eq 1 ]; then
      printf '   + unpack %s into %s\n' "${tarball#"$here"/}" "$dest"
    else
      mkdir -p "$icons" || { warn "could not create $icons - the default cursor is not installed"; return 0; }
      rm -rf "$icons"/.i3dots-cursor.??????        # (left by an install that was stopped halfway)
      tmp=$(mktemp -d "$icons/.i3dots-cursor.XXXXXX") || return 0
      CLEANUP+=("$tmp")
      # (gzip + tar: every tar reads this; written down before it is moved into place, so a
      # stopped install can never leave it there unrecorded)
      if gzip -dc "$tarball" | (cd "$tmp" && tar -xf -) && [ -f "$tmp/capitaine-cursors/index.theme" ] \
         && [ -e "$tmp/capitaine-cursors/cursors/left_ptr" ] && record path "$dest" && mv "$tmp/capitaine-cursors" "$dest"; then
        say "installed the Capitaine Cursors theme (the default cursor)"
      else
        warn "could not unpack the cursor theme - the cursor stays as it is"
      fi
      rm -rf "$tmp"
    fi
  fi
  if [ -d "$dest" ] && [ ! -e "$HOME/.icons/capitaine-cursors" ] && [ ! -L "$HOME/.icons/capitaine-cursors" ]; then
    run mkdir -p "$HOME/.icons" && record path "$HOME/.icons/capitaine-cursors" \
      && run ln -s "$dest" "$HOME/.icons/capitaine-cursors"
  fi
  # write the cursor (the one picked in Settings, else this default) into the files now, so the next login already
  # starts with it - i3 then needs no restart to pick it up (files only: the running session is not touched)
  if [ "$dry" -eq 0 ] && command -v python3 >/dev/null 2>&1; then
    python3 "$cfg/i3/scripts/SettingsGUI.py" --cursor-files >/dev/null 2>&1 || true
  fi
}
install_cursor

# first login picks a wallpaper and generates colors (a re-install or update keeps your wallpaper)
[ "$first_install" -eq 1 ] && run rm -f "${XDG_CACHE_HOME:-$HOME/.cache}/i3/first-run-done" \
  "${XDG_STATE_HOME:-$HOME/.local/state}/i3wm-dots/first-run-done"

# ---- updates: after a system update, a check for a newer config (a notification; installing is up to you) ---------
# (i3dots-update = ~/.config/i3/scripts/Update.sh; the pacman / dnf / apt hook asks it to check after a system update)
setup_updates() {
  local state="${XDG_DATA_HOME:-$HOME/.local/share}/i3wm-dots-updater" url="" unit="$cfg/systemd/user/i3dots-update.service"
  if [ "$dry" -eq 1 ]; then
    say "would set up i3dots-update$( [ "$do_autoupdate" -eq 1 ] && [ "$do_packages" -eq 1 ] && echo " and the system update hook")"
    return 0
  fi
  mkdir -p "$state" "$HOME/.local/bin"
  mkdir -p "$cfg/systemd/user"
  if [ "$update_mode" -eq 0 ]; then
    # where updates come from: the repo this was installed from (its GitHub address), else the main repo
    url="$(git -C "$here" config --get remote.origin.url 2>/dev/null || true)"
    case "$url" in https://*|git@*) ;; *) url="$REPO_URL" ;; esac
    printf '%s\n' "$(repo_moved "$url")" >"$state/repo-url"
    git -C "$here" rev-parse HEAD >"$state/applied" 2>/dev/null || rm -f "$state/applied"
    [ "$do_autoupdate" -eq 1 ] && rm -f "$state/off"
    [ "$do_autoupdate" -eq 0 ] && : >"$state/off"
  elif [ -f "$state/repo-url" ]; then
    # an update: a desktop that still gets its updates from the old repo address switches to the new one
    url="$(repo_moved "$(head -n1 "$state/repo-url")")"
    [ "$url" = "$(head -n1 "$state/repo-url")" ] || { printf '%s\n' "$url" >"$state/repo-url"; say "updates now come from $url"; }
  fi
  # (the systemd unit the system hooks start - see Update.sh --install-hook)
  cat >"$unit" <<'UNIT'
[Unit]
Description=Check GitHub for a newer i3wm-dots desktop config (started after a system update)

[Service]
Type=oneshot
ExecStart=%h/.config/i3/scripts/Update.sh --auto
Nice=10
UNIT
  command -v systemctl >/dev/null 2>&1 && systemctl --user daemon-reload >/dev/null 2>&1 || true
  ln -sfn "$cfg/i3/scripts/Update.sh" "$HOME/.local/bin/i3dots-update"
  # the uninstaller, as a copy that outlives ~/.config/i3:  i3dots-uninstall
  [ -f "$here/uninstall.sh" ] && install -m 755 "$here/uninstall.sh" "$HOME/.local/bin/i3dots-uninstall"
  [ "$update_mode" -eq 1 ] && return 0
  case ":$orig_path:" in
    *":$HOME/.local/bin:"*) ;;
    *) say "note: ~/.local/bin is not in your PATH - run the updater as ~/.local/bin/i3dots-update (or add that folder to PATH)" ;;
  esac
  if [ "$do_autoupdate" -eq 0 ]; then
    say "no update checks after system updates (update by hand with: i3dots-update)"
  elif [ "$do_packages" -eq 1 ] && [ "$FAMILY" != unknown ]; then
    say "setting up a check for a newer config after system updates (pacman -Syu / dnf upgrade / apt upgrade)"
    bash "$cfg/i3/scripts/Update.sh" --install-hook || warn "could not set up the system update hook - run later: i3dots-update --install-hook"
  else
    say "to check for a newer config after system updates, run once:  i3dots-update --install-hook"
  fi
}
setup_updates

# ---- sanity checks -----------------------------------------------------------------
if [ "$dry" -eq 0 ]; then
  checks="i3 polybar picom dunst rofi feh maim xdotool xclip i3lock brightnessctl pamixer playerctl notify-send xrandr xprop"
  for c in $checks; do
    command -v "$c" >/dev/null 2>&1 || missing+=("$c")
  done
  command -v ghostty >/dev/null 2>&1 || command -v kitty >/dev/null 2>&1 || missing+=("a terminal (ghostty or kitty)")
  command -v clipmenu >/dev/null 2>&1 || command -v copyq >/dev/null 2>&1 || missing+=("clipmenu or copyq")
  [ "$do_pokemon" -eq 0 ] || command -v fastfetch >/dev/null 2>&1 || missing+=("fastfetch (the Mimikyu greeting in the terminal)")
  if command -v i3 >/dev/null 2>&1; then
    ver="$(i3 --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -n1)"
    if [ -n "$ver" ] && awk -v v="$ver" 'BEGIN { split(v, a, "."); exit !(a[1] < 4 || (a[1] == 4 && a[2] < 22)) }'; then
      warn "i3 $ver is older than 4.22 - the 'gaps' lines in the config need >= 4.22 (use a newer distro release or build i3)"
    fi
    if i3 -C -c "$cfg/i3/config" >/dev/null 2>&1; then say "i3 config validated OK"
    else warn "i3 rejected the config - see:  i3 -C -c ~/.config/i3/config"; fi
  fi
  if [ ! -e /usr/share/xsessions/i3.desktop ] && [ ! -e /usr/local/share/xsessions/i3.desktop ]; then
    warn "no 'i3' session file in /usr/share/xsessions - the login screen may not list i3"
  fi
  if [ "$FAMILY" = fedora ] && ! rpm -q xorg-x11-server-Xorg >/dev/null 2>&1; then
    warn "Xorg server is not installed - i3 cannot start without it:  sudo dnf install xorg-x11-server-Xorg"
  fi
fi

# ---- summary -------------------------------------------------------------------------
if [ "$update_mode" -eq 1 ]; then
  say "config updated"
  exit 0
fi
if [ "${#missing[@]}" -gt 0 ]; then
  echo
  warn "could not be installed automatically: $(printf '%s\n' "${missing[@]}" | sort -u | tr '\n' ' ')"
  warn "install them manually, or the matching keybinds/modules will do nothing (log: ~/.cache/i3wm-dots-install.log)"
fi

# shellcheck source=/dev/null
os_id="$( . "${I3DOTS_OS_RELEASE:-/etc/os-release}" 2>/dev/null; echo "${ID:-}" )"
case "$os_id:${XDG_CURRENT_DESKTOP:-}" in
  linuxmint:*) how='Linux Mint: log out, then on the login screen click the small round icon next to your name and choose "i3".' ;;
  *:*GNOME*) how='GNOME: log out, click your name, then the gear icon (bottom-right) and choose "i3".' ;;
  *:*KDE*)   how='KDE: log out, then choose "i3" in the "Desktop Session" menu under the password box (older KDE login screens: the session menu at the bottom-left).' ;;
  *)         how='Log out and choose the "i3" session at your login screen (or put "exec i3" in ~/.xinitrc).' ;;
esac
how="$how
       If i3 is not in the list, restart the computer once (the login screen looks for X11 when it starts)."
cat <<MSG

Done.  $how
  - SUPER+H shows every keybind.  SUPER+W picks a wallpaper.
  - SUPER+ALT+M opens Settings (mouse and touchpad gestures, displays, appearance and bar styles, accent colour,
    terminal themes, keybindings, sound, Bluetooth, Wi-Fi).
  - On a touchpad, swipe with three fingers to change workspace (left = next, right = previous).
  - Terminal: Ghostty (kitty if Ghostty could not be installed). Change it in Settings > Keybindings (the terminal row).
  - New terminal windows greet you with the Mimikyu fastfetch and the black / grey / white prompt
    (bash and zsh; open a new terminal to see them).
  - Your old desktop is untouched - pick it again at the login screen any time.
  - Undo the dotfiles:  ./install.sh --restore
  - Remove it all again (the config, and if you want i3 and the programs it added):  ./uninstall.sh  or  i3dots-uninstall
  - Updates: after a system update (pacman -Syu / dnf upgrade / apt upgrade) you get a notification when a newer
    config is out on GitHub - nothing changes until you run:  i3dots-update   (keeps your Settings; files you edited
    by hand are replaced - undo: i3dots-update --undo)   No more checks: i3dots-update --off
MSG
# The login screen has to offer X11 sessions for i3. GNOME's GDM still does (Fedora 43-45, Ubuntu: GNOME itself is
# Wayland-only now, other desktops' X11 sessions are not), and so do KDE's Plasma Login Manager (Fedora 44+), SDDM
# and LightDM - unless X11 was switched off in GDM's settings, which hides i3 from the list.
sysroot="${I3DOTS_TEST_ROOT:-}"
dm="$(readlink "$sysroot/etc/systemd/system/display-manager.service" 2>/dev/null)"; dm="${dm##*/}"; dm="${dm%.service}"
case "$dm" in
  gdm|gdm3)
    for f in "$sysroot/etc/gdm/custom.conf" "$sysroot/etc/gdm3/custom.conf" "$sysroot/etc/gdm3/daemon.conf"; do
      [ -r "$f" ] || continue
      if awk '/^[ \t]*\[/ { d = ($0 ~ /^[ \t]*\[daemon\][ \t]*$/) }
              d && /^[ \t]*XorgEnable[ \t]*=[ \t]*(false|0)[ \t]*$/ { off = 1 }
              END { exit !off }' "$f"; then
        cat <<MSG

Login screen: GDM is set to hide X11 sessions (XorgEnable=false in ${f#"$sysroot"}), so "i3" will not be listed.
Allow them again, then restart the computer:
  sudo sed -i 's/^[ \t]*XorgEnable[ \t]*=.*/XorgEnable=true/' ${f#"$sysroot"}
MSG
      fi
    done ;;
esac
