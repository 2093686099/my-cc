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
  (cd ~/.claude/skills/gstack && git pull --ff-only)
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

HEAD_SHA=$(git -C ~/.turbo/repo rev-parse HEAD)
tmp=$(mktemp)
jq --arg sha "$HEAD_SHA" '.lastUpdateHead = $sha' ~/.turbo/config.json > "$tmp" && mv "$tmp" ~/.turbo/config.json

echo "==> 5. Install custom skills from this repo (if any)"
if [ -d "$REPO_DIR/skills" ] && [ -n "$(ls -A "$REPO_DIR/skills" 2>/dev/null)" ]; then
  for skill_dir in "$REPO_DIR/skills"/*/; do
    [ -d "$skill_dir" ] || continue
    skill=$(basename "$skill_dir")
    rm -rf "$HOME/.claude/skills/$skill"
    cp -r "$skill_dir" "$HOME/.claude/skills/$skill"
    echo "    + $skill"
  done
fi

echo
echo "Done."
echo "Re-run this script anytime to pull latest gstack + turbo and re-sync skills."
