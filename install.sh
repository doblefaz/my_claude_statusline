#!/usr/bin/env bash
# Installs the Claude Code statusline into ~/.claude and registers it in settings.json.
#
# Usage: ./install.sh [--link] [--force] [-h|--help]
#   --link   symlink the script to this repo instead of copying it, so a
#            `git pull` updates the statusline without reinstalling.
#   --force  overwrite an existing, different `statusLine` without asking.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CLAUDE_DIR/settings.json"
TARGET="$CLAUDE_DIR/statusline-command.sh"
NEW_STATUSLINE='{"type":"command","command":"bash ~/.claude/statusline-command.sh","refreshInterval":10}'

link=0
force=0
for arg in "$@"; do
  case "$arg" in
    --link)  link=1 ;;
    --force) force=1 ;;
    -h|--help) sed -n '2,8p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $arg (see --help)" >&2; exit 2 ;;
  esac
done

command -v jq >/dev/null || { echo "Error: 'jq' is required (e.g. sudo dnf install jq)." >&2; exit 1; }

mkdir -p "$CLAUDE_DIR"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

# Validate settings.json before touching anything
if ! jq empty "$SETTINGS" 2>/dev/null; then
  echo "Error: $SETTINGS is not valid JSON. Fix it and run again; nothing was changed." >&2
  exit 1
fi

# Decide what to do with the existing statusLine key
current="$(jq -c '.statusLine // empty' "$SETTINGS")"
update_settings=1
if [ -z "$current" ]; then
  echo "No statusLine configured; adding it."
elif [ "$(jq -cS . <<<"$current")" = "$(jq -cS . <<<"$NEW_STATUSLINE")" ]; then
  echo "statusLine already configured identically; leaving settings.json untouched."
  update_settings=0
else
  echo "A different statusLine already exists in $SETTINGS:"
  jq . <<<"$current"
  if [ "$force" -ne 1 ]; then
    if [ ! -t 0 ]; then
      echo "Not running interactively; use --force to overwrite. Nothing was changed." >&2
      exit 1
    fi
    read -r -p "Overwrite it? [y/N] " answer
    case "$answer" in
      y|Y|yes|YES) ;;
      *) echo "Aborted; nothing was changed."; exit 1 ;;
    esac
  fi
fi

# Script
if [ "$link" -eq 1 ]; then
  ln -sf "$REPO_DIR/statusline-command.sh" "$TARGET"
  echo "Linked: $TARGET -> $REPO_DIR/statusline-command.sh"
else
  # Remove first so a previous symlink is not written through into the repo
  rm -f "$TARGET"
  install -m 755 "$REPO_DIR/statusline-command.sh" "$TARGET"
  echo "Copied: $TARGET"
fi

# settings.json: set only the statusLine key, with a timestamped backup
if [ "$update_settings" -eq 1 ]; then
  backup="$SETTINGS.bak.$(date +%Y%m%d-%H%M%S)"
  cp "$SETTINGS" "$backup"
  tmp="$(mktemp)"
  jq --argjson sl "$NEW_STATUSLINE" '.statusLine = $sl' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
  echo "Updated: $SETTINGS (backup: $backup)"
fi
echo "Restart Claude Code to see the statusline."
