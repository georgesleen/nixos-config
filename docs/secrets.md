# Secrets (sops-nix)

Encrypted secrets live in `secrets/secrets.yaml`, decrypted at activation
to `/run/secrets/<name>`. Recipients (who can decrypt) are listed in
`.sops.yaml`: one personal age key per editor, one age key per host derived
from that host's own SSH host key — no separate host key to distribute.

## Edit secrets

```bash
sops secrets/secrets.yaml
```

Decrypts to `$EDITOR`, re-encrypts on save.

## Add a secret to a host

In the host's `default.nix`:

```nix
sops.defaultSopsFile = ../../secrets/secrets.yaml;
sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
sops.secrets.my-secret = { };
```

Available at `/run/secrets/my-secret` after rebuild.

## Onboard a new host

```bash
ssh-to-age -i /etc/ssh/ssh_host_ed25519_key.pub   # run on the new host
```

Add the result to `.sops.yaml` as a new recipient, then re-encrypt:

```bash
sops updatekeys secrets/secrets.yaml
```

## Personal age key

Your editing key lives at `~/.config/sops/age/keys.txt` — machine-local,
not in git. Back it up (e.g. password manager); losing it without a backup
means you can no longer edit secrets except by SSH-ing into a host and
using its own key directly.
