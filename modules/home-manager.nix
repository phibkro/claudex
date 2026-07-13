{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.claudex;
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
  baseUrl = "http://127.0.0.1:${toString cfg.port}";
  acceptancePrompt = ../docs/acceptance-prompt.md;
  modelType = lib.types.submodule {
    options = {
      id = lib.mkOption {
        type = lib.types.str;
        description = "Provider model identifier.";
      };
      name = lib.mkOption {
        type = lib.types.str;
        description = "Display name in Claude Code's model picker.";
      };
      description = lib.mkOption {
        type = lib.types.str;
        description = "Description in Claude Code's model picker.";
      };
      capabilities = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "effort"
          "xhigh_effort"
          "max_effort"
          "thinking"
          "adaptive_thinking"
          "interleaved_thinking"
        ];
        description = "Claude Code capabilities declared for the pinned model.";
      };
    };
  };

  /*
    Runtime state cannot live in the Nix store: it contains the downstream
    API key and Codex OAuth refresh token. Regenerate the declarative config
    on every start while preserving the randomly-created key.

    Upstream's Codex token writer uses os.Create (mode follows umask), so the
    explicit 0077 umask and repair chmod are load-bearing.
  */
  init = pkgs.writeShellApplication {
    name = "claudex-init";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
            umask 077

            config_dir="''${XDG_CONFIG_HOME:-$HOME/.config}/claudex"
            data_dir="''${XDG_DATA_HOME:-$HOME/.local/share}/claudex"
            state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/claudex"
            config="$config_dir/config.yaml"
            key_file="$state_dir/api-key"

            install -d -m 0700 "$config_dir" "$data_dir/auth" "$state_dir"

            if [ ! -s "$key_file" ]; then
              key=$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')
              printf '%s\n' "$key" > "$key_file"
            fi
            chmod 0600 "$key_file"
            key=$(tr -d '\n' < "$key_file")

            case "$key" in
              (*[!0-9a-f]*|"")
                echo "claudex-init: invalid API key in $key_file" >&2
                exit 1
                ;;
            esac

            tmp=$(mktemp "$config_dir/config.yaml.XXXXXX")
            trap 'rm -f "$tmp"' EXIT
            cat > "$tmp" <<EOF
      host: "127.0.0.1"
      port: ${toString cfg.port}
      tls:
        enable: false
      remote-management:
        allow-remote: false
        secret-key: ""
        disable-control-panel: true
        disable-auto-update-panel: true
      auth-dir: "$data_dir/auth"
      api-keys:
        - "$key"
      debug: false
      pprof:
        enable: false
      plugins:
        enabled: false
      logging-to-file: false
      request-log: false
      usage-statistics-enabled: false
      ws-auth: true
      request-retry: 2
      routing:
        strategy: "fill-first"
        session-affinity: true
      EOF
            chmod 0600 "$tmp"
            mv -f "$tmp" "$config"
            trap - EXIT

            find "$data_dir/auth" -type d -exec chmod 0700 {} +
            find "$data_dir/auth" -type f -exec chmod 0600 {} +
    '';
  };

  login = pkgs.writeShellApplication {
    name = "claudex-login";
    runtimeInputs = [
      init
      cfg.package
    ];
    text = ''
      umask 077
      claudex-init
      exec cliproxyapi \
        -config "''${XDG_CONFIG_HOME:-$HOME/.config}/claudex/config.yaml" \
        -local-model \
        -codex-login "$@"
    '';
  };

  status = pkgs.writeShellApplication {
    name = "claudex-status";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.systemd
    ];
    text = ''
      state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/claudex"
      key_file="$state_dir/api-key"

      systemctl --user --no-pager status claudex.service || true
      if [ -s "$key_file" ]; then
        curl --fail --silent --show-error \
          -H "Authorization: Bearer $(tr -d '\n' < "$key_file")" \
          ${baseUrl}/v1/models | ${pkgs.jq}/bin/jq -r '.data[]?.id' || true
      else
        echo "claudex-status: not initialized; run claudex-login" >&2
      fi
    '';
  };

  modelAudit = pkgs.writeShellApplication {
    name = "claudex-model-audit";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnused
      pkgs.systemd
    ];
    text = ''
      since="''${1:-15 minutes ago}"
      journalctl --user -u claudex.service --since "$since" --no-pager \
        | sed -nE 's/.*auth=codex-[^ ]+ provider=[^ ]+ model=([^ ]+).*/auth=codex-oauth model=\1/p' \
        | sort -u
    '';
  };

  launcher = pkgs.writeShellApplication {
    name = "claudex";
    runtimeInputs = [
      init
      pkgs.coreutils
      pkgs.curl
      pkgs.systemd
    ];
    text = ''
      claudex-init
      systemctl --user start claudex.service

      ready=false
      for _ in $(seq 1 50); do
        if curl --fail --silent ${baseUrl}/healthz >/dev/null; then
          ready=true
          break
        fi
        sleep 0.1
      done
      if [ "$ready" != true ]; then
        echo "claudex: proxy failed to become ready" >&2
        systemctl --user --no-pager status claudex.service >&2 || true
        exit 1
      fi

      key=$(tr -d '\n' < "''${XDG_STATE_HOME:-$HOME/.local/state}/claudex/api-key")
      opus=${lib.escapeShellArg cfg.models.opus.id}
      sonnet=${lib.escapeShellArg cfg.models.sonnet.id}
      haiku=${lib.escapeShellArg cfg.models.haiku.id}
      model="''${CLAUDEX_MODEL:-$opus}"

      unset ANTHROPIC_API_KEY
      export ANTHROPIC_BASE_URL=${baseUrl}
      export ANTHROPIC_AUTH_TOKEN="$key"
      export ANTHROPIC_MODEL="$model"

      export ANTHROPIC_DEFAULT_OPUS_MODEL="$opus"
      export ANTHROPIC_DEFAULT_OPUS_MODEL_NAME=${lib.escapeShellArg cfg.models.opus.name}
      export ANTHROPIC_DEFAULT_OPUS_MODEL_DESCRIPTION=${lib.escapeShellArg cfg.models.opus.description}
      export ANTHROPIC_DEFAULT_OPUS_MODEL_SUPPORTED_CAPABILITIES=${lib.escapeShellArg (lib.concatStringsSep "," cfg.models.opus.capabilities)}

      export ANTHROPIC_DEFAULT_SONNET_MODEL="$sonnet"
      export ANTHROPIC_DEFAULT_SONNET_MODEL_NAME=${lib.escapeShellArg cfg.models.sonnet.name}
      export ANTHROPIC_DEFAULT_SONNET_MODEL_DESCRIPTION=${lib.escapeShellArg cfg.models.sonnet.description}
      export ANTHROPIC_DEFAULT_SONNET_MODEL_SUPPORTED_CAPABILITIES=${lib.escapeShellArg (lib.concatStringsSep "," cfg.models.sonnet.capabilities)}

      export ANTHROPIC_DEFAULT_HAIKU_MODEL="$haiku"
      export ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME=${lib.escapeShellArg cfg.models.haiku.name}
      export ANTHROPIC_DEFAULT_HAIKU_MODEL_DESCRIPTION=${lib.escapeShellArg cfg.models.haiku.description}
      export ANTHROPIC_DEFAULT_HAIKU_MODEL_SUPPORTED_CAPABILITIES=${lib.escapeShellArg (lib.concatStringsSep "," cfg.models.haiku.capabilities)}
      export ANTHROPIC_SMALL_FAST_MODEL="$haiku"

      # Claude Code disables deferred ToolSearch for custom gateways. The
      # Codex translator does not carry Anthropic tool_reference blocks, so
      # expose built-ins eagerly for ordinary sessions instead.
      eager_tools=${lib.escapeShellArg (lib.concatStringsSep "," cfg.eagerTools)}
      case "''${1:-}" in
        agents|auth|auto-mode|doctor|install|mcp|migrate|plugin|remote-control|setup-token|skill|telemetry|update|ultrareview|upgrade)
          exec ${lib.escapeShellArg cfg.claudeCommand} "$@"
          ;;
      esac
      for arg in "$@"; do
        case "$arg" in
          --tools|--tools=*) exec ${lib.escapeShellArg cfg.claudeCommand} "$@" ;;
        esac
      done
      exec ${lib.escapeShellArg cfg.claudeCommand} "$@" --tools "$eager_tools"
    '';
  };

  acceptance = pkgs.writeShellApplication {
    name = "claudex-acceptance";
    runtimeInputs = [
      launcher
      pkgs.gawk
    ];
    text = ''
      prompt=$(awk '
        BEGIN { section = 0 }
        /^## Prompt$/ { section = 1; next }
        section && /^```text$/ { capture = 1; next }
        capture && /^```$/ { exit }
        capture { print }
      ' ${acceptancePrompt})
      exec claudex --print "$prompt"
    '';
  };
in
{
  options.programs.claudex = {
    enable = lib.mkEnableOption "ClaudeX, an OpenAI Codex gateway for Claude Code";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../packages/cliproxyapi.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ../packages/cliproxyapi.nix { }";
      description = "CLIProxyAPI package used by the gateway.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8317;
      description = "Loopback port for the Anthropic-compatible gateway.";
    };

    claudeCommand = lib.mkOption {
      type = lib.types.str;
      default = "claude";
      description = "Claude Code executable invoked by the launcher.";
    };

    installAcceptancePrompt = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install the acceptance prompt under ~/.claude.";
    };

    models = {
      opus = lib.mkOption {
        type = modelType;
        default = {
          id = "gpt-5.6-sol";
          name = "GPT-5.6 Sol";
          description = "Frontier OpenAI agentic coding model (Opus tier)";
        };
      };
      sonnet = lib.mkOption {
        type = modelType;
        default = {
          id = "gpt-5.6-terra";
          name = "GPT-5.6 Terra";
          description = "Balanced OpenAI agentic coding model (Sonnet tier)";
        };
      };
      haiku = lib.mkOption {
        type = modelType;
        default = {
          id = "gpt-5.6-luna";
          name = "GPT-5.6 Luna";
          description = "Fast OpenAI agentic coding model (Haiku tier)";
        };
      };
    };

    eagerTools = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "Bash"
        "Read"
        "Edit"
        "Write"
        "Glob"
        "Grep"
        "Agent"
        "Task"
        "WebFetch"
        "WebSearch"
        "Skill"
        "AskUserQuestion"
        "NotebookEdit"
        "TodoWrite"
        "EnterPlanMode"
        "ExitPlanMode"
        "TaskCreate"
        "TaskGet"
        "TaskUpdate"
        "TaskList"
      ];
      description = "Built-in tools exposed eagerly because deferred ToolSearch is unavailable through this gateway.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = isLinux;
        message = "programs.claudex currently requires Linux systemd user services";
      }
    ];

    home.packages = [
      cfg.package
      init
      login
      status
      modelAudit
      launcher
      acceptance
    ];

    home.file.".claude/CLAUDEX_ACCEPTANCE.md" = lib.mkIf cfg.installAcceptancePrompt {
      source = acceptancePrompt;
    };

    systemd.user.services.claudex = lib.mkIf isLinux {
      Unit = {
        Description = "ClaudeX loopback Codex-to-Anthropic protocol proxy";
        After = [ "network-online.target" ];
        Wants = [ "network-online.target" ];
      };
      Service = {
        Type = "simple";
        ExecStartPre = "${init}/bin/claudex-init";
        ExecStart = "${cfg.package}/bin/cliproxyapi -config %h/.config/claudex/config.yaml -local-model";
        Restart = "on-failure";
        RestartSec = "2s";
        UMask = "0077";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        ReadWritePaths = [
          "%h/.config/claudex"
          "%h/.local/share/claudex"
          "%h/.local/state/claudex"
        ];
        ProtectControlGroups = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
        ];
      };
    };
  };
}
