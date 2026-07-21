# Secrets (sops-nix)

Encrypted secrets live under `secrets/` as per-host files (e.g.
`secrets/secrets.yaml` for the T480s, `secrets/gs-pi4.yaml` for the Pi),
decrypted at activation to `/run/secrets/<name>`.

`.sops.yaml` lists recipients (who can decrypt) as age keys:

- **Your personal (editing) key**, derived from `~/.ssh/id_ed25519`; a
  recipient on every file so you can edit any host's secrets from your laptop.
- **One key per host**, derived from that host's own SSH host key
  (`/etc/ssh/ssh_host_ed25519_key`); the host decrypts itself at boot. No host
  key is ever distributed or backed up.

`creation_rules` map each file to its recipients (your key + that host's key).
The most specific `path_regex` must come first, since sops uses the first match.

## Edit secrets

```bash
sops secrets/<host>.yaml
```

Decrypts to `$EDITOR`, re-encrypts on save.

## Add a secret to a host

In the host's `default.nix`:

```nix
sops.defaultSopsFile = ../../secrets/<host>.yaml;
sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
sops.secrets.my-secret = { };
```

Available at `/run/secrets/my-secret` after rebuild. Nested YAML keys use a `/`
path: `sops.secrets."jellyfin/api_key"` reads `jellyfin: { api_key: ... }`.

## Onboard a new host

1. Derive the host's age key from its SSH host key:

   ```bash
   ssh <host> 'cat /etc/ssh/ssh_host_ed25519_key.pub' | ssh-to-age
   ```

2. In `.sops.yaml`, add it as a `&host_<name>` anchor, then add a creation rule
   for its file (your key + that host key) *above* the general rule:

   ```yaml
   creation_rules:
     - path_regex: secrets/<host>\.yaml$
       key_groups:
         - age: [ *user_george, *host_<name> ]
   ```

3. Create the encrypted file. From a plaintext yaml kept outside git (shred it
   after), matching the rule via the path passed to sops:

   ```bash
   sops --config .sops.yaml -e /tmp/plain/secrets/<host>.yaml > secrets/<host>.yaml
   ```

   Or `sops secrets/<host>.yaml` to author interactively.

4. Existing files pick up a changed recipient set only after
   `sops updatekeys secrets/<file>.yaml`.

## Personal key: derived from your SSH key

Your editing identity at `~/.config/sops/age/keys.txt` is derived from
`~/.ssh/id_ed25519` (backed up in Bitwarden), so it is disposable; regenerate
it on any machine that has your SSH key:

```bash
ssh-to-age -private-key -i ~/.ssh/id_ed25519 > ~/.config/sops/age/keys.txt
```

Back up only your SSH key. To rotate the personal recipient, put the new
`age1...` (from `ssh-to-age -i ~/.ssh/id_ed25519.pub`) in `.sops.yaml` and run
`sops updatekeys` on every secrets file.

## Recover or rotate a host key

Host keys need no backup. If a host is reimaged its SSH host key changes;
re-derive its age key (step 1 above), replace the anchor in `.sops.yaml`, and
`sops updatekeys secrets/<host>.yaml`.
