# AGENTS.md

Companion code for the posts and project pages at [timwrites.dev](https://timwrites.dev). The site's source lives in a separate repo; this one holds what a reader would want to copy.

## Layout

```
posts/<slug>/       code behind a post
projects/<slug>/    code behind a project page
```

`<slug>` is the entry's slug on the site, so `posts/texturiser/` pairs with `https://timwrites.dev/posts/texturiser/`. One folder per entry, nothing shared between folders: a reader copies one folder and it works.

A folder that grows into something people would install or file issues against moves to its own repo. Leave a `README.md` behind pointing at it.

## This repo is public from the first commit

There is no private drafts remote here, unlike the site. Anything pushed is published. So:

- Nothing goes in until it passes the quality check below.
- No secrets, tokens, or connection strings. Not in code, not in comments, not in example output.
- No surname, no personal email, no machine-specific paths (`C:\Users\<name>`, home directories, drive letters). Use `$env:USERPROFILE`, `~`, or a variable at the top of the script.
- No employer code and no client names. Generalise anything drawn from paid work.
- No personal data as sample output: no real transcripts, no real `texture.md`, no logs. Write a made-up example if one is needed.

## Code

Clean, lean, minimal fuss. The reader came from a blog post and wants to see the idea working, not a framework.

- **The code matches the post.** If a script and its post disagree, one of them is wrong. Fix it and say which. Where the repo has deliberately moved on from the post, the folder's `README.md` says so.
- **Runnable as copied.** Settings a reader must change sit in variables at the top of the file, named for what they are. No editing in the middle of a function to make it work.
- **No dependencies the post isn't about.** Standard library and the tool the post covers. Ask before adding anything else.
- **Comments say why, never what.** A comment earns its place by naming the trap a line avoids or the reason for an odd choice. It doesn't narrate the next line, restate a name, or record the history of a change. If it would read the same with the code deleted, cut it.
- **Fail loudly, unless failing quietly is the point.** A hook that must never block a session can swallow an error, but the comment beside it says why.
- **No cleverness for its own sake.** A longer obvious version beats a shorter cryptic one.
- **Match the file you're in.** Naming, layout and idiom follow what's already there.

## Every folder has a `README.md`

Short, and in this order:

1. One line on what it is, and a link back to the post.
2. What you need: versions, tools, platform. Say plainly if it only runs on one platform.
3. Setup, as numbered steps.
4. What it creates or changes on the reader's machine, and how to undo it.
5. Known limits, if any.

Add a row to the index in the root `README.md` in the same commit.

## Prose

- British English.
- Plain hyphens for asides. Never an em dash, anywhere, including code comments and prompts.
- Never hard-wrap prose in Markdown: one paragraph or list item, one line. Code comments are exempt.

## Quality check before pushing

1. Every script parses, and has been run at least once in the state being committed. Use a dry-run mode where the script has one.
2. Search the diff for a home directory path, an email address, a surname, and anything that looks like a key.
3. Search the diff for an em dash.
4. The folder's `README.md` links to the post, and the root index has the row.

## Git

- `main` only. Small commits straight to it are fine.
- Commit or push only when asked.
- Links from a post to this repo use a commit permalink, not a branch, so the post stays accurate after the code moves on.

## Shell

PowerShell, not bash.
