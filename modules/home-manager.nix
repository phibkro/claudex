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
      pkgs.gnugrep
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

      if journalctl --user -u claudex.service --since "15 minutes ago" --no-pager -o cat \
          | grep -Eq '] (429|500) \\|'; then
        echo >&2
        echo "claudex-status: recent generation failures detected; run claudex-doctor" >&2
      fi
    '';
  };

  doctor = pkgs.writeShellApplication {
    name = "claudex-doctor";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.gnugrep
      pkgs.gnused
      pkgs.iproute2
      pkgs.jq
      pkgs.systemd
    ];
    text = ''
      umask 077
      probe=false
      since="30 minutes ago"
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --probe) probe=true; shift ;;
          --since)
            if [ "$#" -lt 2 ]; then
              echo "claudex-doctor: --since requires a value" >&2
              exit 2
            fi
            since=$2
            shift 2
            ;;
          -h|--help)
            echo "usage: claudex-doctor [--probe] [--since TIME]"
            echo "  --probe  make one minimal generation request per configured tier"
            exit 0
            ;;
          *) echo "claudex-doctor: unknown argument: $1" >&2; exit 2 ;;
        esac
      done

      state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/claudex"
      key_file="$state_dir/api-key"
      fail=0

      if systemctl --user is-active --quiet claudex.service; then
        echo "service=PASS active"
      else
        echo "service=FAIL inactive"
        fail=1
      fi

      listeners=$(ss -H -ltn 'sport = :${toString cfg.port}' || true)
      if printf '%s\n' "$listeners" | grep -q '127.0.0.1:${toString cfg.port}' \
          && ! printf '%s\n' "$listeners" | grep -Eq '0.0.0.0:${toString cfg.port}|\[::\]:${toString cfg.port}'; then
        echo "listener=PASS loopback-only"
      else
        echo "listener=FAIL expected only 127.0.0.1:${toString cfg.port}"
        fail=1
      fi

      health_code=$(curl --silent --output /dev/null --write-out '%{http_code}' \
        --max-time 5 ${baseUrl}/healthz || true)
      if [ "$health_code" = 200 ]; then
        echo "transport=PASS healthz=200"
      else
        echo "transport=FAIL healthz=$health_code"
        fail=1
      fi

      unauth_code=$(curl --silent --output /dev/null --write-out '%{http_code}' \
        --max-time 5 ${baseUrl}/v1/models || true)
      if [ "$unauth_code" = 401 ]; then
        echo "downstream-auth=PASS unauthenticated=401"
      else
        echo "downstream-auth=FAIL unauthenticated=$unauth_code"
        fail=1
      fi

      if [ -s "$key_file" ]; then
        key=$(tr -d '\n' < "$key_file")
        auth_code=$(curl --silent --output /dev/null --write-out '%{http_code}' \
          --max-time 5 -H "Authorization: Bearer $key" ${baseUrl}/v1/models || true)
      else
        key=""
        auth_code="missing-key"
      fi
      if [ "$auth_code" = 200 ]; then
        echo "credential-routing=PASS authenticated-models=200"
      else
        echo "credential-routing=FAIL authenticated-models=$auth_code"
        fail=1
      fi

      logs=$(mktemp)
      trap 'rm -f "$logs"' EXIT
      journalctl --user -u claudex.service --since "$since" --no-pager -o cat > "$logs" || true
      for code in 401 403 429 500; do
        count=$(grep -E "] $code \\|" "$logs" \
          | grep -Ec 'POST +"/v1/messages' || true)
        echo "generation-journal-$code=$count since=$since"
      done

      probe_model() {
        tier=$1
        model=$2
        body=$(mktemp)
        payload=$(jq -nc --arg model "$model" '{model:$model,max_tokens:8,messages:[{role:"user",content:"Reply OK."}]}')
        code=$(curl --silent --output "$body" --write-out '%{http_code}' \
          --max-time 90 \
          -H "Authorization: Bearer $key" \
          -H 'content-type: application/json' \
          -H 'anthropic-version: 2023-06-01' \
          -X POST ${baseUrl}/v1/messages --data "$payload" || true)
        if [ "$code" = 200 ] && jq -e '.type == "message"' "$body" >/dev/null 2>&1; then
          echo "generation-$tier=PASS model=$model http=200"
        else
          error_type=$(jq -r '.error.type // "transport_error"' "$body" 2>/dev/null || echo transport_error)
          raw_message=$(jq -r '.error.message // "no structured error"' "$body" 2>/dev/null || echo "no structured error")
          error_message=$(printf '%s\n' "$raw_message" \
            | sed -E 's/[[:alnum:]._%+-]+@[[:alnum:].-]+\.[[:alpha:]]{2,}/<redacted-email>/g' \
            | cut -c1-240)
          echo "generation-$tier=FAIL model=$model http=$code type=$error_type message=$error_message"
          fail=1
        fi
        rm -f "$body"
      }

      if [ "$probe" = true ]; then
        if [ -z "$key" ]; then
          echo "generation=SKIP missing downstream key"
          fail=1
        else
          probe_model opus ${lib.escapeShellArg cfg.models.opus.id}
          probe_model sonnet ${lib.escapeShellArg cfg.models.sonnet.id}
          probe_model haiku ${lib.escapeShellArg cfg.models.haiku.id}
        fi
      else
        echo "generation=NOT_PROBED run: claudex-doctor --probe"
      fi

      exit "$fail"
    '';
  };

  recover = pkgs.writeShellApplication {
    name = "claudex-recover";
    runtimeInputs = [
      doctor
      pkgs.coreutils
      pkgs.curl
      pkgs.systemd
    ];
    text = ''
      echo "claudex-recover: restarting proxy to clear stale provider cooldowns"
      systemctl --user restart claudex.service
      ready=false
      for _ in $(seq 1 50); do
        if curl --fail --silent ${baseUrl}/healthz >/dev/null; then
          ready=true
          break
        fi
        sleep 0.1
      done
      if [ "$ready" != true ]; then
        echo "claudex-recover: proxy failed to restart" >&2
        systemctl --user --no-pager status claudex.service >&2 || true
        exit 1
      fi
      if ! claudex-doctor --probe "$@"; then
        echo >&2
        echo "claudex-recover: recovery probe failed" >&2
        echo "  401/403: run claudex-login" >&2
        echo "  429: wait for quota/plan propagation, then rerun claudex-recover" >&2
        exit 1
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
        | sed -nE 's/.*auth=codex provider=[^ ]+ model=([^ ]+).*/auth=codex-oauth model=\1/p' \
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
      doctor
      recover
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
