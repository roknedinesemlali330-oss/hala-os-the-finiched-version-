#!/bin/sh
# The desktop session started after login (by the greeter or by agreety).
export QS_ICON_THEME=Papirus
export MOZ_ENABLE_WAYLAND=1
export QT_QUICK_BACKEND=software

CONF=/etc/myos/hyprland.conf
if systemd-detect-virt -q; then
  CONF=/etc/myos/hyprland-vm.conf
  export WLR_NO_HARDWARE_CURSORS=1
  export WLR_RENDERER_ALLOW_SOFTWARE=1
fi

if Hyprland -c "$CONF"; then
  exit 0
else
  exec sway
fi
