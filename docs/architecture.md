# Architecture

## Purpose

ClaudeX separates the agent harness from the model provider. Claude Code remains responsible for interaction, context assembly, permissions, tools, agents, skills, hooks, MCP, and repository instructions. A local gateway translates only the model protocol.

```text
Claude Code harness
  ├─ CLAUDE.md and settings
  ├─ tools, agents, skills, hooks, MCP
  └─ Anthropic Messages + SSE
             │
             ▼
       CLIProxyAPI
  ├─ downstream bearer authentication
  ├─ Anthropic ↔ Codex translation
  ├─ streaming and tool calls
  └─ reasoning-state translation
             │
             ▼
     OpenAI Codex endpoint
       via ChatGPT OAuth
```

Claude Code is pointed at the gateway with `ANTHROPIC_BASE_URL` and `ANTHROPIC_AUTH_TOKEN`. Its ordinary configuration is not modified; the environment exists only inside the `claudex` launcher.

## Components

### Package

`packages/cliproxyapi.nix` builds a pinned CLIProxyAPI release from source with fixed source and Go-vendor hashes. It applies one narrow patch: `-local-model` also suppresses the unrelated Antigravity catalog refresher.

### Runtime initialization

`claudex-init` creates:

```text
~/.config/claudex/config.yaml
~/.local/state/claudex/api-key
~/.local/share/claudex/auth/
```

The config is regenerated from declared policy at each start. The random downstream API key and OAuth state persist.

### Service

`claudex.service` runs on demand as a hardened systemd user service. It listens only on `127.0.0.1`, and it has no install target, so enabling the module does not create an always-running daemon.

### Launcher

`claudex` initializes state, starts the service, waits for `/healthz`, exports gateway/model metadata, and execs Claude Code.

### Model aliases

Claude Code's Opus, Sonnet, and Haiku aliases are pinned to Sol, Terra, and Luna respectively. Friendly picker metadata and capability declarations prevent provider-specific IDs from losing Claude Code UI features.

### Tool compatibility

Claude Code disables deferred ToolSearch on non-Anthropic base URLs. CLIProxyAPI's Codex translator does not translate Anthropic `tool_reference` blocks, so enabling deferred search would be incorrect. ClaudeX instead passes an explicit eager built-in tool set to ordinary sessions. Maintenance subcommands and user-provided `--tools` arguments bypass this rewrite.

## Trust boundaries

- Claude Code controls local tool execution and permissions.
- CLIProxyAPI sees model requests and OAuth credentials.
- OpenAI receives translated prompts and tool transcripts.
- Nix pins executable source but does not make upstream behavior trusted.
- Journal model-selection records are stronger evidence than model self-identification.
