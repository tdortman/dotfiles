{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.jgu-vpn;
  dnsTarget = if cfg.dnsServers != [ ] then "${builtins.head cfg.dnsServers}:53" else "127.0.0.53:53";
  haricaCa = ./HARICA-TLS-Root-2021-RSA.pem;

  jguVpnRun = pkgs.writeShellApplication {
    name = "jgu-vpn-run";

    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
      iproute2
      strongswan
      util-linux
    ];

    text = ''
      if ! ip link show "${cfg.interface}" >/dev/null 2>&1; then
        echo "[jgu-vpn-run] XFRM interface ${cfg.interface} not found. Is strongSwan running?" >&2
        exit 1
      fi

      xfrm_ready() {
        ip xfrm state 2>/dev/null | grep -iE "if_id[[:space:]]+${xfrmIdPattern}([[:space:]]|$)" >/dev/null \
          && ip xfrm policy 2>/dev/null | grep -iE "if_id[[:space:]]+${xfrmIdPattern}([[:space:]]|$)" >/dev/null
      }

      if ! xfrm_ready; then
        echo "[jgu-vpn-run] XFRM state and policy for if_id ${toString cfg.ifId} are not ready. Initiating jgu-child." >&2
        if ! timeout 10s swanctl --initiate --ike jgu --child jgu-child; then
          echo "[jgu-vpn-run] swanctl initiation failed or timed out. Waiting for recovery." >&2
        fi

        ready=0
        for attempt in $(seq 1 10); do
          if xfrm_ready; then
            ready=1
            break
          fi
          echo "[jgu-vpn-run] Waiting for XFRM state and policy, attempt ''${attempt}/10." >&2
          sleep 1
        done
        if [ "''${ready}" -ne 1 ]; then
          echo "[jgu-vpn-run] XFRM CHILD SA for if_id ${toString cfg.ifId} is unavailable. Refusing to create VPN namespace." >&2
          exit 1
        fi
      fi

      export VPN_RUN_HOST_DNS_TARGET="${dnsTarget}"

      exec vpn-run -i ${cfg.interface} -n jgu-vpn-ns "$@"
    '';
  };
  xfrmIdPattern = "(${toString cfg.ifId}|0x${lib.toHexString cfg.ifId})";
in
{
  options.jgu-vpn = {
    enable = lib.mkEnableOption "JGU campus VPN (strongSwan IKEv2 via XFRM interface, bridged to a veth-isolated netns by vpn-run)";

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Bring up the IKE/CHILD SA on boot (start_action = start).";
    };

    dnsServers = lib.mkOption {
      type = lib.types.listOf lib.types.str;

      example = [
        "134.93.144.2"
        "134.93.144.3"
      ];

      default = [ ];

      description = ''
        JGU DNS servers. The first one is used as the DNS target for
        commands run through the VPN namespace. Leave empty to use the
        host's stub resolver (127.0.0.53) instead.
      '';
    };

    gateway = lib.mkOption {
      type = lib.types.str;
      default = "vpn.uni-mainz.de";
      description = "JGU VPN gateway (ZDV).";
    };

    ifId = lib.mkOption {
      type = lib.types.int;
      default = 42;
      description = "XFRM interface ID; must match strongSwan child if_id_in/out.";
    };

    interface = lib.mkOption {
      type = lib.types.str;
      default = "jgu0";
      description = "XFRM interface name (must match strongSwan if_id).";
    };

    secretsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      example = "/run/agenix/jgu-vpn-swanctl";
      default = null;

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

    shellAlias = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Create a shell alias for jgu-vpn-run.";
    };

    username = lib.mkOption {
      type = lib.types.str;
      example = "jdoe@uni-mainz.de";
      description = "EAP identity (usually user@uni-mainz.de).";
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

    environment = {
      etc = {
        "ssl/certs/HARICA_TLS_RSA_Root_CA_2021.pem".source = haricaCa;
        "swanctl/x509ca/HARICA-TLS-RSA-Root-CA-2021.pem".source = haricaCa;
      };

      shellAliases = lib.mkIf cfg.shellAlias {
        jgu-vpn-run = "sudo -E jgu-vpn-run";
      };

      systemPackages = [ jguVpnRun ];
    };

    security.sudo.extraRules = lib.optionals (config.vpn-run.allowedUsers != [ ]) [
      {
        commands = [
          {
            options = [
              "NOPASSWD"
              "SETENV"
            ];

            command = "${jguVpnRun}/bin/jgu-vpn-run";
          }
          {
            options = [
              "NOPASSWD"
              "SETENV"
            ];

            command = "/run/current-system/sw/bin/jgu-vpn-run";
          }
        ];

        users = config.vpn-run.allowedUsers;
      }
    ];

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
        children.jgu-child = {
          dpd_action = "restart";

          esp_proposals = [
            "aes256-sha1"
            "aes256-sha256"
            "aes256-sha256-ecp256"
            "aes256-sha384"
          ];

          if_id_in = toString cfg.ifId;
          if_id_out = toString cfg.ifId;
          local_ts = [ "0.0.0.0/0" ];
          remote_ts = [ "0.0.0.0/0" ];
          start_action = if cfg.autoStart then "start" else "trap";
        };

        dpd_delay = "30s";
        dpd_timeout = "150s";
        keyingtries = 0;

        local.jgu-local = {
          auth = "eap";
          eap_id = cfg.username;
          id = cfg.username;
        };

        local_addrs = [ "%any" ];
        mobike = true;

        proposals = [
          "aes256-sha1-modp2048"
          "aes256-sha256-modp2048"
          "aes256-sha384-modp2048"
        ];

        remote.jgu-remote = {
          auth = "pubkey";
          cacerts = [ "HARICA-TLS-RSA-Root-CA-2021.pem" ];
        };

        remote_addrs = [ cfg.gateway ];
        version = 2;

        vips = [
          "0.0.0.0"
          "::"
        ];
      };
    };

    systemd.services = {
      jgu-vpn-xfrm = {
        description = "Create JGU VPN XFRM interface ${cfg.interface}";
        before = [ "strongswan-swanctl.service" ];
        wantedBy = [ "multi-user.target" ];

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

        path = [ pkgs.iproute2 ];
      };

      strongswan-swanctl = {
        after = lib.mkAfter [ "jgu-vpn-xfrm.service" ];
        wants = [ "jgu-vpn-xfrm.service" ];
      };
    };
  };
}
