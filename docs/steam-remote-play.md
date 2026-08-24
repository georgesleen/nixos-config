# Steam Remote Play: win11 VM (gs-server) to T480s

Working configuration as of 2026-07-02. Host is Steam inside the win11 VM
(RX580 passthrough), client is Steam on the T480s. LAN only; Tailscale is
deliberately out of the path (see below).

## Why not Tailscale

- Steam discovers Remote Play hosts via UDP broadcast on 27036. Tailscale is
  layer 3 point-to-point and never carries broadcast, so discovery cannot work
  across the tailnet.
- Tailscale merely being connected on a Windows host breaks Remote Play even
  on the LAN: Steam advertises the wrong IP during discovery
  ([tailscale/tailscale#4320](https://github.com/tailscale/tailscale/issues/4320),
  open, no fix).
- On top of both, the guest's tailscaled was found wedged (two daemon
  processes, state "NoState", data path dead even via DERP relay), which is
  why nothing ever reached the VM over the tailnet.

Resolution: the Tailscale service inside the guest is stopped and disabled
(`sc stop Tailscale`, `sc config Tailscale start= disabled`).

## Guest addressing (changed 2026-08-23)

The guest no longer sits on the LAN. It is on libvirt's NAT bridge at a fixed
`192.168.122.248` (MAC `52:54:00:cd:23:2a`), because macvtap cannot ride the
Wi-Fi uplink gs-server falls back to; see `hosts/gs-server/win11-vm.nix`.

Reach it at **gs-server's own address** on the forwarded ports: `gs-server`
(Tailscale `100.111.59.110`) works from anywhere on the tailnet, or its LAN
address (`192.168.10.227` wired, `192.168.10.228` on Wi-Fi). RDP is
`gs-server:3389`; the Sunshine web UI is `https://gs-server:47990`.

Forwarded by the `60-win11-network` libvirt hook: TCP 3389, 47984, 47989,
47990, 48010 and UDP 3389, 47998, 47999, 48000, 48002, 48010. The rules exist
only while the domain runs.

Two consequences:

- **Steam Remote Play discovery no longer works.** It finds hosts by UDP
  broadcast on 27036, which no NAT carries. Moonlight, which is addressed
  directly, is unaffected. Steam in-home streaming would need the guest back
  on the LAN, which needs the wired uplink.
- **RDP is now reachable from the whole tailnet**, not LAN-only as before.

## Start sequence

```bash
wake-server                                   # WoL alias (bashrc.nix)
ssh gs-server virsh -c qemu:///system start win11
```

The VM is headless: the domain has `<video model='none'/>` and the RX580 is
the only GPU, so the virt-manager console is black by design. Windows
auto-logs-in; Steam auto-starts and binds UDP 27036 a minute or two after
boot. SSH into the guest is not available: the guest has no listener on 22
(checked 2026-08-23).

## RX580 Code 43 after a dirty handoff

If games in the guest fail with "A D3D11-compatible GPU is required", check
the adapter: it will be Code 43 (`CM_PROB_FAILED_POST_START`) and the desktop
is software-rendered.

Cause: amdgpu on the host initialized the card (host boot), then the
`managed='yes'` detach handed the guest an unreset GPU. A device
disable/enable inside the guest does NOT clear it. Fix is a graceful VM power
cycle; on VM stop the card rebinds to amdgpu, which re-POSTs it, and the next
start hands it over clean:

```bash
virsh -c qemu:///system shutdown win11   # wait for "shut off"
virsh -c qemu:///system start win11
```

Check from ssh:

```
powershell -NoProfile -Command "Get-CimInstance Win32_VideoController | Select-Object Name,ConfigManagerErrorCode"
```

`0` is healthy. Related: Code 10 after a guest soft reboot, same class, same
fix (see CLAUDE.md Workarounds).

## Pairing a new client (one-time)

Both ends signed into the same Steam account on the same LAN. On the client:
Settings, Remote Play, the guest appears under Computers & Devices, click
Connect. Steam shows a 4-digit PIN that must be typed into Steam on the
guest, which is headless, so RDP in (Remmina, `gs-server`) and enter it
there.

## Console lock: always hand the session back

Disconnecting or quitting RDP locks the Windows console session, and Remote
Play then captures a lock screen (black stream). After any RDP use, hand the
session back to the physical console instead of just closing the client:

```
# From an RDP session on the guest, or any guest shell:
tscon 1 /dest:console
```

(Session id from `query session`; it is 1 with the standard autologon.) This
drops the RDP client and leaves the console unlocked and streamable.

## Known ceiling: use Moonlight for heavy games

Steam's host-side AMF (hardware) encoder is broken on the RX580
(`SetProperty(AMF_VIDEO_ENCODER_RATE_CONTROL_SKIP_FRAME_ENABLE)` fails, all
encoders fail, Steam falls back to software x264 and BitBlt capture). Polaris
is on AMD's legacy driver branch, so the mainline 23.30+ AMF fixes will never
arrive; and the x264 fallback shares the VM's 6 vCPUs (i7-6700K, 4c/8t) with
the game, so encode balloons to hundreds of ms per frame on CPU-heavy titles.

Sunshine's AMF works fine on the same driver (H.264 and HEVC, 8-bit only), so
Moonlight + Sunshine is the playable path: HEVC AMF encode on the RX580, iHD
VA-API decode on the T480s (`intel-media-driver`, required, also what makes
Remmina fast). Keep Steam Remote Play for light titles/convenience. If
Moonlight errors "No running app to resume (503)", restart the Sunshine
service in the guest: `net stop SunshineService & net start SunshineService`.

### Moonlight client settings (T480s)

- Display mode: **Fullscreen**, always. Tiled/windowed means sway scales the
  1080p stream down to the tile, which letterboxes it (black side bars) and
  destroys sharpness; no bitrate compensates for that. Manual toggle:
  left Alt+f (sway `Mod3+f`), or
  `swaymsg '[app_id="com.moonlight_stream.Moonlight"] fullscreen enable'`.
- 1920x1080, 60 fps, HEVC, bitrate 60-80+ Mbps; V-Sync off and lowest-latency
  frame pacing for input delay.
- Windows key only reaches the guest with "Capture system keyboard
  shortcuts" active (set to Always, or stream fullscreen). While capture is
  active, sway's own bindings are inhibited. Ctrl+Esc opens the Start menu
  without any capture.
- The custom keymap makes left Alt Hyper_L, so inside the stream use
  **right Alt** for Alt combos, including Moonlight's overlay
  (Ctrl+RightAlt+Shift+S for stats).
- Expectations: ~30-60 ms added latency on wired LAN when tuned (fine for
  factory games, not twitch shooters); 4:2:0 chroma keeps small text slightly
  soft, use RDP for desktop work.

## UDP offload notes

Latency-sensitive streamers misread coalesced UDP as packet loss and throttle
to ~1 FPS, so segmentation offload stays off at every hop that applies:

- Guest VirtIO NIC: "UDP Segmentation Offload" disabled (IPv4 and v6) in the
  adapter's advanced properties. A Windows/driver update can silently revert
  this; re-check if quality tanks.
- NixOS hosts: `tailscale-disable-uso` unit in `modules/core/common.nix`
  (only relevant if streaming ever crosses tailscale0 again).
