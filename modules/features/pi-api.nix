# `pi-api`: call the media stack's HTTP APIs without handling their keys.
#
# Each key stays in its sops file and is read straight into the curl header, so
# it never reaches a shell argument, the terminal, or a saved transcript. Full
# read/write: the arrs issue admin-equivalent keys and have no read-only scope,
# so the point here is confining where the key travels, not what it can do.
#
#   sudo pi-api sonarr GET /queue
#   sudo pi-api radarr GET /movie
#   sudo pi-api jellyfin GET /Sessions
#   sudo pi-api sonarr POST /command '{"name":"RefreshSeries"}'
#
# Needs root to read /run/secrets; gs-pi4 has passwordless sudo for wheel.
{ pkgs, ... }:
let
  piApi = pkgs.writeShellApplication {
    name = "pi-api";
    runtimeInputs = [
      pkgs.curl
      pkgs.jq
    ];
    text = ''
      service=''${1-}; method=''${2-}; path=''${3-}; body=''${4-}

      # service|port|secret|header|api-base
      table='
      sonarr|8989|/run/secrets/sonarr/api_key|X-Api-Key|/api/v3
      radarr|7878|/run/secrets/radarr/api_key|X-Api-Key|/api/v3
      prowlarr|9696|/run/secrets/prowlarr/api_key|X-Api-Key|/api/v1
      seerr|5055|/run/secrets/seerr/api_key|X-Api-Key|/api/v1
      jellyfin|8096|/run/secrets/jellyfin/api_key|X-Emby-Token|
      '

      if [ -z "$service" ] || [ -z "$method" ] || [ -z "$path" ]; then
        echo "usage: pi-api <service> <METHOD> <path> [json-body]" >&2
        echo "services:$(echo "$table" | awk -F'|' '/./{printf " %s", $1}')" >&2
        exit 2
      fi

      row=$(echo "$table" | awk -F'|' -v s="$service" '$1 == s {print; exit}')
      if [ -z "$row" ]; then
        echo "pi-api: unknown service '$service'" >&2
        exit 2
      fi

      port=$(echo "$row" | cut -d'|' -f2)
      secret=$(echo "$row" | cut -d'|' -f3)
      header=$(echo "$row" | cut -d'|' -f4)
      base=$(echo "$row" | cut -d'|' -f5)

      if [ ! -r "$secret" ]; then
        echo "pi-api: cannot read $secret (run under sudo?)" >&2
        exit 1
      fi

      # The key goes in via --config on stdin, so it is never an argv entry
      # visible in /proc, nor echoed back to the caller.
      case "$path" in /*) ;; *) path="/$path" ;; esac
      url="http://127.0.0.1:''${port}''${base}''${path}"

      set -- --silent --show-error --fail-with-body \
        --request "$method" --config - "$url"
      if [ -n "$body" ]; then
        set -- "$@" --header "Content-Type: application/json" --data "$body"
      fi

      printf 'header = "%s: %s"\n' "$header" "$(cat "$secret")" \
        | curl "$@" \
        | { jq . 2>/dev/null || cat; }
    '';
  };
in
{
  environment.systemPackages = [ piApi ];
}
