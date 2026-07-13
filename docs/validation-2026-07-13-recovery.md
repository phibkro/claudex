# Recovery and diagnostics validation — 2026-07-13

## Incident reproduced

After subscription usage was exhausted, generation returned HTTP 429 while
`/healthz`, authenticated model discovery, and token counting still returned
200. Once the upgraded plan began serving requests, two model tiers recovered
but the highest tier remained in CLIProxyAPI's in-memory credential cooldown.
Restarting `claudex.service` cleared that stale cooldown; generation then
succeeded through all three aliases.

This establishes that transport health is not generation readiness and that
reauthentication is not the first response to a post-quota 429.

## Diagnostic checks

The generated `claudex-doctor` command was run against the live hardened service.
Without generation probes it confirmed:

- active user service;
- loopback-only listener;
- `/healthz` returned 200;
- unauthenticated model discovery returned 401;
- authenticated model discovery returned 200;
- recent generation-only 401/403/429/500 counts were available from the journal.

With `--probe`, one minimal request through each configured alias returned 200:

```text
generation-opus=PASS model=gpt-5.6-sol http=200
generation-sonnet=PASS model=gpt-5.6-terra http=200
generation-haiku=PASS model=gpt-5.6-luna http=200
```

The ordinary `claudex` launcher also completed an end-to-end request after
recovery.

## Privacy regression control

Upstream session-affinity logs used `auth.ID`, whose value derives from the OAuth
filename and may contain an account identifier. The package patch changes only
logging arguments to use `auth.Provider`; credential cache keys and selection
continue using the original ID. Diagnostic rendering also redacts email-shaped
strings from upstream error messages.

Raw OAuth files, tokens, downstream keys, prompts, account identifiers, and
complete journals are intentionally absent from this record.
