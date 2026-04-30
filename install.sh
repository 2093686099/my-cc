#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing: $1" >&2; exit 1; }; }
need git
need jq
# bun used to be required for gstack ./setup, but we now skip ./setup entirely
# (see step 1). gstack's runtime bin/ scripts are all pure bash.

echo "==> 1. Install / update gstack source (without ./setup)"
# We deliberately skip gstack's ./setup because it hard-installs Playwright
# Chromium (~500MB) + builds a 90MB browse binary, both only needed for
# /browse /qa /design-review skills — all pruned by gstack-keep.txt.
# Step 7 below replicates the only two pieces of ./setup we need: name:
# field patching for the gstack- prefix, and SKILL.md symlink creation.
# Caveat: running /gstack-upgrade will re-run ./setup and reinstall Playwright.
# Use this script (./install.sh) to update gstack instead.
mkdir -p ~/.claude/skills
if [ -d ~/.claude/skills/gstack/.git ]; then
  (cd ~/.claude/skills/gstack && git fetch --depth 1 origin main && git reset --hard origin/main)
else
  git clone --depth 1 https://github.com/garrytan/gstack.git ~/.claude/skills/gstack
fi
mkdir -p ~/.gstack/projects

echo "==> 2. Configure gstack (prefix=on, proactive=off, terse, telemetry=off)"
GS=~/.claude/skills/gstack/bin
# GSTACK_SETUP_RUNNING=1 suppresses gstack-config's post-set relink hook.
# Otherwise `set skill_prefix true` triggers gstack-relink which creates all
# 42 wrappers in ~/.claude/skills/ — step 7 below would sweep + rebuild from
# keep-list, but no point doing the work twice.
export GSTACK_SETUP_RUNNING=1
"$GS/gstack-config" set skill_prefix true
"$GS/gstack-config" set proactive false
"$GS/gstack-config" set explain_level terse
"$GS/gstack-config" set telemetry off || true
unset GSTACK_SETUP_RUNNING

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

echo "==> 5. Add .turbo/ to global gitignore"
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

echo "==> 6. Install custom skills from this repo (if any)"
if [ -d "$REPO_DIR/skills" ] && [ -n "$(ls -A "$REPO_DIR/skills" 2>/dev/null)" ]; then
  for skill_dir in "$REPO_DIR/skills"/*/; do
    [ -d "$skill_dir" ] || continue
    skill=$(basename "$skill_dir")
    rm -rf "$HOME/.claude/skills/$skill"
    cp -r "$skill_dir" "$HOME/.claude/skills/$skill"
    echo "    + $skill"
  done
fi

echo "==> 7. Link gstack skills from keep-list (replaces gstack ./setup symlinking)"
KEEP_FILE="$REPO_DIR/gstack-keep.txt"
GSTACK_SRC="$HOME/.claude/skills/gstack"
SKILLS_DIR="$HOME/.claude/skills"

# Patch name: fields → gstack-<name> in source SKILL.md (mimics SKILL_PREFIX=true).
# git reset --hard in step 1 reverts upstream's flat names, so this re-applies
# the prefix every run. Pure bash, no Playwright/node deps.
"$GSTACK_SRC/bin/gstack-patch-names" "$GSTACK_SRC" true >/dev/null 2>&1 || true

# Sweep stale wrappers from previous runs / previous gstack ./setup invocations.
# We rebuild from the keep-list, so any gstack-* wrapper not in the list is stale.
for d in "$SKILLS_DIR"/gstack-*; do
  [ -d "$d" ] || continue
  rm -rf "$d"
done
# Also remove the bare /gstack browse skill if previously registered
[ -f "$GSTACK_SRC/SKILL.md" ] && rm -f "$GSTACK_SRC/SKILL.md"

if [ -f "$KEEP_FILE" ]; then
  KEEP_LINES=$(grep -vE '^\s*(#|$)' "$KEEP_FILE" || true)
  if [ -n "$KEEP_LINES" ]; then
    linked=0
    while IFS= read -r entry; do
      [ -n "$entry" ] || continue
      # Map keep-list name to source dir: try `gstack-foo → foo`, else literal
      stripped="${entry#gstack-}"
      if [ -f "$GSTACK_SRC/$stripped/SKILL.md" ]; then
        src_dir="$stripped"
      elif [ -f "$GSTACK_SRC/$entry/SKILL.md" ]; then
        src_dir="$entry"
      elif [ "$entry" = "gstack" ]; then
        echo "    skip 'gstack' bare skill — needs SKILL.md.tmpl rendering, not supported here"
        continue
      else
        echo "    WARN: keep-list entry '$entry' has no source dir, skipping"
        continue
      fi
      target="$SKILLS_DIR/$entry"
      mkdir -p "$target"
      ln -snf "$GSTACK_SRC/$src_dir/SKILL.md" "$target/SKILL.md"
      linked=$((linked + 1))
    done <<< "$KEEP_LINES"
    echo "    linked $linked gstack skill(s) from keep-list"
  else
    echo "    keep-list empty — no gstack skills linked"
  fi
else
  echo "    no gstack-keep.txt — no gstack skills linked"
fi

# Defensive: ensure gstack didn't write SessionStart hooks (safety guards do this).
# We never run ./setup so this should always be clean, but keep the check as a tripwire.
if [ -f "$HOME/.claude/settings.json" ] && grep -q "gstack" "$HOME/.claude/settings.json" 2>/dev/null; then
  echo "    WARN: ~/.claude/settings.json contains gstack reference — review with: grep gstack ~/.claude/settings.json"
fi
echo "    (gstack source intact at ~/.claude/skills/gstack/, no Playwright installed)"

echo "==> 8. Configure context-tracking statusLine (only if unset)"
# README §7: turbo workflows like /finalize burn context fast — knowing how much
# is left prevents mid-workflow compaction. Use //= so we never overwrite a
# fancier statusLine the user already has (e.g. claude-hud plugin).
SETTINGS="$HOME/.claude/settings.json"
mkdir -p "$HOME/.claude"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
tmp=$(mktemp)
jq '.statusLine //= {
  "type": "command",
  "command": "jq -r \"\\\"\\(.context_window.remaining_percentage | floor)% context left\\\"\""
}' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
if jq -e '.statusLine.command | test("remaining_percentage")' "$SETTINGS" >/dev/null; then
  echo "    installed default context-left statusLine"
else
  echo "    statusLine already set (kept existing)"
fi

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
echo "Re-run this script anytime to pull latest gstack + turbo and re-link skills."
