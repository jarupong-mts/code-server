#!/usr/bin/env bash
# Creates .env from .env.example on first run, then prompts for any required
# secret that is still unset or left at its placeholder. Values are never
# echoed, and the T3 password is stored only as a bcrypt hash.
set -euo pipefail

cd "$(dirname "$0")/.."
ENV_FILE=.env

if [ ! -f "$ENV_FILE" ]; then
  install -m 600 .env.example "$ENV_FILE"
  echo "Created $ENV_FILE from .env.example"
fi

# Value of KEY from .env without surrounding single quotes, empty when missing.
# The file is never sourced, so the `$` characters in a bcrypt hash are not
# expanded.
get() { sed -n "s/^$1=//p" "$ENV_FILE" | tail -n 1 | sed -e "s/^'//" -e "s/'\$//"; }

# A value needs input when it is empty or still the .env.example placeholder.
needs_value() {
  local v
  v=$(get "$1")
  [ -z "$v" ] || [[ "$v" == *replace-with* ]]
}

# Replace KEY=... (or append it) with a single-quoted value. Compose reads
# single-quoted values literally.
set_value() {
  local key=$1 value=$2 tmp
  tmp=$(mktemp "$ENV_FILE.XXXXXX")
  KEY="$key" VAL="'$value'" awk '
    BEGIN { k = ENVIRON["KEY"]; v = ENVIRON["VAL"]; done = 0 }
    index($0, k "=") == 1 { print k "=" v; done = 1; next }
    { print }
    END { if (!done) print k "=" v }
  ' "$ENV_FILE" > "$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$ENV_FILE"
}

# Read a secret twice from stdin and print it on stdout. Prompts go to stderr.
read_secret() {
  local label=$1 first second
  while :; do
    read -r -s -p "$label: " first; echo >&2
    if [ -z "$first" ]; then echo "Empty value, try again." >&2; continue; fi
    if [[ "$first" == *"'"* ]]; then echo "Single quotes are not supported, try again." >&2; continue; fi
    read -r -s -p "Confirm $label: " second; echo >&2
    if [ "$first" != "$second" ]; then echo "Values do not match, try again." >&2; continue; fi
    printf '%s' "$first"
    return 0
  done
}

# Host-specific values. Each is filled only when empty, so a value set by hand
# in .env always wins.
if [ -z "$(get DOCKER_SOCKET_PATH)" ]; then
  # Rootless Docker keeps its socket under the user's runtime directory.
  case "$(docker info -f '{{json .SecurityOptions}}')" in
    *rootless*) socket="/run/user/$(id -u)/docker.sock" ;;
    *) socket=/var/run/docker.sock ;;
  esac
  set_value DOCKER_SOCKET_PATH "$socket"
fi

if [ -z "$(get CODE_SERVER_UID)" ]; then
  set_value CODE_SERVER_UID "$(id -u)"
fi

# Rootless engines renumber groups inside containers, so ask a container which
# gid it sees for the socket instead of reading the host's group id.
if [ -z "$(get CODE_SERVER_GID)" ]; then
  gid=$(docker run --rm -v "$(get DOCKER_SOCKET_PATH):/var/run/docker.sock" httpd:2.4-alpine stat -c %g /var/run/docker.sock)
  set_value CODE_SERVER_GID "$gid"
fi

if [ -z "$(get CODE_SERVER_WORKSPACE_PATH)" ]; then
  # The workspace mount is the parent of this checkout (projects/code-server ->
  # projects). Inside code-server the host path must come from HOST_PROJECT_DIR.
  if [ -f /.dockerenv ] && [ -z "${HOST_PROJECT_DIR:-}" ]; then
    echo "Inside a container, set HOST_PROJECT_DIR to this project's host path." >&2
    exit 1
  fi
  set_value CODE_SERVER_WORKSPACE_PATH "$(dirname "${HOST_PROJECT_DIR:-$(pwd -P)}")"
fi

# How code-server is reached. Asked once: Traefik routes it through the proxy
# network, direct publishes it on CODE_SERVER_BIND_IP:CODE_SERVER_PORT.
if [ -z "$(get COMPOSE_FILE)" ]; then
  read -r -p "Route code-server through Traefik on the proxy network? [Y/n]: " answer
  case "$answer" in
    n|N|no|NO)
      read -r -p "Bind IP [0.0.0.0]: " bind_ip
      read -r -p "Port [8080]: " port
      port=${port:-8080}
      case "$port" in ''|*[!0-9]*) echo "Port must be a number" >&2; exit 1 ;; esac
      case "$(docker ps --format '{{.Ports}}')" in
        *":$port->"*) echo "Port $port is already published by a running container" >&2; exit 1 ;;
      esac
      set_value CODE_SERVER_BIND_IP "${bind_ip:-0.0.0.0}"
      set_value CODE_SERVER_PORT "$port"
      set_value COMPOSE_FILE "compose.yaml:compose.direct.yaml"
      ;;
    *) set_value COMPOSE_FILE "compose.yaml" ;;
  esac
fi

# Traefik mode needs a running Traefik to route /code/. Direct mode still needs
# the proxy network, because compose.yaml attaches code-server to it.
if [ "$(get COMPOSE_FILE)" = "compose.yaml" ]; then
  case "$(docker ps --format '{{.Image}}')" in
    *traefik*) ;;
    *) echo "No running Traefik found. Start it first, or answer n to publish code-server directly." >&2; exit 1 ;;
  esac
fi
docker network inspect proxy >/dev/null 2>&1 || docker network create proxy

if needs_value CODE_SERVER_PASSWORD; then
  echo "code-server login password (CODE_SERVER_PASSWORD):" >&2
  password=$(read_secret "code-server password")
  set_value CODE_SERVER_PASSWORD "$password"
  echo "Saved CODE_SERVER_PASSWORD."
fi

if needs_value T3_USER; then
  read -r -p "T3 Code login username [admin]: " user
  set_value T3_USER "${user:-admin}"
fi

if needs_value T3_PASSWORD_HASH; then
  user=$(get T3_USER)
  echo "T3 Code login password (port 3773), user '$user':" >&2
  password=$(read_secret "T3 password")
  hash=$(printf '%s\n' "$password" | docker run --rm -i httpd:2.4-alpine htpasswd -niB "$user" | cut -d: -f2-)
  case "$hash" in '$2y$'*) ;; *) echo "Could not generate a bcrypt hash" >&2; exit 1 ;; esac
  set_value T3_PASSWORD_HASH "$hash"
  echo "Saved T3_PASSWORD_HASH."
fi
