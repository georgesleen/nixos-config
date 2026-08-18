#!/bin/sh
# Adversarial tests for secrets-guard-match.sh. Exit 0 means BLOCK, 1 ALLOW.
#
# This guard is deliberately a command-string match, not a sandbox, so these
# tests pin what it does and does not catch. The "known gap" cases at the end
# document real bypasses on purpose: they are the limits of the approach, not
# bugs to be surprised by later.
set -u
script="${1:?usage: secrets-guard-match.test.sh <script> <lib>}"
. "${2:?}"

secrets_dir="/run/sec""rets"

# blocked <description> <command>
blocked() { check_exit "$1" 0 sh "$script" "$2"; }
# allowed <description> <command>
allowed() { check_exit "$1" 1 sh "$script" "$2"; }

blocked "a direct read of the secrets dir" "cat $secrets_dir/wifi-password"
blocked "a listing of the secrets dir" "ls -la $secrets_dir"
blocked "the .d variant of the path" "cat $secrets_dir.d/foo/bar"
blocked "a path buried mid-command" "diff /tmp/a $secrets_dir/b"
blocked "a read inside an ssh payload" "ssh gs-pi4 \"cat $secrets_dir/token\""
blocked "sops with -d" "sops -d secrets/secrets.yaml"
blocked "sops with --decrypt" "sops --decrypt secrets/secrets.yaml"
blocked "sops -d with flags in between" "sops -d --extract '[\"a\"]' secrets/secrets.yaml"

# Ordinary work must not trip the guard.
allowed "an unrelated command" "ls -la /etc/nixos"
allowed "editing the encrypted file is fine" "sops secrets/secrets.yaml"
allowed "sops updatekeys does not decrypt to stdout" "sops updatekeys secrets/secrets.yaml"
allowed "a path that merely starts the same" "cat /run/secretsomething"
allowed "the word secrets on its own" "grep -r secrets /etc/nixos"
allowed "an empty command" ""

# Known gaps. The guard matches literal text, so any command that hides the
# path from the string gets through. Recorded so the limit is explicit.
allowed "KNOWN GAP: a path assembled from variables" 'd=/run/sec; cat "$d"rets/x'
allowed "KNOWN GAP: a glob standing in for the path" "cat /run/sec*/token"

finish
