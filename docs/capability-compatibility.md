# Codex capabilities through Claude Code

Research date: 2026-07-14.

This document separates three surfaces that are easy to conflate:

1. **Codex model capability** — what OpenAI's models and Codex clients support.
2. **Claude Code harness capability** — local tools, orchestration, policy, and UI.
3. **Protocol compatibility** — what CLIProxyAPI preserves while translating Anthropic Messages to OpenAI Codex Responses.

A feature is safe to advertise through ClaudeX only when all required layers exist.

## Evidence labels

| Label | Meaning |
|---|---|
| **official** | Documented by OpenAI or Anthropic |
| **catalogued** | Present in OpenAI's embedded Codex client model catalog |
| **translated** | Explicitly implemented and tested in pinned CLIProxyAPI source |
| **validated** | Exercised through the installed ClaudeX stack |
| **incompatible** | A required protocol or first-party service is absent |
| **unverified** | Plausible but not established end to end |

Audit versions:

- Claude Code `2.1.197`
- CLIProxyAPI `v7.2.72`, commit `6279bb8a4c2835ff6ed99c6b85083b2afbefa681`
- ClaudeX default models: `gpt-5.6-sol`, `gpt-5.6-terra`, `gpt-5.6-luna`

## Codex model surface

The embedded OpenAI Codex client catalog reports the following for all three default models:

- 372,000-token context window
- 128,000-token maximum completion
- text and image inputs
- parallel tool calls
- native web search with text and image results
- shell-command tool mode
- reasoning summaries and low/medium/high/xhigh/max effort
- Responses Lite and WebSocket preference

Sol and Terra advertise multi-agent version 2 and an additional `ultra` effort. Luna advertises multi-agent version 1 and stops at `max`. OpenAI's [Models](https://developers.openai.com/codex/models) documentation describes Ultra as a subagent workflow, not merely a larger single-model reasoning budget.

ClaudeX intentionally does not present Codex `ultra` as a Claude effort capability. Claude Code's similarly named ultracode/workflow machinery is a different orchestrator with different fan-out controls.

## Compatibility matrix

### Core interaction and tools

| Capability | Codex parallel | Claude Code surface | Bridge result | Policy |
|---|---|---|---|---|
| Text messages and streaming | Responses text/SSE | Interactive and print modes | **translated, validated** | keep |
| Shell execution | native shell tool | `Bash` | Sent as an ordinary function tool; Claude Code executes locally | keep |
| File read/search/edit | native local tools in Codex clients | `Read`, `Glob`, `Grep`, `Edit`, `Write`, `NotebookEdit` | Ordinary function tools; execution remains in Claude Code | keep |
| Tool choice | Responses `auto`, `required`, `none`, named function | Anthropic tool choice | **translated and tested** | keep |
| Parallel tool calls | catalogued | parallel safe tools | **translated and tested** | keep with concurrency cap |
| Images in prompts/results | catalogued text+image input | image content blocks and tool results | **translated and tested** | keep |
| Model effort | Codex reasoning levels | Claude thinking budget/adaptive effort | mapped to `reasoning.effort`; summaries/signatures translated | keep low–max |
| Interleaved reasoning/tool use | encrypted reasoning items | signed thinking blocks | replay cache and signature compatibility are tested | keep |
| Stop reasons and usage | Responses metadata | Anthropic message metadata | translated, including cached-input tokens | keep |
| Local token counting | GPT tokenizer | `/v1/messages/count_tokens` | implemented locally by CLIProxyAPI | keep; treat as estimate |
| Structured output (`--json-schema`) | Responses structured outputs | Claude Code print-mode schema | Anthropic `output_config` schema is not translated on the Codex path | **do not advertise** |
| Anthropic sampling/output fields | provider-specific | `max_tokens`, stop sequences, temperature/top-p | Codex translator does not forward these fields; model limits still apply upstream | document discrepancy |

### Instructions, extensibility, and policy

| Capability | Codex parallel | Claude Code surface | Bridge result | Policy |
|---|---|---|---|---|
| Repository instructions | `AGENTS.md` | `CLAUDE.md`, rules, memory | Claude system blocks become Codex developer messages | keep |
| Skills | native Codex skills/plugins | Claude Code `Skill` and local/plugin skills | Skill expansion is client-side prompt/context work | keep |
| Hooks | native Codex lifecycle hooks | Claude Code hooks | Hook execution and policy are client-side | keep |
| Permissions/sandbox | native approvals and sandbox | Claude permission modes, hooks, pagu-box | Claude Code remains the execution boundary | keep |
| MCP tools | native STDIO/HTTP MCP | Claude MCP clients and project `.mcp.json` | MCP calls are ordinary function tools; long names are shortened and restored | keep, project-scoped |
| Deferred MCP ToolSearch | native Codex clients have their own discovery | Claude `ToolSearch`, `tool_reference`, `defer_loading` | `defer_loading` is deleted and `tool_reference` is not translated | **disable; eager tools only** |
| Plugins | Codex plugins can bundle skills/MCP/hooks | Claude plugins can bundle skills/MCP/hooks | Local components work through their constituent surfaces | keep local plugins; no cloud connectors |
| Prompt caching | OpenAI prompt cache keys/cached-token accounting | Anthropic `cache_control` breakpoints | tool-level `cache_control` is removed, but CLIProxyAPI derives a stable Codex `prompt_cache_key` from the Claude session and reports cached tokens | keep as coarse emulation |
| Compaction | native Codex compaction exists | Claude `/compact` and auto-compaction | Claude performs model-driven summarization through the bridge; it does not use native Codex client orchestration | keep, constrain summary size |

### Web and browser capabilities

| Capability | Result | Policy |
|---|---|---|
| `WebSearch` | Claude's typed server-search declaration is explicitly converted to Codex `web_search`; results are converted back to Claude server-tool blocks. **Translated and tested.** | keep |
| `WebFetch` | Claude Code fetches locally, then uses a small model to extract content. It can work through Luna, but its default domain-safety preflight contacts Anthropic. | keep only with `skipWebFetchPreflight = true`; prefer a fetch MCP or `curl` for lossless reads |
| Claude in Chrome | Anthropic requires a direct Anthropic plan; third-party providers are unsupported. | disable/reject `--chrome` |
| Claude computer use | Requires claude.ai authentication and is unavailable through third-party providers; CLI support is macOS-only. | disable |
| Codex browser/computer use | OpenAI documents native browser and computer-use surfaces, but ClaudeX does not expose the Codex client protocol for them. Generic MCP browser tools remain usable. | use Playwright/Chrome MCP instead |
| Image generation | Codex supports it, but Claude Code has no equivalent first-party local tool in the current eager set and Responses Lite suppresses implicit image-tool injection. | unverified; do not advertise |

### Agents and orchestration

Both products support subagents, but their safety defaults differ materially.

| Property | Native Codex | Claude Code 2.1.197 |
|---|---:|---:|
| Default concurrent agent threads | 6 | no equivalent hard agent cap |
| Default nesting depth | 1 | nested subagents allowed to fixed depth 5 |
| General safe-tool concurrency | client-specific | 10 (`CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY`) |
| API retries per logical request | client/provider-specific | 10 by default, maximum 15 |
| Dynamic workflow size | bounded by Codex agent settings | bundled workflows can fan out broadly; size guideline is advisory and unavailable before Claude Code 2.1.202 |
| Teams | native subagent orchestration | experimental Claude teams have no hard teammate limit |

Ordinary Claude Code `Agent` calls work because every subagent is another normal model session and Codex supports tool use. The risk is orchestration policy, not protocol translation.

The bundled Claude `deep-research` workflow in 2.1.197 performs:

1. five parallel WebSearch agents;
2. URL deduplication and up to fifteen source fetches;
3. three-way adversarial verification per claim;
4. synthesis.

During the 2026-07-14 incident, this interacted with five Claude Code processes, the default ten retries, and approximately 200 loopback connections. The gateway observed 10–49 incoming message requests per second and OpenAI began returning 429. Cancelling the workflow restored service.

**Policy:** retain ordinary subagents and Claude Code's standard retry/tool behavior, but disable dynamic workflows in ClaudeX. Agent definitions should still omit `Agent` unless nested delegation is intentional.

### Anthropic first-party cloud surfaces

These features require claude.ai or Anthropic-hosted infrastructure rather than only the Messages protocol:

- Remote Control (`ANTHROPIC_BASE_URL` on a custom gateway is explicitly unsupported)
- Artifacts publishing
- claude.ai connectors
- routines and cloud scheduling
- push notifications and remote file delivery
- shared onboarding links
- `setup-token`
- cloud-hosted `ultrareview`
- Claude in Chrome and Claude computer use
- subscription usage/cost reporting

They have no native meaning through Codex OAuth. ClaudeX explicitly disables the two surfaces most likely to activate implicitly—claude.ai connectors and Remote Control—but otherwise relies on the gateway's lenient compatibility behavior rather than broadly hiding Claude Code features.

## Selected ClaudeX policy

ClaudeX sets `CLAUDE_CODE_DISABLE_WORKFLOWS=1` and supplies this provider-specific Claude Code settings overlay:

```json
{
  "disableClaudeAiConnectors": true,
  "disableRemoteControl": true,
  "disableWorkflows": true
}
```

The environment variable and setting deliberately reinforce the workflow boundary. The settings are passed only by the `claudex` launcher, so ordinary `claude` sessions remain unchanged.

All other Claude Code surfaces remain available where the compatibility gateway accepts them. In particular, ClaudeX does not disable local hooks, local/project skills, MCP, permissions, plan mode, LSP, IDE integration, ordinary subagents, Artifacts, prompt suggestions, WebFetch, or structured-output flags globally. Their matrix entries above describe known translation caveats rather than launcher prohibitions.

## Sources

### OpenAI

- [Codex models](https://developers.openai.com/codex/models)
- [Codex subagents](https://developers.openai.com/codex/agent-configuration/subagents)
- [Codex hooks](https://developers.openai.com/codex/hooks)
- [Codex MCP](https://developers.openai.com/codex/extend/mcp)
- [Codex skills and plugins](https://developers.openai.com/codex/skills-and-plugins)
- [Codex web search](https://developers.openai.com/codex/web-search)
- [Codex image inputs](https://developers.openai.com/codex/image-inputs)
- [Codex permissions](https://developers.openai.com/codex/permission-modes)

### Anthropic

- [Claude Code tools reference](https://code.claude.com/docs/en/tools-reference)
- [Claude Code subagents](https://code.claude.com/docs/en/sub-agents)
- [Claude Code agent teams](https://code.claude.com/docs/en/agent-teams)
- [Claude Code hooks](https://code.claude.com/docs/en/hooks)
- [Claude Code MCP](https://code.claude.com/docs/en/mcp)
- [Claude Code skills](https://code.claude.com/docs/en/skills)
- [Claude Code prompt caching](https://code.claude.com/docs/en/prompt-caching)
- [Claude Code Chrome integration](https://code.claude.com/docs/en/chrome)
- [Claude Code Remote Control](https://code.claude.com/docs/en/remote-control)
- [Claude Code settings](https://code.claude.com/docs/en/settings)

### Bridge source

Pinned CLIProxyAPI paths:

- `internal/translator/codex/claude/codex_claude_request.go`
- `internal/translator/codex/claude/codex_claude_response.go`
- `internal/translator/codex/claude/codex_claude_response_web_search.go`
- `internal/runtime/executor/codex_executor.go`
- `internal/runtime/executor/codex_executor_cache_test.go`
- `internal/runtime/executor/codex_executor_reasoning_replay_cache_test.go`
- `internal/registry/models/codex_client_models.json`

Focused translator and executor tests passed against pinned commit `6279bb8a4c2835ff6ed99c6b85083b2afbefa681` during this audit.
