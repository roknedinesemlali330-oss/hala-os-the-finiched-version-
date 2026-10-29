#!/bin/sh
# Start the graphical login screen inside a tiny Hyprland.
# If the greeter fails, fall back to a plain text login so you are never locked out.
export QT_QUICK_BACKEND=software
export QS_ICON_THEME=Papirus
export XCURSOR_THEME=Adwaita
if systemd-detect-virt -q; then
  export WLR_NO_HARDWARE_CURSORS=1
  export WLR_RENDERER_ALLOW_SOFTWARE=1
fi
rm -f /tmp/myos-greeter-failed
Hyprland -c /etc/myos/greeter-hypr.conf
if [ -e /tmp/myos-greeter-failed ]; then
  rm -f /tmp/myos-greeter-failed
  exec agreety --cmd "sh /etc/myos/session.sh"
fi
