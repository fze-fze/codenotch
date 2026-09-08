# Codenotch

> Working name — not final.

A macOS agent app that pins a small black notch to the **right edge** of the screen
showing how much of each LLM's session limit you have burned, and whether you have hit
the wall yet. Hover a provider to see its individual limit windows and when they reset — and
tells you at a glance whether Claude is still working, done, or waiting on you.
The ring always shows the **current session**, the same window Claude's own usage
panel leads with, so the two never disagree.

![Collapsed notch with hover tooltip](docs/design/frame-124-hover-tooltip.png)

Settings show which account each reading belongs to and whether it is coming
through — and nothing more. That list used to carry a switch per provider plus
buttons to open, switch and re-authorise each account, and every one of them
acted on an account Codenotch does not own: the reading is borrowed from a tool
that already holds the login, so the honest place to change any of it is that
tool. Sign in or out there and the reading here follows.
Settings live in an orb below the notch — an arc in the corner at rest, a gear
when you reach for it. It folds away when you are not looking at it: at rest it is a small pill on the
screen edge, and it unfolds when the pointer reaches it. Click to pin it open.

The notch can live on any of the four edges. Right and left keep the vertical
column; top and bottom lay the readings out side by side, because four cells
stacked vertically would hang a quarter of the way down the screen. It pins
itself to the *usable* edge, so a bottom notch rests on top of the Dock — and it
follows when the Dock hides or moves. On a Mac with a notch of its own, the top
placement takes the hardware notch's own shape — straight sides, rounded
underneath, moulded into the frame at the top — so the notch simply looks wider
and deeper rather than having a bar parked underneath it. Folded away it *is*
the notch, and reaching for it makes the notch grow.

## Status

The notch is built, matches the design frame, and shows **your real Claude
usage** — the same session and weekly percentages Claude's own usage panel
reports, refreshed every 60 seconds. `make run` puts it on screen, hover pops the
detail card.

It also answers **"is Claude still working?"** — inside the Claude ring, a thin
arc spins while a session is working and becomes a pulsing amber ring when one is
blocked waiting on you. Hover for every live session by name, where it is
running, and what it wants.

Cursor and Codex are wired up too, both reading locally: Cursor borrows the
editor's own session from its SQLite state store, and Codex reads the rate-limit
snapshots it writes into its own rollout logs — no credential, no network.
Antigravity is read the same way, through the language server it runs itself.
Grok borrows the CLI's own session from `~/.grok/auth.json` and asks the same
credits billing endpoint `grok /usage` does. There is one weekly limit, and the
ring is how much of it is gone; the card then breaks that figure down by
product — Grok Build, Grok Chat — as *shares of the same limit* rather than as
limits of their own, so those rows say "13% of limit" and only the limit itself
says what is left. The plan's name comes from `/v1/settings`, because the
billing endpoints state percentages and never say which tier they belong to. Its
ring spins while a Grok TUI is mid-turn, read from the sessions it lists in
`~/.grok`.
Run with `CODENOTCH_DEMO=1` to see the design frame's three-provider layout with
its numbers.

## Skills

The other half of the app, reached from **Skills…** in the notch's right-click
menu, the menu bar item, or Settings. A skill is a folder with a `SKILL.md` in
it, and the five agents above will each read one — but not from the same place,
so a skill written once ends up copied four times and the copies drift.

The library is `~/.agents/skills`, which is not a folder of Codenotch's own:
it is the one **Codex, Cursor and Grok already read** with no configuration. So
three of the five are served by a skill merely being in it, and only Claude Code
(`~/.claude/skills`) and Antigravity (`~/.gemini/config/skills`) need anything —
a symlink pointing back at the library. One real copy of every skill, edited
once.

That gives the rule the whole feature rests on: **a mount is a symlink into the
library, and nothing else is ever removed.** A real folder already sitting in an
agent's directory is somebody's own work; a symlink pointing somewhere else is
somebody's deliberate arrangement, very likely another tool's. Both are reported
as conflicts and left exactly where they are. Removing a skill from the library
moves it to the Trash rather than deleting it. The same rule is what lets
Codenotch and `yibie/skills-manager` share a machine without fighting.

Reading the library and having a folder of your own are different things, and
every agent has both. `~/.codex/skills` alone holds fifteen skills that reach
Codex and nothing else, so the sidebar lists them under **Codex only** — one
group per agent, beside the global set. Skills get in by **promoting** one of
those: the folder moves into the library and a link goes back where it was, so
the agent that had it keeps it and every other agent gains it. There is no
marketplace and no import-from-URL.

The vendors' own bundled skills — `~/.codex/skills/.system`,
`~/.cursor/skills-cursor`, `~/.grok/bundled/skills`, about fifty between them —
are never shown. They are read-only and not yours, so there is nothing to be
done to one.

- Design spec: [`docs/specs/2026-09-07-skill-manager-design.md`](docs/specs/2026-09-07-skill-manager-design.md)

## Docs

- Design spec: [`docs/specs/2026-08-28-usage-notch-design.md`](docs/specs/2026-08-28-usage-notch-design.md)
- Implementation plan: [`docs/plans/2026-08-28-usage-notch-plan.md`](docs/plans/2026-08-28-usage-notch-plan.md)
- Design source of truth: [`docs/design/`](docs/design/)

Every size in the UI is measured off the design frame and expressed in frame
pixels (`Design.px(186)`), so the layout is proportionally exact. `Design.scale`
is the one constant that sets the absolute size; it is anchored on the spec's
44pt ring, which puts the notch at 70 x 401pt.

## Stack

Swift 6 / SwiftUI + AppKit, macOS 26, XcodeGen-generated project. Whether it
shows a Dock tile, a menu bar icon or neither is a setting, applied at launch
with `setActivationPolicy` rather than by `LSUIElement` — the plist key cannot
be changed at runtime, and being able to find the app matters more than being
invisible. Same conventions as `~/notch-app`.

## Build

```sh
brew install xcodegen   # once
make run                # generate, build, launch out of the build directory
make install            # ...or put it in /Applications and launch it there
make test               # unit tests
```

### Building it yourself

Debug builds sign with an ordinary **Apple Development** certificate, Release
builds with Developer ID — the two configurations in `project.yml`. Point
`DEVELOPMENT_TEAM` under `Debug` at your own team (`security find-identity -v
-p codesigning` names it) and `make run` needs no other edit. Xcode's location
is taken from `xcode-select -p`, so an Xcode beta is fine.

What matters is that the certificate is *stable*, not that it is Apple's: the
keychain's ACL remembers a binary's designated requirement, and an ad-hoc
signature's is its cdhash, which changes on every rebuild. Sign ad-hoc and
"Always Allow" is forgotten after each `make run`.

**Keychain prompts.** macOS asks once per credential the first time; choose
**Always Allow** and it stays quiet, as long as the build keeps the same
certificate and the same path. It asks again when a credential is deleted and
recreated — signing out of Claude Code and back in does exactly that — and
that is one prompt, not a recurring one.

There is a second gate behind the dialogue, the item's *partition list*, which
"Always Allow" cannot reach. `security set-generic-password-partition-list` is
the documented way to change it, and it is a **last resort**: it rewrites the
whole ACL, including the list of applications already trusted with that item,
so it can lock the credential's *owner* out of its own credential. That is not
theoretical — running it against Claude Code's item cost an afternoon, because
Claude Code could then no longer persist a login and every sign-in came back
signed-out.

Antigravity's item used to need it, when a read here met that gate once an
hour as Google rotated the token. It should not any more: Codenotch asks
Antigravity's own language server first, which needs no credential, so a
running Antigravity means no keychain read at all.

## The honest caveat

No LLM vendor publishes a clean "your session limit is N% used" API. The data layer is
a set of per-provider adapters that each declare their fidelity — `.official`,
`.derived` or `.manual` — and the UI never presents a derived number as if it were
official.

Claude is `.official`: `ClaudeOAuthProvider` reads the OAuth token Claude Code keeps
in the login keychain and calls `GET /api/oauth/usage`, which is where Claude's own
`/usage` gets its numbers. That is not a published API — it can change without
notice — so the response shape is pinned by tests and every failure degrades to a
visible status (`stale`, `needsAuth`, `error`) rather than to a made-up percentage.

The local session files under `~/.claude/projects` were the original plan. They hold
token counts but no limits and no window metadata, so a percentage from them needs an
invented denominator. They remain the `.derived` fallback if the endpoint disappears.

**Keychain:** the grant is remembered against the binary's signature, so the
build has to be signed with a stable certificate — see *Building it yourself*.

**Rate limits:** the endpoint returns 429 if polled too hard, and answers
`Retry-After: 0` when it does. The back-off treats that hint as a floor-raiser
only — 60s, doubling per consecutive 429, capped at 15 minutes. The last good
reading is kept across launches, so a refused fetch shows dated numbers rather
than nothing; the ring dims and the tooltip header says how old they are. The
back-off deadline is persisted too, so relaunching during a penalty waits instead
of spending an attempt on it. Polling drops to every 5 minutes when no session is
running, and right-clicking the notch offers **Refresh now**.

**Logs:** the app can be run with no window of its own, so anything worth
diagnosing goes to the unified log.

```sh
/usr/bin/log stream --predicate 'subsystem == "com.vinz.codenotch"' --level debug
```
