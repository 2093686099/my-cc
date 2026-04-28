#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Mirrors install.sh — removes everything install.sh adds, in dependency-safe order.
# Surgical: only touches things install.sh installs. Won't delete unrelated skills
# you put under ~/.claude/skills/ yourself.

cat <<EOF
This will remove from your machine:
  ~/.claude/skills/gstack/             gstack source repo
  ~/.claude/skills/gstack-*            gstack keep-list symlinks
  ~/.claude/skills/<turbo skill>       all skills installed from ~/.turbo/repo/skills/
  ~/.claude/skills/<custom>            skills from this repo's skills/ (e.g. old-code)
  ~/.gstack/                           gstack runtime state (projects, sessions)
  ~/.turbo/                            turbo workspace + config
  .turbo/  line in ~/.config/git/ignore (or core.excludesfile path)
  turbo block in ~/.claude/CLAUDE.md   (between turbo:claude-additions markers)

It will NOT touch:
  ~/.claude/settings.json, ~/.claude/skills/<your other skills>, your shell rc files.

EOF

if [ "${1-}" != "-y" ] && [ "${1-}" != "--yes" ]; then
  printf "Continue? [y/N] "
  read -r ans
  case "$ans" in
    y|Y|yes|YES) ;;
    *) echo "Aborted."; exit 0 ;;
  esac
fi

echo "==> 1. Strip turbo block from ~/.claude/CLAUDE.md"
TARGET="$HOME/.claude/CLAUDE.md"
MARK_START="<!-- turbo:claude-additions:start -->"
MARK_END="<!-- turbo:claude-additions:end -->"
if [ -f "$TARGET" ] && grep -qF "$MARK_START" "$TARGET"; then
  awk -v s="$MARK_START" -v e="$MARK_END" '
    $0 == s { skip=1; next }
    $0 == e && skip { skip=0; next }
    !skip { print }
  ' "$TARGET" > "$TARGET.tmp" && mv "$TARGET.tmp" "$TARGET"
  echo "    stripped from $TARGET"
else
  echo "    no turbo block in $TARGET, skipping"
fi

echo "==> 2. Remove .turbo/ from global gitignore"
GIT_IGNORE_FILE="$HOME/.config/git/ignore"
GIT_CUSTOM=$(git config --global core.excludesfile 2>/dev/null || true)
if [ -n "$GIT_CUSTOM" ]; then
  GIT_IGNORE_FILE="${GIT_CUSTOM/#\~/$HOME}"
fi
if [ -f "$GIT_IGNORE_FILE" ] && grep -qxE '\.turbo/?' "$GIT_IGNORE_FILE"; then
  # Use a portable sed approach (BSD + GNU sed compatible)
  awk '!/^\.turbo\/?$/' "$GIT_IGNORE_FILE" > "$GIT_IGNORE_FILE.tmp" && mv "$GIT_IGNORE_FILE.tmp" "$GIT_IGNORE_FILE"
  echo "    removed .turbo/ from $GIT_IGNORE_FILE"
else
  echo "    no .turbo/ entry in $GIT_IGNORE_FILE, skipping"
fi

echo "==> 3. Remove gstack symlinks (~/.claude/skills/gstack-*)"
shopt -s nullglob
for d in "$HOME/.claude/skills"/gstack-*; do
  rm -rf "$d"
done
shopt -u nullglob
echo "    done"

echo "==> 4. Remove this repo's custom skills"
if [ -d "$REPO_DIR/skills" ]; then
  for skill_dir in "$REPO_DIR/skills"/*/; do
    [ -d "$skill_dir" ] || continue
    skill=$(basename "$skill_dir")
    if [ -d "$HOME/.claude/skills/$skill" ]; then
      rm -rf "$HOME/.claude/skills/$skill"
      echo "    - $skill"
    fi
  done
else
  echo "    (no skills/ dir in repo, skipping)"
fi

echo "==> 5. Remove turbo skills from ~/.claude/skills/"
# Must run before step 6 — needs ~/.turbo/repo/skills/ to enumerate names.
if [ -d "$HOME/.turbo/repo/skills" ]; then
  count=0
  for skill_dir in "$HOME/.turbo/repo/skills"/*/; do
    skill=$(basename "$skill_dir")
    if [ -d "$HOME/.claude/skills/$skill" ]; then
      rm -rf "$HOME/.claude/skills/$skill"
      count=$((count + 1))
    fi
  done
  echo "    removed $count turbo skill(s)"
else
  echo "    (~/.turbo/repo/skills not found, skipping)"
fi

echo "==> 6. Remove turbo workspace (~/.turbo/)"
rm -rf "$HOME/.turbo"
echo "    done"

echo "==> 7. Remove gstack source (~/.claude/skills/gstack/)"
rm -rf "$HOME/.claude/skills/gstack"
echo "    done"

echo "==> 8. Remove gstack runtime state (~/.gstack/)"
rm -rf "$HOME/.gstack"
echo "    done"

echo
echo "Done. To reinstall: ./install.sh"
echo "Note: Claude Code, gh, codex, agent-browser, claude-hud and any Playwright"
echo "      cache that may exist outside this scope were not touched."
