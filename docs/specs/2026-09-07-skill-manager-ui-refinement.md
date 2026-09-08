# Skill Manager UI refinement

## Constraints

Keep the native SwiftUI panel, Settings / Skills / Projects tabs, Skills card
grid, and Projects sidebar with a detail form. Reuse the existing model and
filesystem operations. This change does not migrate storage, change agent
discovery, or implement new mount behavior.

## Independent dimensions

- **Category**: Library contains the existing managed catalog; Agent-only
  contains skills discovered in an agent's own directory. The detail shows the
  actual source path, including legacy global folders and registered origins.
- **Scope**: global, linked to projects, or no shared scope. A particular
  project filter uses effective reach, including global inheritance and local
  overrides. Global skills can retain explicit project links.
- **Tags**: searchable metadata independent of category and scope. Personal
  tags remain in the existing Codenotch preferences; declared tags remain in
  SKILL.md. Their existing storage and identity rules are unchanged.

The implementation uses the existing `.agents/skills` paths (plural), both
under the home directory and under each project.

## Skills

Search, category, scope, and tag selection compose. Selected tags match all
selected values; a #tag search requires an exact tag. Ordinary search words
match names, descriptions, or tags using localized matching. Applied tags are
visible and removable; empty results offer Clear filters.

Cards retain their original layout. The details area is now a native Button,
tags filter independently, and the global switch has an explicit label.
Project scope shows a project name or count. “No shared scope” deliberately
does not claim that an agent-specific link cannot still reach the skill.

Details distinguish category, actual path, personal/declared tags, global
scope, and registered projects. An inherited global state is a label; a local
selection is a switch; an override offers Reveal conflict. Agent-only adoption
opens a detail review, and a successful adoption continues to the Library
detail. Existing adoption semantics are retained.

## Projects

The existing sidebar gains project search. The detail retains its project
identity and actions and adds skill search, tags, and All / Active & local
filters. Skills are grouped into project-enabled, globally inherited, local,
overrides, and available from Library. The same scope control is reused in
both the project page and skill detail. Library skill rows open their details
without leaving Projects. Instructions and agent compatibility remain under
an expandable Agent setup section.

## Validation

- `make build` passed.
- Final `make test`: 562 tests passed, zero failures, including eight new
  deterministic filtering tests for exact tags, combined filters, localized
  text, global inheritance, retained project links, and overrides.
- Actual native window checks: Skills and Agent-only card grids, tag click
  filtering, searchable tag popover, empty search results, Agent-only details,
  project grouping, and opening global skill details from a project.
- The new UI retains system appearance and respects Reduce Motion for card
  hover animation. Native buttons and scope controls have accessibility names.
- Live filesystem-changing actions were not exercised during visual QA.
  Existing filesystem behavior is covered by the repository's fixture tests.
- Existing Swift concurrency warnings in providers and filesystem models
  remain outside this UI-only change.
