# The texturiser

Two Claude Code hooks that carry the feel of a collaboration from one session to the next. The why, and the story of the race condition, are in the post: [The texturiser](https://timwrites.dev/posts/texturiser/).

When a session ends, the conversation is folded into a small file, `~/.claude/texture.md`, by a headless `claude -p` call. When the next session starts, that file is printed into its context.

## What you need

- Windows. The scripts use a hidden window, a `Local\` mutex and `$env:USERPROFILE`. The approach ports; the scripts as written don't.
- PowerShell 7 (`pwsh`) on your `PATH`.
- The `claude` CLI on your `PATH`.

## Setup

1. Copy `inject-texture.ps1` and `texturise.ps1` into `~/.claude/hooks/`.
2. Copy `texture-prompt.md` and `texturise-nohooks.settings.json` into `~/.claude/`.
3. Merge the two entries in `settings.hooks.json` into the `hooks` object of your `~/.claude/settings.json`.
4. Swap in your own name. It is `$UserName` at the top of both scripts, and "Tim" throughout `texture-prompt.md`, including the `TIM:` label in the Register section.
5. Check `$Model` at the top of `texturise.ps1` is a model your account can use.

End a session, give it a couple of minutes, and `~/.claude/texture.md` should exist. Start a new one and it opens with a continuity note.

To see what a fold would send without calling the model or writing anything, set `TEXTURISE_DRYRUN=1` and run `texturise.ps1 -PayloadFile <file>`, where the file holds the JSON a `SessionEnd` hook receives (`session_id`, `transcript_path`, `cwd`).

## What it creates

All under `~/.claude/`:

| Path | What |
| --- | --- |
| `texture.md` | The texture itself. Rewritten in full at every fold. |
| `texture-markers.json` | Per session, the timestamp of the last message folded. |
| `texture-history/` | The previous thirty versions of `texture.md`. |
| `texturise.log` | One line per fold, skip or failure. |

To remove it, delete the two hook entries from `settings.json`, then those four paths and the files you copied.

## Known limits

- **It stores personal context in plain text.** That is its job. The file stays on your machine, but every session reads it, so anything in it can surface in what a session writes.
- **It parses Claude Code's transcript files**, which are an internal format that can change in any release.
- **One session at a time is assumed.** The mutex stops two folds overwriting each other, but two live sessions can't see each other's changes.
- **Prompts with an image attached are skipped.** Only plain-text user messages count as typed turns.
- **A long session is truncated** to the last 60,000 characters of conversation. The log says when.
