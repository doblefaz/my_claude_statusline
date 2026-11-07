# my_claude_statusline

My custom status line for [Claude Code](https://claude.com/claude-code).

## What it shows

First, one line per working directory (the current one and any added ones) with its git branch:

```
 • ~/projects/app (main)
 • ~/other-dir (no git)
```

Then a summary line with:

| Segment | Content |
|---|---|
| Model | Name and effort level, if the model supports it |
| Context | % used and tokens (`39% (78k/200k)`) |
| 5-hour limit | % consumed and reset time |
| 7-day limit | % consumed and reset date/time |
| RAM | % used (`39% (6.0G/15.4G)`) |
| CPU | Temperature; green < 70°, yellow 70–84°, red ≥ 85° |

Context and rate-limit data only appear inside a Claude Code session.

## Requirements

- Linux (reads `/proc/meminfo` and `/sys/class/thermal`)
- `bash`, `jq`, `awk`, `git`

## Installation

```bash
git clone <repo-url> my_claude_statusline
cd my_claude_statusline
./install.sh          # copy the script
./install.sh --link   # or symlink it to the repo, so `git pull` updates it
```

The installer copies `statusline-command.sh` to `~/.claude/` and sets the
`statusLine` key in `~/.claude/settings.json`. Restart Claude Code afterwards.

Safety behavior:

- If `statusLine` is missing, it is added.
- If it is already identical, `settings.json` is left untouched.
- If a different one exists, it is shown and you are asked to confirm
  (`--force` overwrites without asking; non-interactive runs require `--force`).
- Before any change to `settings.json`, a timestamped backup
  (`settings.json.bak.YYYYMMDD-HHMMSS`) is created. Other settings are never touched.
- Invalid JSON in `settings.json` aborts the install without changing anything.

### Manual installation

1. Copy `statusline-command.sh` to `~/.claude/` and make it executable.
2. Add to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline-command.sh",
    "refreshInterval": 10
  }
}
```
