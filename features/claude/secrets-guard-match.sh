#!/bin/sh
# Decides whether a Bash command reads decrypted sops secrets. Exits 0 to BLOCK
# and 1 to ALLOW. Takes the command string as $1.
#
# Split out of claude-secrets-guard so the match can be tested adversarially
# without going through the hook's JSON plumbing. This is a guardrail against
# casual reads, not a sandbox: it matches the command string, so it also has to
# catch the payload of an `ssh <host> "..."`.

cmd="${1-}"
[ -z "$cmd" ] && exit 1

printf '%s\n' "$cmd" \
  | grep -qE '/run/secrets(\.d)?\b|\bsops\b[^|]*(-d|--decrypt)'
