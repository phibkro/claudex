# Original implementation report

## Goal

Use OpenAI Codex models inside Claude Code while preserving Claude Code's harness and leaving ordinary `claude` unchanged.

## Sequence

1. Located Theo Browne's ClaudeX demonstrations and established that no implementation had been published.
2. Confirmed Claude Code's official custom-gateway and pinned-model seams.
3. Identified CLIProxyAPI as an existing Anthropic-to-Codex bridge with ChatGPT OAuth.
4. Audited its listener, management, token storage, updater, translation, and model-catalog surfaces.
5. Built and pinned it declaratively with Nix.
6. Added private runtime initialization and a hardened on-demand user service.
7. Added `claudex`, login, status, and model-audit commands.
8. Completed browser OAuth and an end-to-end Sol request.
9. Mapped Opus/Sonnet/Haiku to Sol/Terra/Luna from catalog evidence.
10. Added picker metadata and a read-only acceptance prompt.
11. Found and fixed Claude Code's custom-gateway ToolSearch incompatibility using eager built-ins.
12. Verified all three models externally from proxy journal records.

## Original homelab commits

```text
b3ebaa1 feat(agents): add hardened ClaudeX Codex gateway
52517bc feat(agents): map ClaudeX tiers and add acceptance test
7cb2b34 fix(agents): expose ClaudeX tools on custom gateway
```

The implementation was subsequently extracted into this repository so consumers can pin it as an independent flake.

## Evidence discipline

Three evidence classes were kept separate:

- A returned marker proves the harness completed a requested interaction.
- Tool output proves Claude Code exposed and executed that tool.
- Proxy journal selection records prove which Codex OAuth model handled the request.

A model's statement about its identity was explicitly rejected as provider evidence.

## Operational caveats discovered

- API-key/gateway authentication disables Claude.ai connectors; Claude Code warns about this at startup.
- Custom gateways disable deferred ToolSearch unless they support Anthropic `tool_reference` blocks.
- NixOS-integrated Home Manager packages require system activation to update `/etc/profiles/per-user`; invoking a standalone Home Manager activation only linked managed files.
- Unrelated failed systemd units can make `nixos-rebuild test` return failure after Home Manager changes have already activated.
