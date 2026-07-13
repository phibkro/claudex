# Research and sources

This document preserves the evidence used to design ClaudeX. Dates and model names reflect the original implementation on 2026-07-13.

## Theo Browne's ClaudeX

Theo described a private project called ClaudeX/Claudeex but had not published its implementation.

- [So I've been using GPT-5.6 for awhile...](https://www.youtube.com/watch?v=mHG7K7QmQyU&t=1457s), around 24:17:
  > I had it create ClaudeX, which let me use my Codex OAuth in Claude Code so I could test using Claude Code's workflows with Codex.
- [This is absolute chaos...](https://www.youtube.com/watch?v=sKmrLtB47WA&t=1480s), around 24:40:
  > I set up my Claude Code to allow for it to call Codex... We're actually using Sol as the model in Claude Code.

He said a dedicated explanation was forthcoming. No public ClaudeX repository or implementation instructions were found during the original research.

## Claude Code gateway support

Official Claude Code documentation establishes the supported gateway seam:

- [LLM gateway configuration](https://code.claude.com/docs/en/llm-gateway)
- [Model configuration](https://code.claude.com/docs/en/model-config)

Key environment variables:

```text
ANTHROPIC_BASE_URL
ANTHROPIC_AUTH_TOKEN
ANTHROPIC_MODEL
ANTHROPIC_DEFAULT_OPUS_MODEL
ANTHROPIC_DEFAULT_SONNET_MODEL
ANTHROPIC_DEFAULT_HAIKU_MODEL
```

Claude Code also documents `_NAME`, `_DESCRIPTION`, and `_SUPPORTED_CAPABILITIES` metadata for provider-specific pinned model IDs.

## Protocol bridge

[router-for-me/CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI) already supplied the required mechanics:

- Codex OAuth login
- Anthropic-compatible `/v1/messages`
- Anthropic ↔ OpenAI Responses/Codex translation
- streaming tool calls
- reasoning replay/state
- embedded Codex model catalog
- Linux server support

The original integration pinned release `v7.2.72`, commit `6279bb8a4c2835ff6ed99c6b85083b2afbefa681`.

## Model tiers

The pinned embedded catalog described:

- `gpt-5.6-sol`: “Latest frontier agentic coding model.”
- `gpt-5.6-terra`: “Balanced agentic coding model for everyday work.”
- `gpt-5.6-luna`: “Fast and affordable agentic coding model.”

Those descriptions motivated the Opus/Sonnet/Haiku mapping.

## ToolSearch finding

Claude Code debug output on a custom `ANTHROPIC_BASE_URL` reported:

```text
[ToolSearch:optimistic] disabled: ANTHROPIC_BASE_URL=http://127.0.0.1:8317 is not a first-party Anthropic host. Set ENABLE_TOOL_SEARCH=true ... if your proxy forwards tool_reference blocks.
```

Source inspection found `tool_reference` handling in CLIProxyAPI's Claude executor but not in its Claude-to-Codex translators. Explicit eager built-in tools were therefore selected instead of claiming unsupported deferred ToolSearch compatibility.

## Alternative considered

`musistudio/claude-code-router` was considered. CLIProxyAPI was selected because its Codex OAuth and Anthropic-to-Codex path matched the demonstrated use case more directly.
