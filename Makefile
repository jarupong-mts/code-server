SHELL := /bin/bash
COMPOSE := docker compose

# Host path of this project. Compose resolves bind mounts on the Docker host, so
# from inside code-server this must be the host path, not /home/coder/project.
# On the host itself it defaults to this checkout; inside a container
# (/.dockerenv exists) it must be given explicitly.
HOST_PROJECT_DIR ?= $(if $(wildcard /.dockerenv),,$(CURDIR))
export HOST_PROJECT_DIR

# Build and (re)create only the T3 Code services; code-server is not touched.
T3_UP := CODE_SERVER_HOME_PATH=$(HOST_PROJECT_DIR)/data/home $(COMPOSE) up -d --no-deps --build t3-auth t3code

.PHONY: up t3-up t3-password check-host-dir

check-host-dir:
	@test -n "$(HOST_PROJECT_DIR)" || { echo "Inside a container, set HOST_PROJECT_DIR to this project's host path." >&2; exit 1; }

# First-time or repeat deploy: prompt for missing secrets in .env, then build
# and start the whole stack. Running this from inside code-server recreates
# code-server itself, so use t3-up for T3-only changes.
up: check-host-dir
	scripts/setup-env.sh
	CODE_SERVER_HOME_PATH=$(HOST_PROJECT_DIR)/data/home $(COMPOSE) up -d --build

t3-up: check-host-dir
	$(T3_UP)

# Prompt for a new T3 password, store its bcrypt hash in .env, then apply it.
t3-password: check-host-dir
	@set -euo pipefail; \
	user=$$(sed -n 's/^T3_USER=//p' .env); user=$${user:-admin}; \
	grep -q '^T3_PASSWORD_HASH=' .env || { echo "T3_PASSWORD_HASH is not set in .env" >&2; exit 1; }; \
	read -r -s -p "New password for $$user: " pw; echo; \
	[ -n "$$pw" ] || { echo "Empty password; nothing changed" >&2; exit 1; }; \
	hash=$$(printf '%s\n' "$$pw" | docker run --rm -i httpd:2.4-alpine htpasswd -niB "$$user" | cut -d: -f2-); \
	case "$$hash" in '$$2y$$'*) ;; *) echo "Could not generate a bcrypt hash" >&2; exit 1 ;; esac; \
	umask 077; \
	awk -v h="$$hash" 'BEGIN { q = sprintf("%c", 39) } /^T3_PASSWORD_HASH=/ { print "T3_PASSWORD_HASH=" q h q; next } { print }' .env > .env.new; \
	cat .env.new > .env; rm -f .env.new; \
	echo "Updated T3_PASSWORD_HASH in .env"; \
	$(T3_UP)
