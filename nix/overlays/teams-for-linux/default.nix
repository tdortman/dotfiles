_:

_:

prev: {
  # Local patch: upstream cleans expired auth cookies from Profile 0's
  # session only, so a second profile can start with the stale "sign in
  # again" banner. Drop the patch once upstream cleans each profile view.
  teams-for-linux = prev.teams-for-linux.overrideAttrs (oldAttrs: {
    patches = (oldAttrs.patches or [ ]) ++ [
      ./clean-expired-auth-cookies-per-profile-session.patch
      # Local preference: with auth.reauthRecovery on, a stale session gets
      # Teams' ignorable "sign in again" banner (click = in-app recovery)
      # instead of an automatic reload into the account picker.
      ./no-silent-auth-recovery-reload.patch
    ];
  });
}
