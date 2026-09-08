# Skill Manager — Design

Started: 2026-09-07

The second half of Codenotch. The notch answers *how much have I spent*; this
answers *do all my agents know the same things*.

## The problem

A skill is a folder with a `SKILL.md` in it, and five different coding agents on
this Mac will read one — Claude Code, Codex, Cursor, Grok and Antigravity. They
do not read the *same* folder. So a skill written once ends up copied three or
four times, the copies drift, and the only way to know which agent has which
version is to go and look.

## The premise

`~/.agents/skills` is the folder the ecosystem settled on, and **Codex, Cursor
and Grok already read it with no configuration.** That single fact decides the
whole design: if the library *is* that folder, then three of the five agents are
served by a skill merely existing in it, and only two need anything done.

Claude Code reads `~/.claude/skills` and Antigravity reads
`~/.gemini/config/skills`. Those two get a **symlink** pointing back at the
library. So there is one real copy of every skill, everywhere, always — edit it
once and every agent has the edit.

A private `~/.codenotch/skills` would have been tidier to own and would have
needed five links instead of two, for nothing in return.

## The rule

> A mount is a symlink into the library, and nothing else is ever removed.

Everything the app will and will not do falls out of that sentence.

- Mounting writes one symlink. It never copies, so there is nothing to drift.
- Unmounting removes that symlink, and *only* if it resolves inside the library.
- A real folder in an agent's directory is somebody's own work. It is reported
  as a conflict and left exactly where it is — the app will not mount over it
  and will not delete it.
- A symlink pointing somewhere else **that exists** is somebody's deliberate
  arrangement, very likely another tool's. Same treatment: reported, untouched.
- A symlink pointing at something that is **gone** is the exception, and getting
  this wrong was a real bug: three links in `~/.claude/skills` pointed into a
  `~/skills` folder that no longer existed, and calling them "not ours to
  remove" left the user with three broken skills and no way to fix them from
  here. A link into nothing is not an arrangement, it is debris — there is no
  content behind it to lose — so it reads as *broken*, says so plainly, and can
  be replaced by a link to the library.

This is also the interoperability contract with `yibie/skills-manager`, whose
TUI refuses to replace a link resolving into a managed root for the same reason.
The two can be run on the same machine without fighting.

Removal from the library goes to the **Trash**, never `rm`. A skill is prose
someone wrote, there is no other copy once the mounts are gone, and the Trash is
an undo that already exists on every Mac.

## Two kinds of skill

Reading the library and having a folder of your own are **different things**,
and the first version of this conflated them. It gave the three shared-library
agents no own-folder at all — and `~/.codex/skills` holds fifteen real skills
that belong to Codex alone. Every one of them was invisible, and the window
showed nothing to adopt.

So every agent has both:

- a **library** it may or may not read (`~/.agents/skills`), and
- an **own folder** it always has, holding skills that reach only it.

| Agent | Detected by | Own folder | Reads library |
|---|---|---|---|
| Claude Code | `~/.claude` | `~/.claude/skills` | no → link |
| Codex | `~/.codex` | `~/.codex/skills` | yes |
| Cursor | `~/.cursor` | `~/.cursor/skills` | yes |
| Grok | `~/.grok` | `~/.grok/skills` | yes |
| Antigravity | `~/.gemini` or `~/.antigravity` | `~/.gemini/config/skills` | no → link |

An agent-local skill can be **promoted**: the folder moves into the library and
a link goes back where it was, so the agent that had it keeps it and every other
agent gains it. That is the only way a skill becomes global.

Nothing is ever written into the own-folder of an agent that reads the library —
a skill mounted at `~/.codex/skills` *as well* would be the same skill twice, and
Codex would have to pick one.

## What is never shown

The vendors ship skills of their own, and there are about fifty of them:

| Folder | Count |
|---|---|
| `~/.codex/skills/.system` | 6 |
| `~/.cursor/skills-cursor` | 24 |
| `~/.grok/bundled/skills` | 26 |

They are read-only and they are not yours. There is nothing to be done to one,
so listing them would be fifty inert rows standing between you and your own.
They are never scanned, never offered and never displayed.

Five and not the reference project's forty. Every agent here is one the notch
already reads usage for, so both halves of the app know about the same set of
tools. An agent nobody runs is a row that can only ever say "Not installed".

Grok is the one this fork added — the reference detects forty agents and not
that one.

Antigravity's path is `~/.gemini/config/skills` and **not**
`~/.gemini/antigravity/skills`: the first is the one all three of its surfaces
read (IDE, CLI, agent), and the second has a known bug where symlinked skills are
never discovered — which is precisely what we put there.

The three that read the library are shown with a check and no switch. Saying
"nothing to do here" is more useful than a control that pretends to act; the
alternative was a toggle that did nothing, or a second copy under `~/.codex/skills`
that Codex would then have to choose between.

## Getting skills in

Promoting, and nothing else. No marketplace, no import-from-URL, no editing skill
text in the app.

The premise is that you already have skills, scattered across whichever agent you
set up first, and what you want is for them to be in one place and reach all of
them. So the app scans every installed agent's own folder and lists what it finds
under that agent's name.

Promoting **moves** the folder into the library and mounts it back where it came
from. One real folder afterwards, in the library; the agent that had it keeps it
through a link; every other agent gains it. Copy, verify, then trash the
original — in that order, so there is never a moment where the only copy is gone.

Two agents holding a `review` each are two folders that may hold different text.
They get a row apiece rather than being merged, and a name the library already
holds is flagged on the row so Promote can be disabled with a reason, instead of
offering a button that can only fail.

Links are never listed at all: a link into the library is already ours and
already managed, and a link elsewhere belongs to a setup that expects one copy.

## Reading a `SKILL.md`

The frontmatter is parsed by hand rather than with a YAML library — this project
has no package dependencies, and adding one to read two strings would be the tail
wagging the dog. It ignores anything richer than `key: value` rather than
mis-reading it.

It does have to understand **block scalars**, though, and not understanding them
was a bug: `description: >` puts the text on the following indented lines, and
reading that line as an ordinary value gives a description of exactly `>` —
which is what four of the skills on this machine displayed. Folded (`>`) joins
its lines with spaces, literal (`|`) keeps the newlines, a blank line is a
paragraph break, and the block ends where the indentation does so the key after
it is still read.

## The Integrations list

Read-only, deliberately. It carried a switch per provider plus "Open …",
"Switch…" and "Allow access…", every one of which acted on an account Codenotch
does not own — the reading is borrowed from a tool that already holds the login,
so the honest place to change any of it is that tool. With the set of agents
settled none of it was reached. What is left is the part that was actually being
read: whose account each number belongs to, and whether it is coming through.

## Project skills, and the inversion they force

Project skills were out of scope and are now the point. What changed is a
measurement: a real Codex session on this Mac carried **twenty-five skills and
21 KB of descriptions**, with Codex's own warning that it had already truncated
them to fit its skills budget. Every one of those was loaded because it existed,
not because the project wanted it.

That reverses the argument for the library's location. `~/.agents/skills` is the
perfect place to *distribute from* precisely because three agents read it with
no configuration — and that same fact makes it the worst possible place to
*rest* a skill that should reach one project. So there are now two roots:

- `~/.codenotch/skills` — **the quiet store, which no agent scans.** Every
  managed skill's real folder, global or not. A private directory was rejected
  for the global library above and is right here for exactly the reason it was
  wrong there: being a name only Codenotch knows is the entire point.
- `~/.agents/skills` — **loaded everywhere, always.** Not a second home: a
  *symlink* per globally-loaded skill, pointing back into the store. Codex was
  probed and follows one — it listed a skill whose only real copy was in
  `~/.codenotch/skills`.

The first design moved the folder between the two, and that was wrong three
ways. The real path changed under the user, so Finder and an editor went
somewhere different depending on a switch. Toggling twice looked like nothing
had happened, because it *was* nothing — with no visible path, an invisible
move and no move are the same picture. And a link somebody else had made into
`~/.agents/skills/<name>` broke silently the moment the folder left. Writing and
removing a link has none of those problems, and a skill's own text is never
touched by a decision about its reach.

One move survives, and it happens once per skill: a real folder that was in
`~/.agents/skills` before any of this existed is taken into the store the first
time it is switched off. Nothing else would work — leaving it there is exactly
the state being switched off.

Taking a skill in from an agent's own folder follows the same rule and leaves a
link where the skill was. Moving `~/.codex/skills/x` into the store with nothing
behind it is not taking a skill in, it is taking it away.

### What each agent actually reads, probed rather than assumed

Marker skills were planted in every candidate directory of a scratch project and
each tool was asked what it could see.

| | project `.agents/skills` | project instructions |
| --- | --- | --- |
| Codex | **yes** — its session log listed the marker | `AGENTS.md`, merged with `~/.codex/AGENTS.md` under `--- project-doc ---` |
| Cursor | **yes** — its bundle classifies a path starting `.agents/skills/` as `"workspace"` | `/AGENTS.md` at the workspace root |
| Antigravity | **yes** — its language server documents `<workspace>/.agents/skills/<name>/` | `AGENTS.md`, `GEMINI.md`, `.agents/rules/*.md` |
| Claude Code | **no** — reads `.claude/skills`, and *follows it through a symlink* | `CLAUDE.md` only |

Claude Code is the whole reason there is anything to install. The instructions
finding is the sharper of the two and was worth a controlled probe: with only
`AGENTS.md` present **and every tool disabled**, Claude Code could not answer a
question the file answers — it tried to `Read` the file instead, which says it
sees the *name* but does not get the *contents*. With `CLAUDE.md -> AGENTS.md`
in place and tools still disabled, it answered at once. The link is the
difference between "it might go and look" and "it already knows".

### What gets written into a project

```
项目/
├─ AGENTS.md              real file, committed
├─ CLAUDE.md      ─────→  AGENTS.md            relative link, committed
├─ .agents/skills/*       absolute links, .gitignore
└─ .claude/skills ─────→  ../.agents/skills    relative link, committed
```

The two link directions are opposite on purpose. A per-skill link has to leave
the project — into the store or into a checkout — and a relative path out of a
project depends on where the project sits; git stores a symlink as its target
string, so committing one hands everyone else a dead link. The two bridges never
leave the project, so relative is true wherever it is cloned, and both are worth
committing: one line in a repo and every teammate's Claude Code reads what the
other three already do.

### Rules carried over unchanged

A real folder or file is never replaced, a link pointing somewhere that exists is
somebody's arrangement, a link pointing at nothing is debris and may be replaced.
Two additions:

- **A skill that is a *subdirectory* of a checkout is never moved.** Pulling one
  folder out of somebody's repository detaches it from `git pull`, so the next
  version silently never arrives. It is linked where it lies.
  A skill that **is** the repository — its own folder holding the `.git` — moves
  freely: the checkout travels with it and `git pull` works just as well from
  the store. The first version of this rule refused both, which was wrong and
  wrong in the common case: a skill cloned straight into `~/.codex/skills/<name>`
  is its own repo by construction.
- **`AGENTS.md` and `CLAUDE.md` both real and different is reported, never
  merged.** Which set of instructions is right is not a thing to guess at.

Codenotch never writes an `AGENTS.md`. Instructions are prose somebody has to
mean.

## Scope

Skills and instructions, global and per-project. Memory is **not** in scope and
cannot be: each tool's memory is a private store in a private format — there is
no shared file to link. The one place all four read is `AGENTS.md`, which is
what the instructions bridge is for.

## Out

Discover/marketplace, description translation, git-backed version history,
folder or URL import, in-app editing, and per-tool memory.
