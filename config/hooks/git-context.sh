#!/usr/bin/env bash
# SessionStart hook: Inject recent git context
# Outputs JSON with additionalContext for Claude Code 2.1.85+.
# Note: set -euo pipefail intentionally omitted — this hook is informational only
# and must always exit 0 even when run outside a git repository.

BRANCH=$(git branch --show-current 2>/dev/null || echo "(detached)")

COMMITS=$(git log --oneline -5 2>/dev/null || echo "(no commits)")

STATUS=$(git status --short 2>/dev/null || echo "(not a git repo)")

CONTEXT="=== Git Context ===
Branch: $BRANCH

Recent commits:
$COMMITS

Working tree status:
$STATUS"

# Escape the context string for JSON (replace \ with \\, " with \", newlines with \n)
ESCAPED=$(printf '%s' "$CONTEXT" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' '\001' | sed 's/\x01/\\n/g')

printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}' "$ESCAPED"
