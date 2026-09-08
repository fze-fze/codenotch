# Local token usage

Usage is a fourth native SwiftUI panel tab. It is independent of the quota rings: quota percentages cannot be converted into token consumption.

## Query behavior

- Lifetime tokens and Lifetime cost (USD) always cover all imported local history and all agents. Filters affect only the section below them.
- All agents is the default. Codex, Claude Code, and Gemini are one-click presets; Choose agents supports any combination, including an empty selection. Unavailable sources remain explicit in the coverage section.
- 1d, 7d, and 30d are rolling 24-hour periods, with an inclusive start and end at refresh time. All has no lower bound. Future timestamps are excluded. Daily chart buckets use the Mac's local calendar.
- Detail includes input, cache read/write, output, total tokens, estimated cost, sessions, active days, cache read share of all input, daily totals, and a model breakdown across selected agents.

## Local sources and accounting

| Agent | Source | Accounting |
| --- | --- | --- |
| Codex | `~/.codex/sessions/**/*.jsonl`, `~/.codex/archived_sessions/**/*.jsonl` | Cumulative token deltas; repeated quota events ignored; turn context provides model. Cached input is a subset of input. Reasoning is a subset of output. Fork prefixes provide a baseline and do not count as new consumption. |
| Codex, archived threads | `~/.codex/state_*.sqlite` (`threads`) | Per-thread `tokens_used` for threads whose rollout log is gone. One unclassified total per thread, so it is counted but never priced. |
| Claude Code | `~/.claude/projects/**/*.jsonl`, including subagents | Assistant usage, deduplicated by message ID across streaming rows and copied logs. Cache read, 5-minute write, and 1-hour write are separate from fresh input. |
| Gemini CLI | `~/.gemini/tmp/**/chats/session-*.json` | Per-message token usage. Cached tokens are a subset of input; thoughts are added to output. Unclassified reported totals remain visible as other tokens. |
| Antigravity | `~/.gemini/antigravity{,-cli,-ide}/conversations/*.db` | One SQLite store per conversation. `gen_metadata` holds a protobuf record per model generation; `steps` holds the timestamps it points at by index. Cached prefix tokens are separate from fresh input. |
| Grok | `~/.grok/sessions/**/updates.jsonl` | One cumulative `usage` summary per prompt on the JSON-RPC update stream, broken down per model by `modelUsage`. Cache reads and cache writes are carved out of the reported input; reasoning is already inside output. |
| Cursor | No local token counts to read | Shown as unavailable, never inferred from quotas or request counts. |

Codex Desktop writes the same rollout logs as the CLI — `session_meta.originator` names the client, and on the machine this was built against 55 of 63 logs were Codex Desktop — but **archiving a thread deletes its log**. That is not an edge case: 753 of 816 threads were archived, and every one had lost its transcript, while all 63 unarchived threads still had theirs. Without a second source, archiving silently erases history that was never imported.

Codex's own state database keeps a per-thread `tokens_used` that outlives the log, and it is read for threads whose log is gone. It is deliberately coarser, in two ways that are carried rather than smoothed over. It is the *final* cumulative counter, not the sum across context compactions: checked against the logs still on disk it matched exactly for every thread that never compacted and undercounted the ones that did — 188M against a true 311M across the same 63 threads — so a recovered thread total is a floor. And it has no bucket split and no per-turn times, so the whole thread lands in the unclassified bucket, dated by when it was last worked on. The unclassified bucket already means "no cost estimate", so a recovered thread contributes tokens and no dollars, which is the honest reading.

A thread is read from the state database only when its log is genuinely gone **and** nothing was imported from it earlier, so a thread archived after Codenotch had already seen it keeps its detail and is never counted twice. The two sources agree on session identity — a thread's ID is its session ID — so recovered threads do not inflate the session count either.

The remaining loss is real and worth stating: a thread archived before Codenotch first ran keeps only its total, and one archived before the state row existed keeps nothing. Continuous import is what narrows that window, since anything already imported survives the log's deletion.

Antigravity is not the Gemini CLI, and on a machine with Antigravity installed `~/.gemini` holds Antigravity's own directories rather than Gemini CLI chats. The two are read as separate sources; the app, its CLI, and its IDE integration are counted together under Antigravity.

Antigravity ships no protobuf descriptors, so its fields are addressed by number. The mapping was confirmed before being trusted rather than assumed: the output field is exactly the sum of the two fields beside it (reasoning and answer tokens), and input + cached tracks Antigravity's own context-used counter across a conversation, offset by a constant the client adds for its own prompt estimate. One field is constant for a whole conversation, so it is a property of the prompt rather than a per-request bucket; counting it per generation would inflate every conversation by a multiple of its own system prompt, and it is deliberately excluded. A generation whose steps carry no timestamp is dropped rather than dated by guess, and a request that failed before the model answered carries no usage submessage and is not counted.

Grok's accounting was missed on the first pass and is worth recording why. It hides behind two things at once: it is not in the transcript — `chat_history.jsonl` carries no counts, and the `events.jsonl` telemetry stream is lifecycle only — and it spells its fields in camelCase (`inputTokens`, `cachedReadTokens`) where every other agent uses snake_case, so a snake_case search over `~/.grok` finds nothing but documentation. It lives in `updates.jsonl`, the JSON-RPC stream Grok writes when driven through the agent-client protocol, which means coverage is partial by nature: sessions run without that client leave no accounting behind. Grok's own docs describe usage telemetry as an opt-in OpenTelemetry export to a collector the user configures; that is a separate stream and is not what is read here.

A prompt is summarised more than once as it runs and the counts are cumulative, so records are keyed on the prompt rather than the line and the repeats collapse onto one record, where the archive keeps the largest reading of each bucket. Grok also reports its own `costUsdTicks` per prompt. That figure is not used: costs everywhere else are reference-rate estimates, and it does not reproduce from published `grok-4.6` rates, so mixing the two would make one column mean two different things.

Cursor was checked against its own local state, not assumed. It writes a `tokenCount` on every chat message and leaves both halves zeroed; the non-zero token figures it does keep are context-window limits and estimates, not what was billed. It says so instead of showing a zero.

`UsageHistoryReader` scans off the main actor and checks cancellation between files and JSONL chunks. File size and modification time avoid reparsing unchanged logs. A metadata-only ledger is atomically saved in `~/Library/Application Support/Codenotch/token-history-v1.json`; imported records survive deletion and rotation of source logs. IDs and file paths are hashed. Neither prompts nor responses enter the ledger. A corrupt ledger is preserved, with an explicit warning; inaccessible sources and incomplete files are also reported. The window refreshes on entry, on request, and every 60 seconds while the Usage view is active. Closing the window releases its model and cancels its task.

Lifetime means all imported history on this Mac, potentially spanning accounts. It cannot reconstruct logs deleted before import. Sessions without timestamped token accounting cannot be estimated from text length. Missing model names remain Unknown model.

## USD estimates

Reference prices were read on September 8, 2026 from:

- https://platform.claude.com/docs/en/build-with-claude/prompt-caching.md
- https://developers.openai.com/api/docs/pricing
- https://ai.google.dev/gemini-api/docs/pricing

The bundled table uses exact IDs and **standard short-context text** reference rates. It estimates API-equivalent cost; it is not the user's subscription bill or an invoice reconstruction. Long-context premiums, fast processing, regional uplifts, non-text modalities, tool calls, storage, and subscription fees are excluded. Historical records use the current reference or user-specified rate, not a historical rate schedule.

Unknown models remain unpriced. Partial totals carry `+`, completely unpriced totals say Not priced, and model rows use an em dash. Tokens remain fully included. Records with unclassified token buckets have no cost estimate. Model prices provides persisted per-million-token overrides for all five billed categories, including zero prices for genuinely free usage. Restore reference removes an override; models without a reference return to unpriced.

Anthropic publishes every cache bucket per model, so Claude models carry all five rates: cache reads at a tenth of base input, five-minute writes at 1.25x and one-hour writes at 2x. Claude Code leans on all of them, and an input-and-output-only estimate would misprice most of a real conversation. Google's published cache figure is the context-cache read rate; cache storage is billed per hour rather than per token and has no per-token bucket here. The current Gemini Flash models carry a promotional rate that expires December 31, 2026, and the rate in effect on the day the table was checked is the one used.

Models with no published rate stay unpriced rather than inheriting a sibling's. Two cases matter in practice. Codex's internal auto-review model is a real turn model in the logs and is billed to no public table. `grok-4.6-build`, the model Grok Build names in its own logs, is not a published model ID either, and Grok's cost figure for it does not reproduce from `grok-4.6` rates, so pricing it as its near-namesake would be a guess dressed as a rate. Both have their tokens counted and their cost left unestimated. Users can enter a rate for either, or for any other model, in Model prices.

## Verification

Deterministic XCTest fixtures cover cumulative deltas, repeated events, counter resets, model switches, fork baselines, Claude cache accounting and duplicate messages, Gemini thinking tokens, malformed rows, time boundaries, cost coverage, agent combinations, archive reload/rotation, saved-price overrides, and preservation of corrupt archives. Antigravity is covered by hand-encoded protobuf written into a real SQLite store with its schema, so the blob is proven to survive the database round trip: disjoint buckets, the excluded conversation constant, failed and undated generations, truncated and unknown wire types, absurd counts, and a conversation seen through two installs collapsing to one record. Codex archived-thread recovery is covered by fixtures for the two ways it could go wrong — a thread counted twice because it was archived after its log was imported, and a coarse total preferred over a log that still exists — plus unclassified accounting, unpriced-but-counted totals, session identity matching the log reader's, millisecond and second timestamps, rows with nothing to report, and finding the state database by name rather than by a hardcoded version. Grok is covered by fixtures taken from a real update stream: cache reads carved out of a reported input that includes them, reasoning left inside output, repeated cumulative summaries for one prompt collapsing onto one record, a turn split across models attributed to each, rows with no accounting or no usable time ignored, and epoch-second stamps accepted alongside ISO-8601 while booleans and out-of-range values are refused. Pricing fixtures assert the published cache multipliers, that every model these agents can name is priced, and that an unpublished model stays unpriced while its tokens still count. No live credentials or provider endpoints are used by tests.

`SQLiteStore` had a latent fault that this work exposed. `sqlite3_open_v2` allocates the connection before it looks at the file, so a `mode=ro` open reports success on a write-ahead-logged database whose `-shm` sidecar is missing — the normal state once the owning app has quit — and fails only at the first statement. Returning that connection was worse than failing: every query answered with no rows, so a store full of history read as an empty one, with no error and no warning, and the `immutable=1` fallback behind it never ran. The connection is now proved readable before it is returned. Cursor's and Codex's stores are read through the same helper and were subject to the same silence.

## Overview and grouped analysis

The revised dashboard starts with Lifetime cards and an Overview heatmap. Overview always covers the last 365 local calendar days for the selected agents, independent of the analysis period below it. Grey cells represent no imported usage; green intensity represents daily tokens. Most-active month/day and longest/current streaks are derived from that window. Current streak may end yesterday while today is still in progress.

Analysis uses the existing agent and rolling-time filters. Group by Model / Agent switches both a native Swift Charts stacked cumulative area chart and its color-keyed detail legend. Each layer is one group's cumulative tokens, with missing dates carried forward; the stack endpoint equals the filtered total. Categories use a shared, deterministic palette based on all imported category names, so changing the query does not reassign colors. The legend includes tokens, share, and estimated USD. The original input/cache/output model table remains available in a disclosure section.
