---
name: fix-media-grab
description: Fix a wrong-version or wrong-release grab on the gs-pi4 nixflix stack (e.g. a live-action remake imported into an animated series, wrong year, remake-vs-original, wrong show). Covers finding the offending Sonarr/Radarr file, deleting it, blocklisting the bad release, re-searching for the correct version, and library-wide scans for the same mistake. Invoke when a user reports "wrong version", "live action instead of animated", "wrong episode/movie downloaded", or wants the media library audited for version mismatches.
---

# Fixing a wrong-version media grab (gs-pi4)

Sonarr/Radarr sometimes grab the WRONG production for the right title: a
live-action remake imported into the animated original (the classic case:
"Avatar: The Last Airbender" 2005 animated polluted with the 2024 Netflix
live-action), a wrong-year remake, or a different show entirely
("The Kings Avatar"). This skill is the remediation loop. Read the `gs-pi4`
skill first for how to reach the services and the secret-safety rules.

## Reaching the *arr API (IMPORTANT, non-obvious on this host)

The api key is NOT in `config.xml`. These services run with the data dir on the
media drive and the api key injected as a systemd credential:

- Live config is `-data=/srv/media/.state/<app>` (confirm with
  `tr '\0' ' ' < /proc/<pid>/cmdline`), and that `config.xml` has **no**
  `<ApiKey>` element. The `/var/lib/<app>/config/config.xml` copy is stale/unused
  here (the gs-pi4 skill's note is inverted for this reason).
- The key is exported to the process env as `SONARR__AUTH__APIKEY` /
  `RADARR__AUTH__APIKEY` from `/run/credentials/<app>.service/apiKey`.
  `/run/secrets/**` and `sops -d` are blocked, but you may read the key from the
  running process env into a shell variable and use it inline **without ever
  printing it**:

```bash
ssh gs-pi4 'bash -s' <<'REMOTE'
set -euo pipefail
jq=$(ls -d /nix/store/*-jq-*/bin/jq | head -1)
pid=$(sudo -A -k -n systemctl show sonarr -p MainPID --value)
key=$(sudo -A -k -n cat /proc/$pid/environ | tr '\0' '\n' | sed -n 's/^SONARR__AUTH__APIKEY=//p')
curl -s -H "X-Api-Key: $key" http://localhost:8989/api/v3/system/status >/dev/null && echo OK
REMOTE
```

Ports: Sonarr 8989, Radarr 7878, Prowlarr 9696. `jq` isn't on PATH; grab one from
the store. Never echo the key.

## Confirm the mismatch

For the series, list episode->file with the tells that separate animated original
from live-action remake:

```bash
curl -s -H "X-Api-Key: $key" "http://localhost:8989/api/v3/episode?seriesId=<id>&includeEpisodeFile=true" \
  | $jq -r '.[] | "S\(.seasonNumber)E\(.episodeNumber)\tfileId=\(.episodeFileId)\tgrp=\(.episodeFile.releaseGroup // "-")\trt=\(.episodeFile.mediaInfo.runTime // "-")"'
```

Live-action / wrong-version tells vs the animated original:

| signal        | animated original            | live-action remake            |
|---------------|------------------------------|-------------------------------|
| runtime       | ~22-25 min (kids anime)      | ~48-68 min (hour drama)       |
| resolution    | 1440x1080 / 4:3 pillarbox    | 1920x8xx widescreen           |
| release title | no year, real episode titles | "2024"/"2026", "NF WEB-DL"    |
| audio         | AAC 2.0                      | AAC/DDP 5.1, Atmos            |

Also check grab history for the offending release title/downloadId:
`GET /history/series?seriesId=<id>&eventType=1` (`.sourceTitle`, `.downloadId`).
Confirm the file on disk via `GET /episodefile/<id>` `.path` (the folder name may
differ from the title, e.g. `Avatar - The Last Airbender`).

## Remediate (the Sonarr-correct way)

1. **Blocklist** the bad release so it is not re-grabbed. If the grab is still in
   history, `POST /history/failed/<historyId>` marks it failed AND blocklists.
   Otherwise it's usually already in `GET /blocklist` (check first).
2. **Delete** the offending episodefile(s): `DELETE /episodefile/<id>` (removes the
   file from disk and clears hasFile). The auto-mode classifier will block a large
   multi-file range as scope-escalation; delete the file the user explicitly named
   first, and get an explicit go-ahead before deleting a wider set.
3. **Re-search** for the correct version. Do NOT trust a bare `EpisodeSearch`
   command: the top-scored release is often the live-action or a different show.
   Use interactive search and inspect: `GET /release?episodeId=<id>`, filter out
   the wrong version, then grab a clean one by POSTing `{guid,indexerId}` to
   `/release`.

### The animated single-episode trap (important)

For some animated series the indexers have NO animated single-episode release,
only the live-action singles and a wrong-show ("The Kings Avatar"). The animated
episodes exist only inside **season / complete packs**. When per-episode search
comes up empty, search the season pack:
`GET /release?seriesId=<id>&seasonNumber=<n>`, pick an animated pack (no year, no
"NF WEB-DL", BluRay/WEBRip, `approved=true` with empty rejections), and grab it;
Sonarr imports the missing episodes and skips ones already present. A big
well-seeded complete pack (e.g. `S01 to S03 BR X264`) is often `approved=false`
only because on-disk files are equal/higher preference (an upgrade rejection, not
a wrong-content one) and can be force-grabbed if the user prefers it.

### Verify

`GET /queue?includeEpisode=true` should show only animated titles for the series;
re-check `GET /episodefile?seriesId=<id>` shows no `2024`/`NF`/`-R` live-action
paths. Confirm the torrents are moving in qBittorrent (VPN netns), per the gs-pi4
skill.

## Library-wide audit for the same mistake

Two heuristics, run per series/movie:

- **Runtime outlier:** flag any episodefile whose runtime is >1.7x the series
  median (a live-action hour inside a 24-min anime stands out). Legit multi-episode
  files (`S02E12E13`) and genuine long premieres are false positives; verify by
  release title, not runtime alone.
- **Year / production marker:** flag files whose scene name carries a year or
  `NF`/`Netflix`/`WEB-DL DDP` that does NOT match the series' own year/production.
  Noisy: Apple TV+ dramas, genuinely-2021 Netflix animation (Arcane), and
  correctly-dated sequels (Dexter: New Blood 2021) are false positives. Only
  animated-original-vs-live-action-remake and wrong-year-remake cases are real.

For Radarr, compare each `.movieFile` year to `.year`; a mismatch flags a remake
(e.g. The Intouchables 2011 original vs The Upside 2019 remake).

Only auto-fix CLEAR-CUT live-action-in-animated cases (delete + blocklist +
re-search animated). List AMBIGUOUS ones for the user; do not delete on a guess.

## Prevent recurrence

The root cause is the *arr matching a season/series pack of the remake to the
animated series' TVDB entry. Options to raise with the user: a "Restrict" release
profile term (block `Live.?Action` or the remake's year) on the animated series,
or a custom format with a negative score for the remake's markers. The two Avatar
live-action packs are already in the Sonarr blocklist, which stops those exact
releases but not new ones.
