#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing: $1" >&2; exit 1; }; }
need git
need jq
command -v bun >/dev/null 2>&1 || echo "warn: bun not found — gstack setup may fail. Install: https://bun.sh"

echo "==> 1. Install / update gstack"
mkdir -p ~/.claude/skills
if [ -d ~/.claude/skills/gstack/.git ]; then
  # Use fetch + reset --hard so previous prunes (e.g. deleted bare SKILL.md)
  # don't block the update. ~/.claude/skills/gstack is a vendor checkout, not
  # a working tree we edit by hand.
  (cd ~/.claude/skills/gstack && git fetch --depth 1 origin main && git reset --hard origin/main)
else
  git clone --depth 1 https://github.com/garrytan/gstack.git ~/.claude/skills/gstack
fi
(cd ~/.claude/skills/gstack && ./setup)

echo "==> 2. Configure gstack (prefix=on, proactive=off, terse, telemetry=off)"
GS=~/.claude/skills/gstack/bin
"$GS/gstack-config" set skill_prefix true
"$GS/gstack-config" set proactive false
"$GS/gstack-config" set explain_level terse
"$GS/gstack-config" set telemetry off || true

echo "==> 3. Install / update turbo"
mkdir -p ~/.turbo
if [ -d ~/.turbo/repo/.git ]; then
  (cd ~/.turbo/repo && git pull --ff-only)
else
  git clone https://github.com/tobihagemann/turbo.git ~/.turbo/repo
fi

if [ ! -f ~/.turbo/config.json ]; then
  cp "$REPO_DIR/turbo.config.json" ~/.turbo/config.json
fi

echo "==> 4. Sync turbo skills into ~/.claude/skills (honoring excludeSkills)"

# Refresh ~/.turbo/config.json: lastUpdateHead + configVersion (latest from MIGRATION.md).
# Clone mode also auto-adds contribute-turbo to excludeSkills since it requires
# fork/source access. Idempotent across re-runs.
HEAD_SHA=$(git -C ~/.turbo/repo rev-parse HEAD)
CONFIG_VERSION=$(grep -oE '^## Version [0-9]+' ~/.turbo/repo/MIGRATION.md | grep -oE '[0-9]+' | sort -n | tail -1)
REPO_MODE=$(jq -r '.repoMode // "clone"' ~/.turbo/config.json)
tmp=$(mktemp)
if [ "$REPO_MODE" = "clone" ]; then
  jq --arg sha "$HEAD_SHA" --argjson ver "${CONFIG_VERSION:-2}" '
    .lastUpdateHead = $sha
    | .configVersion = $ver
    | .excludeSkills = ((.excludeSkills // []) + ["contribute-turbo"] | unique)
  ' ~/.turbo/config.json > "$tmp" && mv "$tmp" ~/.turbo/config.json
else
  jq --arg sha "$HEAD_SHA" --argjson ver "${CONFIG_VERSION:-2}" '
    .lastUpdateHead = $sha
    | .configVersion = $ver
  ' ~/.turbo/config.json > "$tmp" && mv "$tmp" ~/.turbo/config.json
fi

EXCLUDED=$(jq -r '.excludeSkills[]?' ~/.turbo/config.json 2>/dev/null | paste -sd '|' -)
for skill_dir in ~/.turbo/repo/skills/*/; do
  skill=$(basename "$skill_dir")
  if [ -n "$EXCLUDED" ] && echo "$skill" | grep -qE "^($EXCLUDED)$"; then
    echo "    skip $skill (excluded)"
    continue
  fi
  rm -rf "$HOME/.claude/skills/$skill"
  cp -r "$skill_dir" "$HOME/.claude/skills/$skill"
done

echo "==> 5. Ensure agent-browser is installed (turbo's preferred browser skill)"
# turbo's smoke-test / exploratory-test / design-review prefer agent-browser over
# the claude-in-chrome MCP fallback. Idempotent: skip if already on disk.
if [ -d "$HOME/.claude/skills/agent-browser" ]; then
  echo "    agent-browser already present"
else
  if command -v npx >/dev/null 2>&1; then
    npx -y skills add https://github.com/vercel-labs/agent-browser \
      --skill agent-browser --agent claude-code -y -g 2>&1 | tail -5 \
      || echo "    WARN: agent-browser install failed — install manually if you want browser skills"
  else
    echo "    WARN: npx not found — skip agent-browser. Install Node.js, then re-run."
  fi
fi

echo "==> 6. Add .turbo/ to global gitignore"
# turbo skills write plans/specs/improvements into each repo's .turbo/ dir.
# Without ignoring, every project surfaces them as untracked changes.
GIT_IGNORE_FILE="$HOME/.config/git/ignore"
GIT_CUSTOM=$(git config --global core.excludesfile 2>/dev/null || true)
if [ -n "$GIT_CUSTOM" ]; then
  GIT_IGNORE_FILE="${GIT_CUSTOM/#\~/$HOME}"
fi
mkdir -p "$(dirname "$GIT_IGNORE_FILE")"
touch "$GIT_IGNORE_FILE"
if grep -qxE '\.turbo/?' "$GIT_IGNORE_FILE"; then
  echo "    .turbo/ already in $GIT_IGNORE_FILE"
else
  echo '.turbo/' >> "$GIT_IGNORE_FILE"
  echo "    added .turbo/ to $GIT_IGNORE_FILE"
fi

echo "==> 7. Install custom skills from this repo (if any)"
if [ -d "$REPO_DIR/skills" ] && [ -n "$(ls -A "$REPO_DIR/skills" 2>/dev/null)" ]; then
  for skill_dir in "$REPO_DIR/skills"/*/; do
    [ -d "$skill_dir" ] || continue
    skill=$(basename "$skill_dir")
    rm -rf "$HOME/.claude/skills/$skill"
    cp -r "$skill_dir" "$HOME/.claude/skills/$skill"
    echo "    + $skill"
  done
fi

echo "==> 8. Prune gstack registrations to keep-list"
KEEP_FILE="$REPO_DIR/gstack-keep.txt"
if [ -f "$KEEP_FILE" ]; then
  KEEP_LINES=$(grep -vE '^\s*(#|$)' "$KEEP_FILE" || true)
  if [ -n "$KEEP_LINES" ]; then
    KEEP_PATTERN=$(echo "$KEEP_LINES" | paste -sd '|' -)
    # 6a. Prune gstack-* wrappers
    pruned=0; kept=0
    for d in "$HOME/.claude/skills"/gstack-*; do
      [ -d "$d" ] || continue
      name=$(basename "$d")
      if echo "$name" | grep -qE "^($KEEP_PATTERN)$"; then
        kept=$((kept + 1))
      else
        rm -rf "$d"
        pruned=$((pruned + 1))
      fi
    done
    echo "    wrappers: pruned $pruned, kept $kept"
    # 6b. Bare gstack skill (~/.claude/skills/gstack/SKILL.md is the browse skill)
    BARE_SKILL="$HOME/.claude/skills/gstack/SKILL.md"
    if echo "gstack" | grep -qE "^($KEEP_PATTERN)$"; then
      [ -f "$BARE_SKILL" ] && echo "    bare gstack skill: kept (in keep-list)"
    else
      if [ -f "$BARE_SKILL" ]; then
        rm -f "$BARE_SKILL"
        echo "    bare gstack skill: removed (browse skill unregistered)"
      fi
    fi
    # 6c. Defensive: ensure gstack didn't write SessionStart hooks into settings.json
    if [ -f "$HOME/.claude/settings.json" ] && grep -q "gstack" "$HOME/.claude/settings.json" 2>/dev/null; then
      echo "    WARN: ~/.claude/settings.json contains gstack reference — review with: grep gstack ~/.claude/settings.json"
    fi
  else
    echo "    keep-list empty — keeping all gstack wrappers and bare skill"
  fi
else
  echo "    no gstack-keep.txt — keeping all gstack wrappers and bare skill"
fi
echo "    (gstack source intact at ~/.claude/skills/gstack/)"

echo "==> 9. Append turbo CLAUDE-ADDITIONS to ~/.claude/CLAUDE.md (idempotent)"
TARGET="$HOME/.claude/CLAUDE.md"
SRC="$HOME/.turbo/repo/CLAUDE-ADDITIONS.md"
MARK_START="<!-- turbo:claude-additions:start -->"
MARK_END="<!-- turbo:claude-additions:end -->"
mkdir -p "$HOME/.claude"
touch "$TARGET"
# Strip any existing block first (delete lines between markers, inclusive)
if grep -qF "$MARK_START" "$TARGET"; then
  awk -v s="$MARK_START" -v e="$MARK_END" '
    $0 == s { skip=1; next }
    $0 == e && skip { skip=0; next }
    !skip { print }
  ' "$TARGET" > "$TARGET.tmp" && mv "$TARGET.tmp" "$TARGET"
fi
# Append fresh block. awk demotes ## → # and skips the file's preamble.
{
  echo ""
  echo "$MARK_START"
  awk '/^## /{flag=1} flag{sub(/^## /,"# "); print}' "$SRC"
  echo "$MARK_END"
} >> "$TARGET"
echo "    wrote turbo block to $TARGET"

echo
echo "Done."
echo "Re-run this script anytime to pull latest gstack + turbo, re-sync skills, and re-prune."
