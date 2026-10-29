# Environment for the MyOS desktop session
export QS_ICON_THEME=Papirus
export MOZ_ENABLE_WAYLAND=1
export QT_QUICK_BACKEND=software

# Safe mode: boot with  myos.nogreeter  and the desktop starts from the first console
if grep -q myos.nogreeter /proc/cmdline 2>/dev/null; then
  if [ -z "$WAYLAND_DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
    exec sh /etc/myos/session.sh
  fi
fi
