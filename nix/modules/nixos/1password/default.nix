{
  config,
  lib,
  ...
}:

let
  cfg = config.onepassword;
in
{
  options.onepassword = {
    enable = lib.mkEnableOption "1Password and SSH agent integration";

    user = lib.mkOption {
      type = lib.types.str;
      description = "User to grant polkit permissions for 1Password";
    };
  };

  config = lib.mkIf cfg.enable {
    environment = {
      etc = {
        "1password/custom_allowed_browsers" = {
          mode = "0755";

          text = ''
            librewolf
            librewolf-bin
            .librewolf-wrapped
            .librewolf-wrap
          '';
        };

        "xdg/autostart/1password.desktop".text = ''
          [Desktop Entry]
          Type=Application
          Name=1Password
          Exec=1password --silent
          Hidden=false
          NoDisplay=false
          X-GNOME-Autostart-enabled=true
        '';
      };

      sessionVariables.SSH_AUTH_SOCK = "$HOME/.1password/agent.sock";
    };

    programs = {
      _1password.enable = true;

      _1password-gui = {
        enable = true;
        polkitPolicyOwners = [ cfg.user ];
      };
    };

    security.polkit = {
      enable = true;

      # Idk if this is really worth it
      extraConfig = ''
        polkit.addRule(function(action, subject) {
          if (
            (
              action.id == "com.1password.1Password.unlock" ||
              action.id == "com.1password.1Password.authorizeSshAgent"
            ) &&
            subject.user == "${cfg.user}"
          ) {
            return polkit.Result.YES;
          }
        });
      '';
    };
  };
}
