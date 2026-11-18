---
name: diff-review
description: Open George's PR-style review of the agent's changes in difit (browser) and read his inline review comments back. Use when George asks to review your changes, to open the diff in difit, or to "read my review comments". Not for the agent reviewing code on its own.
---

# Diff review: difit

George reviews agent-made changes like a GitHub pull request in difit: he
browses the changeset in the browser, leaves inline comments, and hands them
back. difit exposes the comments through its CLI.

## Launch

`diff-review <repo-or-file>` (defaults to the cwd). A dirty tree opens the
uncommitted changes, untracked files included; a clean one opens the HEAD
commit. For untracked files difit runs `git add -N` on them (intent-to-add),
so afterwards they show as added in `git status`; undo with
`git reset -- <file>` if that matters. For any other range, run difit directly
from the repo root (`difit HEAD~3`, `difit main feature`; `difit --help`).

The command returns immediately and prints one status line. Tell George the
review is open, then wait for him to say he is done. Never launch a second
review for the same repo while he is reviewing.

## Read comments

1. Find the port in the URL logged to
   `${XDG_RUNTIME_DIR:-/tmp}/diff-review/difit.log` (default 4966, one higher
   for each port already taken).
2. `difit comment get --port <port> --format json` prints
   `{"threads": [...]}`; each thread has `id`, `filePath`, `position`
   (`side`, `line`), `codeSnapshot`, and `messages[].body`.
3. After addressing a thread: `difit comment resolve <threadId...> --port <port>`.

The server shuts down as soon as its browser tab disconnects ("Client
disconnected, shutting down server..." in the log), so read the comments
while George still has the tab open. Never open your own browser client on
his server: closing it kills his session. If the server is already gone, ask
him to paste the output of difit's "Copy All Prompt".

## Rules

- Do not add your own comments unless George asks. If he does:
  `difit comment add --port <port> '<json>'`.
- Never copy secrets from a diff into comment text or argv.
