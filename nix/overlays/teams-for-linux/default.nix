_:

_:

prev: {
  # Local patches while nixpkgs pins teams-for-linux 2.23.0. Drop the overlay
  # once nixpkgs ships a release containing upstream #3061.
  teams-for-linux = prev.teams-for-linux.overrideAttrs (oldAttrs: {
    patches = (oldAttrs.patches or [ ]) ++ [
      # Upstream #3061, closing #3057: profile views were created detached, and
      # on Electron 42.11+/43 a view that loads Teams while detached paints but
      # never takes input once attached. Views stay attached and switching
      # toggles setVisible().
      ./keep-profile-views-attached.patch

      # The auth-persistence helpers run for Profile 0's session only, so a
      # second profile loses its MSAL tokens on every restart.
      ./persist-auth-state-per-profile-session.patch
    ];
  });
}
