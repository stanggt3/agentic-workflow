#!/usr/bin/env bash
# SessionStart hook: Inject current repo's memory graph context
# Outputs JSON with additionalContext for Claude Code 2.1.85+.
# Silently outputs empty context if bridge is unreachable or context is empty.
# Note: set -euo pipefail intentionally omitted — must always exit 0.

# Derive repo slug (same pattern used in skills)
REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")
if [ -n "$REMOTE_URL" ]; then
  REPO_SLUG=$(echo "$REMOTE_URL" | sed 's|.*[:/]\([^/]*/[^/]*\)\.git$|\1|;s|.*[:/]\([^/]*/[^/]*\)$|\1|' | tr '/' '-')
else
  REPO_SLUG=$(basename "$(pwd)" 2>/dev/null || echo "unknown")
fi

# Check bridge health — silent exit if unreachable
if ! curl -sf --max-time 2 "http://localhost:3100/health" >/dev/null 2>&1; then
  exit 0
fi

# Query token-budgeted context from the memory graph
RESPONSE=$(curl -sf --max-time 5 \
  "http://localhost:3100/memory/context?query=recent+decisions+tasks+topics&repo=${REPO_SLUG}&max_tokens=800&agent=session-start" \
  2>/dev/null) || exit 0

[ -z "$RESPONSE" ] && exit 0

# Use Python (always available) to parse JSON and format sections
CONTEXT=$(python3 -c "
import sys, json
try:
    data = json.loads(sys.stdin.read())
    if not data.get('ok'):
        sys.exit(0)
    sections = data.get('data', {}).get('sections', [])
    if not sections:
        sys.exit(0)
    lines = ['=== Project Memory ===']
    for s in sections:
        heading = s.get('heading', '')
        content = (s.get('content') or '').split('\n')[0]
        lines.append(f'[{heading}] {content}')
    print('\n'.join(lines))
except Exception:
    sys.exit(0)
" <<< "$RESPONSE" 2>/dev/null) || exit 0

[ -z "$CONTEXT" ] && exit 0

# Escape for JSON
ESCAPED=$(printf '%s' "$CONTEXT" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' '\001' | sed 's/\x01/\\n/g')

printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}' "$ESCAPED"
