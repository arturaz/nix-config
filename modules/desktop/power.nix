# Plasma power management: never sleep on its own while on AC power.
{
  # A system-wide default (like Plasma's own settings, read before ~/.config/powerdevilrc),
  # so it covers every user, new ones included. A user's own choice in System Settings >
  # Power Management overrides it.
  environment.etc."xdg/powerdevilrc".text = ''
    [AC][SuspendAndShutdown]
    AutoSuspendAction=0
  '';
}
