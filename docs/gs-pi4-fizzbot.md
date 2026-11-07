# Fizzbot Pi

`gs-pi4-fizzbot` runs the fizzbot-3 Discord bot and Ollama on a 4 GB Raspberry Pi 4.
It boots from a 128 GB USB flash drive. Ollama listens on localhost only.

## Access

```sh
ssh george-sleen@gs-pi4-fizzbot
```

Tailscale uses ordinary OpenSSH, not Tailscale SSH. The Pi keeps its direct-link
network settings until it moves to the router.

## Discord token

`secrets/gs-pi4-fizzbot.yaml` contains the `fizzbot_discord_token` key.
Only George and this Pi are age recipients. Edit the token in a private terminal:

```sh
sops secrets/gs-pi4-fizzbot.yaml
```

Sops-nix installs the token as a root-only file. Systemd passes it to the bot
through `LoadCredential`. Do not put the token in source, arguments, or logs.

## Discord access

Enable Message Content Intent on the application's Bot page in the
[Developer Portal](https://discord.com/developers/applications).
The bot needs message content to read the conversation before a mention or reply.
See Discord's [intent access rules](https://support-dev.discord.com/hc/en-us/articles/40281523410967-Changes-to-Privileged-Intent-Access-for-Discord-Apps).

Grant View Channel, Read Message History, Send Messages, and Add Reactions in the
channels where the bot operates. The existing Discord application needs no new
invitation if it already has these permissions.

## Build and deploy

The `fizzbot-3` flake input pins the local Git repository at
`~/Documents/projects/fizzbot-3`. Commit bot changes there before updating its pin:

```sh
nix flake update fizzbot-3
make test
make build-gs-pi4-fizzbot
nixos-rebuild switch --flake .#gs-pi4-fizzbot \
  --target-host george-sleen@gs-pi4-fizzbot --elevate=sudo
make check-boot-order HOST=george-sleen@gs-pi4-fizzbot
```

The build retains the host closure at `.gcroots/gs-pi4-fizzbot`.
Keep datasets, labels, model weights, and plaintext credentials outside Git and
the Nix store.

## Model and service

The bot requests the Ollama model `fizzbot` and starts at boot.
`ollama-preload-fizzbot` loads that model at boot. The model lives in Ollama's
state directory on the Pi, so a NixOS rebuild does not replace it.
Do not run fizzbot-2 and fizzbot-3 with the same Discord token at the same time.

To install a new model, run `make export-model` in fizzbot-3 and copy
`runs/export/fizzbot.gguf` to the Pi. Then run these commands in that directory:

```sh
printf 'FROM ./fizzbot.gguf\n' > Modelfile
ollama create fizzbot -f Modelfile
sudo systemctl restart ollama ollama-preload-fizzbot fizzbot
```

To read the bot log:

```sh
ssh gs-pi4-fizzbot 'sudo journalctl -u fizzbot -n 30 --no-pager'
```

The host builds the bot with the `aarch64-cross` package of fizzbot-3. A native x86 compiler produces the ARM binary, so a bot change builds in minutes instead of 20 to 55 under QEMU.

## Ranking rounds

`trainingChannelId` in `hosts/gs-pi4-fizzbot/fizzbot.nix` turns on ranking rounds in that Discord channel: one batch of ten a day. `trainingEndsAt` stops new rounds at a Unix time. The bot needs permission there to view the channel, send messages, read history and add reactions.

The bot reads `/var/lib/private/fizzbot/requests.txt`, with one request per line. The file holds real names, so it stays out of git and the Nix store. Copy it to the Pi as root:

```bash
scp notes/fizzbot-pi/requests.txt root@gs-pi4-fizzbot:/var/lib/private/fizzbot/requests.txt
```

The same directory holds `rounds.jsonl` and `votes.jsonl`. `make pull-votes` in the fizzbot-3 repository copies the votes to the laptop.
