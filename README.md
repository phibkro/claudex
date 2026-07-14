# ClaudeX

Run OpenAI Codex models inside the Claude Code harness.

ClaudeX keeps Claude Code's terminal UI, repository instructions, agents, skills, hooks, permissions, web tools, and MCP integration while routing model requests through a local Anthropic-compatible gateway to ChatGPT/Codex OAuth.

```text
Claude Code
    │  Anthropic Messages API
    ▼
CLIProxyAPI on 127.0.0.1
    │  OpenAI Codex protocol
    ▼
ChatGPT/Codex OAuth
```

> [!WARNING]
> This is an independent compatibility project, not an Anthropic or OpenAI product. Using subscription OAuth outside the vendor's own client may carry account-policy risk. The local proxy can see prompts, source excerpts, and tool results. Read [the security document](docs/security.md) before enabling it.

## Features

- Declarative Nix package pinned to CLIProxyAPI 7.2.72
- Reusable Home Manager module
- Loopback-only authenticated gateway
- Private OAuth and downstream-key storage
- Hardened on-demand systemd user service
- Claude model aliases mapped to the GPT-5.6 family
- Eager built-in tools for custom-gateway compatibility
- Read-only acceptance test with external model evidence
- Ordinary `claude` command remains unchanged

## Model mapping

| Claude selector | OpenAI model | Role |
|---|---|---|
| Opus | `gpt-5.6-sol` | Frontier |
| Sonnet | `gpt-5.6-terra` | Balanced |
| Haiku | `gpt-5.6-luna` | Fast/affordable |

## Installation

Add the flake input:

```nix
{
  inputs.claudex.url = "github:phibkro/claudex";
  inputs.claudex.inputs.nixpkgs.follows = "nixpkgs";
}
```

Import and enable the Home Manager module:

```nix
{ inputs, ... }:
{
  imports = [ inputs.claudex.homeManagerModules.default ];
  programs.claudex.enable = true;
}
```

Claude Code must already be available as `claude`. Override `programs.claudex.claudeCommand` if it lives elsewhere.

Apply your Home Manager or NixOS configuration, then authenticate once:

```bash
claudex-login
```

## Usage

```bash
claudex                       # Claude Code with GPT-5.6 Sol by default
claudex-status                # service state, models, and recent-failure hint
claudex-doctor                # transport/auth checks + recent HTTP outcome counts
claudex-doctor --probe        # also make one minimal request per model tier
claudex-recover               # restart stale cooldown state and probe all tiers
claudex-model-audit           # externally verify models used recently
claudex-acceptance            # complete read-only harness test
systemctl --user stop claudex # stop the on-demand proxy
```

Choose another startup model without changing picker aliases:

```bash
CLAUDEX_MODEL=gpt-5.6-terra claudex
```

Normal `claude` continues to use its ordinary Anthropic configuration.

ClaudeX defaults Claude Code's output ceiling to 128,000 tokens, matching the
catalogued maximum completion size of the default OpenAI models. Override it for
one session when a smaller budget is preferable:

```bash
CLAUDE_CODE_MAX_OUTPUT_TOKENS=64000 claudex
```

The model's 372,000-token context window includes both input and output. A large
ceiling permits long compaction summaries but does not require responses to use
that budget.

ClaudeX disables Claude Code's dynamic workflows, including bundled
`deep-research`, because their recursive fan-out and independent retries can
overwhelm Codex request limits. Ordinary agents, hooks, skills, MCP servers, and
parallel tool calls remain available. Claude.ai connectors and Remote Control
are also disabled because they require Anthropic account services rather than
the local Codex gateway. These restrictions apply only to `claudex`; ordinary
`claude` sessions are unchanged.

## Quota and plan-change recovery

A healthy `/healthz` or model list proves transport readiness, not generation
readiness. After exhausting usage or changing OpenAI plans, upstream entitlement
may recover while CLIProxyAPI still holds a per-model cooldown in memory.

```bash
claudex-recover
```

This restarts only the user proxy, checks the loopback/auth boundaries, and makes
a minimal request through Opus/Sonnet/Haiku. If it reports `401` or `403`, renew
OAuth with `claudex-login`. If it reports `429`, wait for quota or plan propagation
and rerun recovery. `claudex-doctor --since "2 hours ago"` reports recent 401,
403, 429, and 500 counts without printing prompts, tokens, or account identifiers.

## Configuration

```nix
programs.claudex = {
  enable = true;
  port = 8317;
  maxOutputTokens = 128000;
  models.opus.id = "gpt-5.6-sol";
  models.sonnet.id = "gpt-5.6-terra";
  models.haiku.id = "gpt-5.6-luna";
};
```

See `modules/home-manager.nix` for all options.

## Evidence

Provider identity is never accepted from model prose. The proxy journal is the external referent:

```bash
claudex-model-audit "30 minutes ago"
```

A successful three-tier run produces:

```text
auth=codex-oauth model=gpt-5.6-luna
auth=codex-oauth model=gpt-5.6-sol
auth=codex-oauth model=gpt-5.6-terra
```

The original implementation's full acceptance record is in [validation-2026-07-13.md](docs/validation-2026-07-13.md).

## Documentation

- [Architecture](docs/architecture.md)
- [Security](docs/security.md)
- [Research and sources](docs/research.md)
- [Codex ↔ Claude Code capability matrix](docs/capability-compatibility.md)
- [Source audit](docs/source-audit.md)
- [Acceptance prompt](docs/acceptance-prompt.md)
- [Recovery validation](docs/validation-2026-07-13-recovery.md)
- [Original implementation report](docs/implementation-report.md)

## License

ClaudeX's Nix integration and documentation are MIT licensed. CLIProxyAPI is a separately maintained MIT-licensed upstream dependency; this repository pins and patches its source during the Nix build.
