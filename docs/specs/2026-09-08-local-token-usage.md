# Local token usage

Usage is a fourth native SwiftUI panel tab. It is independent of the quota rings: quota percentages cannot be converted into token consumption.

## Query behavior

- Lifetime tokens and Lifetime cost (USD) always cover all imported local history and all agents. Filters affect only the section below them.
- All agents is the default. Codex, Claude Code, Gemini CLI and Antigravity are one-click presets; Choose agents supports any combination, including an empty selection. Unavailable sources remain explicit in the coverage section.
- 1d, 7d, and 30d are rolling 24-hour periods, with an inclusive start and end at refresh time. All has no lower bound. Future timestamps are excluded. Daily chart buckets use the Mac's local calendar.
- Detail includes input, cache read/write, output, total tokens, estimated cost, sessions, active days, cache read share of all input, daily totals, and a model breakdown across selected agents.

## Local sources and accounting

| Agent | Source | Accounting |
| --- | --- | --- |
| Codex | `~/.codex/sessions/**/*.jsonl`, `~/.codex/archived_sessions/**/*.jsonl` | Cumulative token deltas; repeated quota events ignored; turn context provides model. Cached input is a subset of input. Reasoning is a subset of output. Fork prefixes provide a baseline and do not count as new consumption. |
| Claude Code | `~/.claude/projects/**/*.jsonl`, including subagents | Assistant usage, deduplicated by message ID across streaming rows and copied logs. Cache read, 5-minute write, and 1-hour write are separate from fresh input. |
| Gemini CLI | `~/.gemini/tmp/**/chats/session-*.json` | Per-message token usage. Cached tokens are a subset of input; thoughts are added to output. Unclassified reported totals remain visible as other tokens. |
| Antigravity | `~/.gemini/antigravity/conversations/*.db`, `~/.gemini/antigravity-ide/...`, `~/.gemini/antigravity-cli/...` | Per-generation `ModelUsageStats` protobuf in `steps.metadata`, timestamped from the step's own start time and joined to `gen_metadata` on the server-assigned response id for the model name. Prompt tokens and cache reads are disjoint, so they sum. `output_tokens` already contains the thinking/response split and is never re-added. Deduplicated by response id, so the same conversation copied between installs counts once. `antigravity-backup` is not read. |
| Cursor, Grok | No supported token history adapter | Shown as unavailable, never inferred from quotas or request counts. |

`UsageHistoryReader` scans off the main actor and checks cancellation between files and JSONL chunks. File size and modification time avoid reparsing unchanged logs. A metadata-only ledger is atomically saved in `~/Library/Application Support/Codenotch/token-history-v1.json`; imported records survive deletion and rotation of source logs. IDs and file paths are hashed. Neither prompts nor responses enter the ledger. A corrupt ledger is preserved, with an explicit warning; inaccessible sources and incomplete files are also reported. The window refreshes on entry, on request, and every 60 seconds while the Usage view is active. Closing the window releases its model and cancels its task.

Every source reports why it contributed what it did, including nothing, in the coverage section: the folders that were checked, which of them exist, how many files were found, and how many generations came out. Zero has several unrelated causes — not installed, installed but unused, folder moved, files unreadable, or no adapter — and only some are the user's to act on, so the panel names which one it is instead of rendering a bare 0.

`SQLiteStore.open` verifies each candidate connection with a real query before accepting it. `sqlite3_open_v2` returns `SQLITE_OK` without touching the file, so the `mode=ro` attempt used to always win and the `immutable=1` fallback was never reached; every database whose owning app had quit and checkpointed then answered every query with *no rows* rather than an error. This affected Antigravity, Cursor and Codex alike.

Lifetime means all imported history on this Mac, potentially spanning accounts. It cannot reconstruct logs deleted before import. Sessions without timestamped token accounting cannot be estimated from text length. Missing model names remain Unknown model.

## USD estimates

Reference prices were read on September 8, 2026 from:

- https://developers.openai.com/api/docs/pricing
- https://ai.google.dev/gemini-api/docs/pricing

The bundled table uses exact IDs and **standard short-context text** reference rates. It estimates API-equivalent cost; it is not the user's subscription bill or an invoice reconstruction. Long-context premiums, fast processing, regional uplifts, non-text modalities, tool calls, storage, and subscription fees are excluded. Historical records use the current reference or user-specified rate, not a historical rate schedule.

Unknown models remain unpriced. Partial totals carry `+`, completely unpriced totals say Not priced, and model rows use an em dash. Tokens remain fully included. Records with unclassified token buckets have no cost estimate. Model prices provides persisted per-million-token overrides for all five billed categories, including zero prices for genuinely free usage. Restore reference removes an override; models without a reference return to unpriced.

The Claude pricing site was inaccessible during implementation, so no unverified Claude rate was bundled. Users can enter their rates in Model prices.

## Verification

Deterministic XCTest fixtures cover cumulative deltas, repeated events, counter resets, model switches, fork baselines, Claude cache accounting and duplicate messages, Gemini thinking tokens, malformed rows, protobuf wire-format decoding and its refusal to guess past truncated or overlong input, Antigravity token/timestamp/model-name extraction from a synthetic conversation database, undated generations, duplicate conversations across installs, per-source diagnostics, time boundaries, cost coverage, agent combinations, archive reload/rotation, saved-price overrides, and preservation of corrupt archives. No live credentials or provider endpoints are used by tests.

## Overview and grouped analysis

The revised dashboard starts with Lifetime cards and an Overview heatmap. Overview always covers the last 365 local calendar days for the selected agents, independent of the analysis period below it. Grey cells represent no imported usage; green intensity represents daily tokens. Most-active month/day and longest/current streaks are derived from that window. Current streak may end yesterday while today is still in progress.

Analysis uses the existing agent and rolling-time filters. Group by Model / Agent switches both a native Swift Charts stacked cumulative area chart and its color-keyed detail legend. Each layer is one group's cumulative tokens, with missing dates carried forward; the stack endpoint equals the filtered total. Categories use a shared, deterministic palette based on all imported category names, so changing the query does not reassign colors. The legend includes tokens, share, and estimated USD. The original input/cache/output model table remains available in a disclosure section.
