#!/usr/bin/env bash
# The polkit agent: the window that asks for your password when a program needs more rights. The one your desktop
# (GNOME, KDE, Cinnamon, Xfce, MATE, LXQt) brings is used when it is there, else the one the installer added.
pgrep -u "$UID" -f 'polkit-gnome-authentication-agent-1|polkit-kde-authentication-agent-1|polkit-mate-authentication-agent-1|lxpolkit|xfce-polkit|lxqt-policykit-agent' >/dev/null && exit 0
for p in /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 /usr/libexec/polkit-gnome-authentication-agent-1 \
  /usr/lib/x86_64-linux-gnu/polkit-gnome-authentication-agent-1 /usr/lib/policykit-1-gnome/polkit-gnome-authentication-agent-1 \
  /usr/libexec/polkit-mate-authentication-agent-1 /usr/lib/mate-polkit/polkit-mate-authentication-agent-1 \
  /usr/libexec/kf6/polkit-kde-authentication-agent-1 /usr/lib/x86_64-linux-gnu/libexec/kf6/polkit-kde-authentication-agent-1 \
  /usr/lib/polkit-kde-authentication-agent-1 /usr/libexec/polkit-kde-authentication-agent-1 \
  /usr/lib/x86_64-linux-gnu/libexec/polkit-kde-authentication-agent-1 \
  /usr/bin/lxqt-policykit-agent /usr/bin/lxpolkit /usr/lib/xfce-polkit/xfce-polkit /usr/libexec/xfce-polkit; do
  [ -x "$p" ] && { "$p" & exit 0; }
done
notify-send "Polkit" "No polkit agent found (install mate-polkit or polkit-gnome)"
