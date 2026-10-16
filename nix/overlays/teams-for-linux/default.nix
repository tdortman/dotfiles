_:

_:

prev: {
  # Local patch: upstream applies the auth-persistence helpers (msal cookie
  # keep-alive, expired-cookie cleanup) to Profile 0's session only, so a
  # second profile loses its MSAL tokens on every restart. Drop the overlay
  # once upstream binds them per profile view.
  teams-for-linux = prev.teams-for-linux.overrideAttrs (oldAttrs: {
    patches = (oldAttrs.patches or [ ]) ++ [
      ./persist-auth-state-per-profile-session.patch
    ];
  });
}
