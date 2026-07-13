# Security

## Threat model

The local gateway receives every prompt, source excerpt, image, tool declaration, and tool result sent to the model. It also stores a refresh token capable of using the authenticated Codex account. Treat it as sensitive infrastructure, not a harmless format converter.

ClaudeX reduces exposure; it does not eliminate the trust placed in CLIProxyAPI or the provider.

## Enforced controls

- Server binds only to `127.0.0.1`.
- Every model endpoint requires a random per-user bearer key.
- The management API and control panel are disabled.
- Plugins are disabled.
- Request-body logging and usage statistics are disabled.
- Remote model-catalog updates are disabled.
- The unrelated Antigravity updater is patched out in local-model mode.
- Info/warning route logs emit the provider type rather than credential IDs derived from OAuth filenames.
- Diagnostic error messages redact email-shaped strings before printing.
- The service starts only when `claudex` is used.
- `ANTHROPIC_API_KEY` is removed from the launched environment so it cannot bypass the gateway token.

## Filesystem controls

Expected modes:

```text
0600 ~/.config/claudex/config.yaml
0600 ~/.local/state/claudex/api-key
0700 ~/.local/share/claudex/auth
0600 ~/.local/share/claudex/auth/*.json
```

The service and login flow run with umask `0077`. Startup also repairs auth-directory modes because upstream's Codex token writer uses `os.Create`, whose resulting mode otherwise depends on the caller's umask.

## Systemd sandbox

The user service enables:

- `NoNewPrivileges`
- `PrivateTmp`
- `ProtectSystem=strict`
- `ProtectHome=read-only`
- explicit writable state directories
- `ProtectControlGroups`
- `ProtectKernelModules`
- `ProtectKernelTunables`
- `LockPersonality`
- `MemoryDenyWriteExecute`
- network address-family restriction to IPv4/IPv6

This limits local impact but does not constrain outbound HTTPS destinations.

## OAuth and policy risk

ClaudeX uses the OAuth client flow supported by CLIProxyAPI to access Codex through a ChatGPT subscription. This may not have the same support or policy status as the official Codex client or an OpenAI API key. Providers can change protocols, revoke tokens, or enforce account restrictions.

Use a separate account if your risk tolerance requires it. Never publish `~/.local/share/claudex`, the generated API key, debug logs containing prompts, or raw proxy journals.

## Supply chain

The Nix build pins CLIProxyAPI source and dependencies. Updates are deliberate hash changes. Before updating:

1. Review auth storage and refresh logic.
2. Review Anthropic-to-Codex translators.
3. Recheck listener and management defaults.
4. Recheck request logging.
5. Reapply or retire the local-model updater and credential-log patches.
6. Run `claudex-doctor --probe` and the complete acceptance test.
