#!/bin/sh
set -eu

# The upstream image provides fixuid specifically so an arbitrary Compose
# user can become the coder account and use its passwordless sudo rule.
eval "$(fixuid -q)"

runtime_uid="$(id -u)"
runtime_gid="$(id -g)"

# Docker creates missing bind-mount source directories as root.  Change only
# the mount roots and code-server's own state directories; never recursively
# chown an arbitrary workspace supplied by the user.
sudo mkdir -p /home/coder/.local /home/coder/.config /home/coder/project
sudo chown "$runtime_uid:$runtime_gid" /home/coder /home/coder/project

for state_path in /home/coder/.local /home/coder/.config; do
    if [ "$(stat -c '%u:%g' "$state_path")" != "$runtime_uid:$runtime_gid" ]; then
        echo "Preparing writable state directory: $state_path"
        sudo chown -R "$runtime_uid:$runtime_gid" "$state_path"
    fi
done

# The upstream entrypoint runs fixuid harmlessly a second time, applies
# DOCKER_USER, executes setup hooks, and starts code-server under dumb-init.
exec /usr/bin/entrypoint.sh "$@"
