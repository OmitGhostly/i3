#!/bin/sh
# Platform.sh - the system's sound, brightness, battery, cpu, memory, Wi-Fi and power, in one place.
# The scripts, the bar and the settings window ask this instead of calling the system's own tools themselves.
#
#   Platform.sh os                         linux | other
#   Platform.sh distro                     the system's name: Fedora Linux, Arch Linux, Linux Mint ...
#   Platform.sh volume [get|muted|up N|down N|mute|unmute|toggle]      N in percent; get prints 0-100, muted yes|no
#   Platform.sh mic    [get|muted|up N|down N|toggle]
#   Platform.sh brightness [get|set N|up N|down N]
#   Platform.sh battery                    "PERCENT STATE" (charging | discharging | full); nothing: no battery
#   Platform.sh cpu | memory               percent in use
#   Platform.sh wifi                       "SSID<tab>SIGNAL" while connected (SIGNAL can be empty); nothing if not
#   Platform.sh has battery|backlight|wifi|volume     answers with the exit status
#   Platform.sh power suspend|hibernate|reboot|poweroff
#   Platform.sh airplane [state|toggle|on|off]   airplane mode (no Wi-Fi): prints on | off
#   Platform.sh bar ITEM                   an item's text for polybar: network volume backlight battery cpu memory
#   Platform.sh plain ITEM...              the same without polybar's colour tags (for i3's own bar, used when
#                                          polybar is not installed); several items: one "ITEM<tab>TEXT" line each
#   Platform.sh nproc                      number of CPUs
#
# Volume: pamixer when a sound server answers it, else PipeWire's wpctl. Brightness: brightnessctl, else xbacklight
# (screens that RandR can dim). Power: systemd (logind).

case "${I3DOTS_OS:-$(uname -s 2>/dev/null)}" in
  Linux|linux) OS=linux ;;
  *) OS=other ;;
esac
SYSFS="${I3DOTS_SYSFS:-/sys}"
PROCFS="${I3DOTS_PROCFS:-/proc}"

have() { command -v "$1" >/dev/null 2>&1; }
# a whole number from a decimal ("0.502" * 100 = 50), clamped to 0..100
pct_of() { awk -v v="$1" -v m="${2:-1}" 'BEGIN { p = v * 100 / m; if (p < 0) p = 0; if (p > 100) p = 100; printf "%d\n", p + 0.5 }'; }
first_number() { tr -c '0-9.\n' ' ' | awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+(\.[0-9]+)?$/) { print $i; exit } }'; }
state_dir() {
  d="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}"
  [ -d "$d" ] && [ -w "$d" ] || d=/tmp
  printf '%s\n' "$d"
}

distro() {
  case "$OS" in
    linux) (
      # shellcheck disable=SC1091
      . /etc/os-release 2>/dev/null; printf '%s\n' "${NAME:-Linux}") ;;
    *) uname -s 2>/dev/null || echo unknown ;;
  esac
}

# ------------------------------------------------------------------ sound
vol_backend() {
  if have pamixer && pamixer --get-volume >/dev/null 2>&1; then echo pamixer; return; fi
  have wpctl && wpctl get-volume @DEFAULT_AUDIO_SINK@ >/dev/null 2>&1 && echo wpctl
}

# sound KIND ACTION [N]   KIND: out | in (the microphone)
sound() {
  kind=$1; action=${2:-get}; n=${3:-5}
  case "$n" in ''|*[!0-9]*) n=5 ;; esac
  b=$(vol_backend)
  [ -n "$b" ] || return 1
  case "$b" in
    pamixer)
      src=""; [ "$kind" = in ] && src=--default-source
      case "$action" in
        get) pamixer $src --get-volume 2>/dev/null ;;
        muted) if [ "$(pamixer $src --get-mute 2>/dev/null)" = true ]; then echo yes; else echo no; fi ;;
        up) if [ "$kind" = out ]; then pamixer -i "$n" --allow-boost --set-limit 150; else pamixer $src -i "$n"; fi ;;
        down) pamixer $src -d "$n" ;;
        mute) pamixer $src -m ;;
        unmute) pamixer $src -u ;;
        toggle) pamixer $src -t ;;
      esac ;;
    wpctl)          # PipeWire and no pamixer: "Volume: 0.40 [MUTED]"
      dev=@DEFAULT_AUDIO_SINK@; [ "$kind" = in ] && dev=@DEFAULT_AUDIO_SOURCE@
      case "$action" in
        get) pct_of "$(wpctl get-volume "$dev" 2>/dev/null | first_number)" ;;
        muted) case "$(wpctl get-volume "$dev" 2>/dev/null)" in *MUTED*) echo yes ;; *) echo no ;; esac ;;
        up) wpctl set-volume -l 1.5 "$dev" "$n%+" ;;
        down) wpctl set-volume "$dev" "$n%-" ;;
        mute) wpctl set-mute "$dev" 1 ;;
        unmute) wpctl set-mute "$dev" 0 ;;
        toggle) wpctl set-mute "$dev" toggle ;;
      esac ;;
  esac
}

# ------------------------------------------------------------------ screen brightness
xbl_ok() { have xbacklight && [ -n "$(xbacklight -get 2>/dev/null | first_number)" ]; }
bl_backend() {
  have brightnessctl && ls "$SYSFS"/class/backlight/* >/dev/null 2>&1 && { echo brightnessctl; return; }
  xbl_ok && echo xbacklight
}
bl_read() {
  case "$1" in
    brightnessctl) brightnessctl -m 2>/dev/null | cut -d, -f4 | tr -d '%' ;;
    xbacklight) xbacklight -get 2>/dev/null ;;
  esac
}
brightness() {
  action=${1:-get}; n=${2:-10}
  case "$n" in ''|*[!0-9]*) n=10 ;; esac
  b=$(bl_backend)
  [ -n "$b" ] || return 1
  cur=$(bl_read "$b" | first_number)
  cur=$(pct_of "${cur:-0}" 100)
  case "$action" in
    get) echo "$cur"; return 0 ;;
    set) new=$n ;;
    up) new=$((cur + n)) ;;
    down) new=$((cur - n)) ;;
    *) return 2 ;;
  esac
  [ "$new" -lt 5 ] && new=5          # never all the way to black
  [ "$new" -gt 100 ] && new=100
  case "$b" in
    brightnessctl) brightnessctl -q set "$new%" ;;
    xbacklight) xbacklight -set "$new" ;;
  esac
}

# ------------------------------------------------------------------ battery
battery() {
  for d in "$SYSFS"/class/power_supply/*; do
    [ "$(cat "$d/type" 2>/dev/null)" = Battery ] || continue
    [ "$(cat "$d/scope" 2>/dev/null)" = Device ] && continue      # (a wireless mouse's battery)
    p=$(cat "$d/capacity" 2>/dev/null); s=$(cat "$d/status" 2>/dev/null)
    [ -n "$p" ] || continue
    case "$s" in Charging) s=charging ;; Full|"Not charging") s=full ;; *) s=discharging ;; esac
    echo "$p $s"; return 0
  done
  return 1
}

# ------------------------------------------------------------------ cpu / memory
cpu_sample() {   # "TOTAL IDLE" since boot
  awk '/^cpu / { t = 0; for (i = 2; i <= NF; i++) t += $i; print t, $5 + $6; exit }' "$PROCFS/stat" 2>/dev/null
}
cpu() {
  f="$(state_dir)/i3dots-cpu-$(id -u)${1:+-$1}"
  now=$(cpu_sample)
  [ -n "$now" ] || return 1
  prev=$(cat "$f" 2>/dev/null)
  if [ -z "$prev" ]; then prev=$now; sleep 0.4; now=$(cpu_sample); fi
  printf '%s\n' "$now" >"$f" 2>/dev/null
  printf '%s %s\n' "$prev" "$now" | awk '{ dt = $3 - $1; di = $4 - $2; if (dt <= 0) { print 0; exit }
    p = (dt - di) * 100 / dt; if (p < 0) p = 0; printf "%d\n", p + 0.5 }'
}
memory() {
  awk '/^MemTotal:/ { t = $2 } /^MemAvailable:/ { a = $2 } END { if (t) printf "%d\n", (t - a) * 100 / t + 0.5 }' "$PROCFS/meminfo" 2>/dev/null
}

# ------------------------------------------------------------------ Wi-Fi
wifi() {
  have nmcli || return 1
  nmcli -t -f ACTIVE,SSID,SIGNAL dev wifi 2>/dev/null | awk -F: '$1 == "yes" { printf "%s\t%s\n", $2, $3; exit }'
}
has_wifi() {
  ls -d "$SYSFS"/class/net/*/wireless "$SYSFS"/class/net/*/phy80211 >/dev/null 2>&1
}

# airplane: Wi-Fi off / on (rfkill)
airplane() {
  have rfkill || return 1
  if rfkill list wifi 2>/dev/null | grep -q "Soft blocked: yes"; then st=on; else st=off; fi
  case "${1:-state}" in
    state) echo "$st"; return 0 ;;
    toggle) if [ "$st" = on ]; then want=off; else want=on; fi ;;
    on|off) want=$1 ;;
    *) return 2 ;;
  esac
  if [ "$want" = on ]; then rfkill block wifi; else rfkill unblock wifi; fi && echo "$want"
}

# ------------------------------------------------------------------ power
power() {
  case "$1" in
    suspend|hibernate|reboot|poweroff) systemctl "$1" 2>/dev/null || loginctl "$1" 2>/dev/null ;;
    *) return 1 ;;
  esac
}

# ------------------------------------------------------------------ text for the bar
# polybar: the Flat style shows the prefixes dimmed (like its built-in modules); the block styles colour the block
bar_text() {
  mode=$1; item=$2
  dim() {
    if [ "$mode" = bar ] && [ "${BAR_STYLE:-flat}" = flat ]; then printf '%%{F#6e6e6e}%s%%{F-}' "$1"; else printf '%s' "$1"; fi
  }
  flat=no; [ "$mode" = bar ] && [ "${BAR_STYLE:-flat}" = flat ] && flat=yes
  case "$item" in
    network|wifi)
      has_wifi || return 0
      w=$(wifi)
      if [ -z "$w" ]; then dim "󰖪"; echo; return 0; fi
      ssid=$(printf '%s' "$w" | cut -f1); sig=$(printf '%s' "$w" | cut -f2)
      icon="󰤨"
      case "$sig" in [0-9]*) if [ "$sig" -lt 25 ]; then icon="󰤯"; elif [ "$sig" -lt 50 ]; then icon="󰤟"
                             elif [ "$sig" -lt 75 ]; then icon="󰤢"; fi ;; esac
      printf '%s %s%s\n' "$icon" "$ssid" "${sig:+ $sig%}" ;;
    volume|pulseaudio)
      v=$(sound out get) || return 0
      [ -n "$v" ] || return 0
      if [ "$(sound out muted)" = yes ]; then dim "󰝟 muted"; echo; return 0; fi
      if [ "$v" -lt 34 ]; then icon="󰕿"; elif [ "$v" -lt 67 ]; then icon="󰖀"; else icon="󰕾"; fi
      printf '%s %s%%\n' "$icon" "$v" ;;
    backlight|brightness)
      v=$(brightness get) || return 0
      printf '󰃟 %s%%\n' "$v" ;;
    battery)
      b=$(battery) || return 0
      p=${b%% *}; s=${b#* }
      if [ "$s" = charging ]; then icon="󰂄"
      elif [ "$s" = full ] || [ "$p" -ge 99 ]; then icon="󰁹"
      elif [ "$p" -le 15 ]; then icon="󰂃"
      elif [ "$p" -lt 30 ]; then icon="󰁺"
      elif [ "$p" -lt 50 ]; then icon="󰁼"
      elif [ "$p" -lt 70 ]; then icon="󰁾"
      elif [ "$p" -lt 90 ]; then icon="󰂀"
      else icon="󰁹"; fi
      printf '%s %s%%\n' "$icon" "$p" ;;
    cpu)
      v=$(cpu "$mode") || return 0
      if [ "$flat" = yes ]; then dim "󰻠 CPU "; printf '%2d%%\n' "$v"; else printf '󰻠 %2d%%\n' "$v"; fi ;;
    memory)
      v=$(memory) || return 0
      [ -n "$v" ] || return 0
      if [ "$flat" = yes ]; then dim "󰍛 RAM "; printf '%2d%%\n' "$v"; else printf '󰍛 %2d%%\n' "$v"; fi ;;
    *) return 2 ;;
  esac
}

# ------------------------------------------------------------------ main
cmd=${1:-os}
[ $# -gt 0 ] && shift
case "$cmd" in
  os) echo "$OS" ;;
  distro) distro ;;
  volume) sound out "$@" ;;
  mic) sound in "$@" ;;
  brightness) brightness "$@" ;;
  battery) battery ;;
  cpu) cpu ;;
  memory) memory ;;
  wifi) wifi ;;
  nproc) getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 1 ;;
  has)
    case "${1:-}" in
      battery) battery >/dev/null ;;
      backlight) [ -n "$(bl_backend)" ] ;;
      wifi) has_wifi ;;
      volume) [ -n "$(vol_backend)" ] ;;
      *) exit 2 ;;
    esac || exit 1 ;;
  power) power "${1:-}" ;;
  airplane) airplane "${1:-state}" ;;
  bar|plain)
    if [ $# -le 1 ]; then bar_text "$cmd" "${1:-}"
    else                            # several items: "ITEM<tab>TEXT" lines (one call for i3's own bar)
      for it in "$@"; do t=$(bar_text "$cmd" "$it" 2>/dev/null); printf '%s\t%s\n' "$it" "$t"; done
    fi ;;
  *) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
esac
