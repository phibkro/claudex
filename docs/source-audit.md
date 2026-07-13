# CLIProxyAPI source audit

Audit target: CLIProxyAPI `v7.2.72`, commit `6279bb8a4c2835ff6ed99c6b85083b2afbefa681`.

This was a targeted integration audit, not a complete security review.

## Reviewed surfaces

- `cmd/server/main.go`: flags, config loading, local-model mode, updater startup
- `config.example.yaml`: listener, management, plugins, logging, auth directory
- `internal/auth/codex/*`: OAuth exchange, refresh, token serialization
- `sdk/auth/codex*`: callback and device flows
- `internal/translator/codex/claude/*`: Codex-to-Anthropic responses
- `internal/translator/claude/openai/*`: Anthropic-to-OpenAI requests
- `internal/runtime/executor/*`: tool and reasoning handling
- embedded Codex model registry

## Findings and responses

### Default listener is unsafe for this use

Upstream's example config defaults `host` to an empty string, binding all interfaces.

**Response:** generated config always sets `host: "127.0.0.1"`.

### Management surface is unnecessary

The management API/control panel can mutate configuration and download UI assets.

**Response:** empty management secret disables the API; control panel and panel updater are disabled.

### Token mode follows umask

`internal/auth/codex/token.go` creates token files with `os.Create` rather than an explicit `0600` mode.

**Response:** login and service run with umask `0077`; initialization repairs directories to `0700` and files to `0600`.

### Local-model mode retained unrelated egress

`-local-model` skipped remote model catalogs but still called `StartAntigravityVersionUpdater`.

**Response:** the Nix derivation patches both calls to run only when `localModel` is false.

### Request visibility

The proxy necessarily receives complete model requests.

**Response:** request logging, file logging, usage statistics, management, and plugins are disabled. This does not remove runtime trust in the process.

### Credential identity appeared in operational logs

Session-affinity info logs and selected warning/error paths printed `auth.ID`, which is derived from the OAuth filename and can contain an account identifier.

**Response:** the Nix patch substitutes `auth.Provider` only at logging call sites; cache keys and credential selection continue using the unmodified ID. Model audits retain `auth=codex` evidence without exposing the backing filename.

### Deferred ToolSearch mismatch

Claude Code's custom-gateway ToolSearch requires `tool_reference` forwarding. The relevant translation was not present in the Codex translator.

**Response:** keep deferred ToolSearch disabled and expose explicit eager built-ins.

## Positive observations

- OAuth callback uses PKCE and state validation.
- Auth directories are created as `0700`.
- Model endpoints can require downstream API keys.
- A dedicated health endpoint exists.
- Embedded model catalogs support offline model discovery.
- Translation and OAuth logic have substantial unit-test coverage upstream.

## Update checklist

Do not bump the package mechanically. Re-run this audit against changed source and verify that every response above is still effective.
