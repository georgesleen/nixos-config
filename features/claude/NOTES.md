# claude

## secretsGuardMatch (home.nix)

PreToolUse hook: block any Bash command that would read decrypted secrets, i.e. the sops-nix runtime mount (/run/secrets, /run/secrets.d) or a sops decrypt-to-stdout (sops -d / --decrypt). The grep sees the whole command string, so it also catches these paths inside an `ssh <host> "..."` payload (the real gap: /run/secrets is 0400 locally, but an ssh login user or sudo routes around file perms). Guardrail against casual/accidental reads, not a hard sandbox: string matching can be defeated by obfuscation. The match itself lives in secrets-guard-match.sh so it can be tested adversarially, including the cases it deliberately does not catch; tests run by `make test`.

## debugHook (home.nix)

Debug-skill nudge: PostToolUse on Bash. When a command's output carries a strong failure signal (not a bare non-zero exit, which grep/test/[ produce benignly), emit a one-line NON-BLOCKING reminder to invoke /debug for root-cause analysis. Deliberately cheap: the methodology lives in the debug SKILL.md and only loads when the skill is actually invoked; this only nudges. Deduped by error signature so a re-run of the same failure does not re-inject. Never blocks: exits 0 with a systemMessage, so it costs ~1 line and never derails routine failures.

## playwright@claude-plugins-official (home.nix)

Disabled: the npx-based plugin cannot run a browser on NixOS. Browser work goes through the `returns` skill instead, which drives the playwright node library over CDP against a headed Chromium. The nix playwright-mcp server that used to stand in here was removed from mcp-servers.nix on 2026-09-11; see the note there.

## imports (home.nix)

Each skill under ./skills is a self-contained module: a <name>.nix that links its ./<name> content dir (recursively, so ~/.claude/skills stays writable for ad-hoc skills) and declares any runtime deps of its own. Auto- import every such file, so adding a skill is just dropping in a <name>/ dir plus a sibling <name>.nix, with no edit here.

## Overview (mcp-servers.nix)

MCP servers for Claude Code, consumed through its settings.json (claude.nix).

A server's tool schemas ride every request of every session, used or not. `playwright` was dropped for that: 23 schemas, never called, and the `returns` skill drives playwright over CDP itself.

## Workarounds

- `claude-proxy.nix`: proxy launchers pass `--settings` with a runtime credential helper because agent-view background sessions do not reliably inherit shell-only gateway exports.
- Both laptop hosts register `sudoAskpass` as sudo's `Path askpass` in `/etc/sudo.conf`: a masked Zenity GTK password window for ttyless sudo, with no `-A` needed. Terminal sudo keeps its normal prompt. Polkit actions use the separate `polkit-gnome` agent; sudo still authenticates through its own PAM stack.
- Framework `sudoPasswordTimeout = "5m"` bounds each GTK askpass prompt, not sudo's credential-cache lifetime. The longer window allows time to notice and answer a desktop authentication request.
- `home.nix` `secretsHook` (PreToolUse/Bash) + `permissions.deny` on `Read(/run/secrets/**)`: block Claude from reading decrypted sops secrets (`/run/secrets`, `sops -d`), including inside an `ssh <host> "..."` payload. Guardrail against casual reads, not a hard sandbox (matches the command string). To act on a secret-backed service, use its own runtime credential inline without echoing it, or an auth-bypass path.
