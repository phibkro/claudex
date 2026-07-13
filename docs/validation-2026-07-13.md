# Validation record: 2026-07-13

The original deployment was tested on NixOS with Claude Code 2.1.197 and CLIProxyAPI 7.2.72.

## Build and configuration gates

- Pinned Go package built from source.
- Home Manager generation built.
- Homelab's complete flake gate passed, including format, lint, host evaluation, and VM checks.
- Generated shell applications passed Home Manager's shell checks.

## Local boundary

Observed modes:

```text
config.yaml 600
api-key     600
auth dir    700
OAuth JSON  600
```

Observed listener:

```text
127.0.0.1:8317
```

HTTP behavior:

```text
GET /healthz                  200
GET /v1/models, no key       401
GET /v1/models, bearer key   200
```

## OAuth and end-to-end request

The browser PKCE flow completed successfully and wrote one Codex OAuth credential. A non-interactive Claude Code request returned the exact requested marker:

```text
CLAUDEX_OK
```

The proxy recorded:

```text
provider=mixed model=gpt-5.6-sol
POST /v1/messages?beta=true 200
```

## Alias probes

Each Claude alias was invoked independently:

```text
OPUS_DIRECT_OK
SONNET_DIRECT_OK
HAIKU_DIRECT_OK
```

External journal audit:

```text
auth=codex-oauth model=gpt-5.6-luna
auth=codex-oauth model=gpt-5.6-sol
auth=codex-oauth model=gpt-5.6-terra
```

This journal output, not the markers, establishes provider route and model IDs.

## Harness acceptance

The acceptance prompt exercised the following without writes:

| Feature | Result |
|---|---|
| Read | PASS |
| Glob | PASS |
| Grep | PASS |
| Bash | PASS |
| WebSearch | PASS |
| Agent/subagents | PASS |
| Skill visibility | PASS |
| fetch MCP | PASS |
| context7 MCP | PASS |
| Opus/Sonnet/Haiku aliases | PASS |

A configured-but-absent tilth server was correctly reported as SKIP rather than PASS.

## Finding during validation

The first full run found that Claude Code hid Glob and Grep because deferred ToolSearch is disabled for custom gateways. Explicitly requesting those tools proved the proxy path worked. The launcher was changed to expose the complete built-in set eagerly, after which the full acceptance run passed.
