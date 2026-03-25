# Design: Memory Recall + Sub-skill Dispatch

**Date:** 2026-03-24
**Status:** Approved
**Scope:** `skills/_preamble.md`, 12 SKILL.md exception files, 4 orchestrator skills, 2 subagent prompt templates

---

## Problem

Skills don't prompt agents to retrieve prior conversation context from the agentic-bridge memory graph. When a session compacts or a new session begins, agents start fresh — even when prior discussions about the same problem space exist in memory. Additionally, the natural chains between skills (rootCause → bugHunt, officeHours → archReview, etc.) are not encoded, so agents never flow between skills without manual user prompting.

---

## Solution Overview

1. **Preamble `## Memory Recall` block** — added to `_preamble.md`, runs on all 22 non-excepted skills before codebase reads
2. **SKIP markers** — 12 mechanical/dispatcher/visual-diff skills opt out via `<!-- MEMORY: SKIP -->`
3. **Orchestrator trigger tables (A)** — 4 skills get explicit "Sub-skill Dispatch" sections
4. **Subagent prompt updates (B)** — `reviewer-prompt.md` and `implementer-prompt.md` get skill dispatch and memory recall steps

---

## Section 1: Preamble Memory Recall Block

**Placement:** After the Codebase Navigation table, before `## Preamble — Bootstrap Check`.

**Query strategy:** Topic-derived (agent synthesizes 3–5 words from argument + task intent).
**Tools:** `search_memory` (hybrid, limit 10) → `get_context` (token_budget 2000), run sequentially.
**Output:** Surface a `> **Prior context:** {summary}` callout if `relevance > 0.3`; continue silently otherwise.

```markdown
## Memory Recall

> **Skip if** this skill is marked `<!-- MEMORY: SKIP -->`.

Before reading the codebase, check for prior discussion context in memory.

**1. Derive a topic string** — synthesize 3–5 words from the skill argument and task intent:
- `/officeHours add dark mode` → `"dark mode UI feature"`
- `/rootCause TypeError cannot read properties` → `"TypeError cannot read properties"`
- `/review 42` → use the PR title once fetched: `"PR {title} review"`
- No argument → use the most specific descriptor available: `"{REPO_SLUG} {skill-name}"`

**2. Search memory:**
```
mcp__agentic-bridge__search_memory — query: <topic>, repo: REPO_SLUG, mode: "hybrid", limit: 10
```

**3. Assemble context:**
```
mcp__agentic-bridge__get_context — query: <topic>, repo: REPO_SLUG, token_budget: 2000
```

**4. Surface results:**
- If `get_context` returns a non-empty summary or any section with `relevance > 0.3`:
  > **Prior context:** {summary} *(~{token_estimate} tokens)*
  Use this to inform your approach before continuing.
- If empty or all low-relevance: continue silently — do not mention the search.
```

---

## Section 2: Exception List

12 of 34 skills receive `<!-- MEMORY: SKIP -->` in their frontmatter comment block.

### Dispatcher shells
Detect platform and re-invoke a sub-skill; the sub-skill does its own recall.

| Skill |
|-------|
| `/design-analyze` |
| `/design-mockup` |
| `/design-implement` |
| `/design-evolve` |
| `/design-verify` |
| `/verify-app` |

### Mechanical pipeline
No discussion phase; context retrieval adds no value.

| Skill |
|-------|
| `/shipRelease` |
| `/syncDocs` |
| `/postReview` |
| `/design-refine` |

### Visual diff
Pixel-level comparison, not discussion-driven.

| Skill |
|-------|
| `/design-verify-web` |
| `/design-verify-ios` |

---

## Section 3: Orchestrator Sub-skill Dispatch (A)

Four skills get a `### Sub-skill Dispatch` section at the natural "what next?" moment.

### `/rootCause` — after Phase 4 (fix verified)

```markdown
### Sub-skill Dispatch

If the fix was verified successfully, invoke bugHunt to write regression tests:
> Skill tool: `bugHunt`, args: `"<error slug from Step 1>"`
```

### `/bugHunt` — after fix-and-verify loop completes

```markdown
### Sub-skill Dispatch

Invoke bugReport to generate a structured report:
> Skill tool: `bugReport`
```

### `/officeHours` — after the design doc is written (final step)

```markdown
### Sub-skill Dispatch

> "Plan is ready. Would you like a review?"
> - Architectural concerns → Skill tool: `archReview`
> - Product/founder lens → Skill tool: `productReview`
> - Both → invoke both in sequence
> - Neither → done
```

### `/review` — after collecting reviewer outputs, before writing the state file

```markdown
### Sub-skill Dispatch

For any issue with `severity: "blocking"` that contains a clear error message or stack trace:
> Skill tool: `rootCause`, args: `"<error description>"`

Attach the investigation file path to that issue's entry in the state file under `"investigation"`.
```

---

## Section 4: Subagent Prompt Updates (B)

### `skills/review/reviewer-prompt.md` — new Step 4

Added after the Analyze section, before the Output Format section.

```markdown
### 4. Sub-skill dispatch

If you find a `blocking`-severity issue containing a clear error message or stack trace,
invoke rootCause to investigate before returning your findings:

> Skill tool: `rootCause`, args: `"<error message>"`

If you invoke it, include the path to the investigation file in your JSON output:

```json
"investigation": "~/.agentic-workflow/<repo-slug>/investigations/<filename>.md"
```

If no blocking bugs with error traces are found, omit the `investigation` key entirely.
```

### `skills/addressReview/implementer-prompt.md` — new Step 0

Added before Step 1 (reading the PR).

```markdown
### 0. Check memory for prior context

Before reading the PR, search for prior discussions about the files or issues you're about to address:

```
mcp__agentic-bridge__search_memory — query: "<issue summary>", repo: <derive from `git remote get-url origin`>, mode: "hybrid", limit: 5
```

Use any relevant prior context to inform your implementation approach. Continue silently if nothing relevant is found.
```

---

## Files Changed

| File | Change |
|------|--------|
| `skills/_preamble.md` | Add `## Memory Recall` section |
| `skills/design-analyze/SKILL.md` | Add `<!-- MEMORY: SKIP -->` |
| `skills/design-mockup/SKILL.md` | Add `<!-- MEMORY: SKIP -->` |
| `skills/design-implement/SKILL.md` | Add `<!-- MEMORY: SKIP -->` |
| `skills/design-evolve/SKILL.md` | Add `<!-- MEMORY: SKIP -->` |
| `skills/design-verify/SKILL.md` | Add `<!-- MEMORY: SKIP -->` |
| `skills/verify-app/SKILL.md` | Add `<!-- MEMORY: SKIP -->` |
| `skills/shipRelease/SKILL.md` | Add `<!-- MEMORY: SKIP -->` |
| `skills/syncDocs/SKILL.md` | Add `<!-- MEMORY: SKIP -->` |
| `skills/postReview/SKILL.md` | Add `<!-- MEMORY: SKIP -->` |
| `skills/design-refine/SKILL.md` | Add `<!-- MEMORY: SKIP -->` |
| `skills/design-verify-web/SKILL.md` | Add `<!-- MEMORY: SKIP -->` |
| `skills/design-verify-ios/SKILL.md` | Add `<!-- MEMORY: SKIP -->` |
| All 34 SKILL.md files (non-SKIP) | Propagate updated preamble with Memory Recall block |
| `skills/rootCause/SKILL.md` | Add `### Sub-skill Dispatch` section |
| `skills/bugHunt/SKILL.md` | Add `### Sub-skill Dispatch` section |
| `skills/officeHours/SKILL.md` | Add `### Sub-skill Dispatch` section |
| `skills/review/SKILL.md` | Add `### Sub-skill Dispatch` section |
| `skills/review/reviewer-prompt.md` | Add Step 4: Sub-skill dispatch |
| `skills/addressReview/implementer-prompt.md` | Add Step 0: Memory check |
