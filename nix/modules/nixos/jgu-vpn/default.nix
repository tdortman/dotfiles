{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.jgu-vpn;
  haricaCa = ./HARICA-TLS-Root-2021-RSA.pem;

  dnsTarget = if cfg.dnsServers != [ ] then "${builtins.head cfg.dnsServers}:53" else "127.0.0.53:53";

  jguVpnRun = pkgs.writeShellApplication {
    name = "jgu-vpn-run";
    runtimeInputs = with pkgs; [
      coreutils
      iproute2
      util-linux
    ];
    text = ''
      if ! ip link show "${cfg.interface}" >/dev/null 2>&1; then
        echo "[jgu-vpn-run] XFRM interface ${cfg.interface} not found — is strongSwan running?" >&2
        exit 1
      fi

      export VPN_RUN_HOST_DNS_TARGET="${dnsTarget}"

      exec unshare -m /bin/sh -c "
        mount -t tmpfs tmpfs /run/nscd 2>/dev/null || true
        exec vpn-run -i ${cfg.interface} -n jgu-vpn-ns \"\$@\"
      " _ "$@"
    '';
  };
in
{
  options.jgu-vpn = {
    enable = lib.mkEnableOption "JGU campus VPN (strongSwan IKEv2 via XFRM interface, bridged to a veth-isolated netns by vpn-run)";

    interface = lib.mkOption {
      type = lib.types.str;
      default = "jgu0";
      description = "XFRM interface name (must match strongSwan if_id).";
    };

    shellAlias = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Create a shell alias for jgu-vpn-run.";
    };

    ifId = lib.mkOption {
      type = lib.types.int;
      default = 42;
      description = "XFRM interface ID; must match strongSwan child if_id_in/out.";
    };

    gateway = lib.mkOption {
      type = lib.types.str;
      default = "vpn.uni-mainz.de";
      description = "JGU VPN gateway (ZDV).";
    };

    username = lib.mkOption {
      type = lib.types.str;
      description = "EAP identity (usually user@uni-mainz.de).";
      example = "jdoe@uni-mainz.de";
    };

    secretsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/run/agenix/jgu-vpn-swanctl";
      description = ''
        swanctl secrets snippet (outside the nix store) with an `eap-*` block, e.g.:

        ```
        secrets {
          eap-jgu {
            id = user@uni-mainz.de
            secret = "your-password"
          }
        }
        ```
      '';
    };

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Bring up the IKE/CHILD SA on boot (start_action = start).";
    };

    dnsServers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "134.93.144.2"
        "134.93.144.3"
      ];
      description = ''
        JGU DNS servers. The first one is used as the DNS target for
        commands run through the VPN namespace. Leave empty to use the
        host's stub resolver (127.0.0.53) instead.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.username != "";
        message = "jgu-vpn.username must be set (e.g. \"\${user}@uni-mainz.de\")";
      }
      {
        assertion = cfg.secretsFile != null;
        message = "jgu-vpn.secretsFile must point to a swanctl secrets file (use agenix)";
      }
      {
        assertion = config.vpn-run.enable;
        message = "jgu-vpn requires vpn-run to be enabled (it reuses its veth/netns infrastructure)";
      }
    ];

    environment.systemPackages = [ jguVpnRun ];

    environment.etc = {
      "ssl/certs/HARICA_TLS_RSA_Root_CA_2021.pem".source = haricaCa;
      "swanctl/x509ca/HARICA-TLS-RSA-Root-CA-2021.pem".source = haricaCa;
    };

    systemd.services.jgu-vpn-xfrm = {
      description = "Create JGU VPN XFRM interface ${cfg.interface}";
      wantedBy = [ "multi-user.target" ];
      before = [ "strongswan-swanctl.service" ];
      path = [ pkgs.iproute2 ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        if ! ip link show "${cfg.interface}" >/dev/null 2>&1; then
          ip link add "${cfg.interface}" type xfrm if_id ${toString cfg.ifId}
        fi
        ip link set "${cfg.interface}" up
      '';
    };

    services.strongswan-swanctl = {
      enable = true;

      includes = lib.optional (cfg.secretsFile != null) cfg.secretsFile;

      strongswan.extraConfig = ''
        charon {
          install_virtual_ip_on = ${cfg.interface}
          make_before_break = yes
          close_ike_on_child_failure = no
          plugins {
            eap-peap {
              load = no
            }
          }
        }
      '';

      swanctl.connections.jgu = {
        version = 2;
        local_addrs = [ "%any" ];
        mobike = true;
        dpd_delay = "30s";
        dpd_timeout = "150s";
        remote_addrs = [ cfg.gateway ];

        proposals = [
          "aes256-sha1-modp2048"
          "aes256-sha256-modp2048"
          "aes256-sha384-modp2048"
        ];

        vips = [
          "0.0.0.0"
          "::"
        ];

        local.jgu-local = {
          auth = "eap";
          id = cfg.username;
          eap_id = cfg.username;
        };

        remote.jgu-remote = {
          auth = "pubkey";
          cacerts = [ "HARICA-TLS-RSA-Root-CA-2021.pem" ];
        };

        children.jgu-child = {
          if_id_in = toString cfg.ifId;
          if_id_out = toString cfg.ifId;
          start_action = if cfg.autoStart then "start" else "trap";
          esp_proposals = [
            "aes256-sha1"
            "aes256-sha256"
            "aes256-sha256-ecp256"
            "aes256-sha384"
          ];
          local_ts = [ "0.0.0.0/0" ];
          remote_ts = [ "0.0.0.0/0" ];
        };
      };
    };

    systemd.services.strongswan-swanctl = {
      after = lib.mkAfter [ "jgu-vpn-xfrm.service" ];
      wants = [ "jgu-vpn-xfrm.service" ];
    };

    environment.shellAliases = lib.mkIf cfg.shellAlias {
      jgu-vpn-run = "sudo -E jgu-vpn-run";
    };

    security.sudo.extraRules = lib.optionals (config.vpn-run.allowedUsers != [ ]) [
      {
        users = config.vpn-run.allowedUsers;
        commands = [
          {
            command = "${jguVpnRun}/bin/jgu-vpn-run";
            options = [
              "NOPASSWD"
              "SETENV"
            ];
          }
          {
            command = "/run/current-system/sw/bin/jgu-vpn-run";
            options = [
              "NOPASSWD"
              "SETENV"
            ];
          }
        ];
      }
    ];
  };
}
