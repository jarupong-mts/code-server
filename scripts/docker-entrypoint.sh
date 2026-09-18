#!/bin/sh
set -eu

# The upstream image provides fixuid specifically so an arbitrary Compose
# user can become the coder account and use its passwordless sudo rule.
eval "$(fixuid -q)"

runtime_uid="$(id -u)"
runtime_gid="$(id -g)"

# Docker creates missing bind-mount source directories as root.  The workspace
# can also contain files copied or checked out by root, so fixing only the
# mount root is not enough: VS Code must be able to create and update files in
# nested directories as well.
sudo mkdir -p /home/coder/.local /home/coder/.config /home/coder/project
sudo chown "$runtime_uid:$runtime_gid" /home/coder

repair_tree() {
    tree_path="$1"

    # Avoid a recursive chown on every restart when the tree is already owned
    # by the runtime user.  -xdev keeps the check inside the bind mount.
    if sudo find "$tree_path" -xdev \
        \( ! -uid "$runtime_uid" -o ! -gid "$runtime_gid" \) \
        -print -quit | grep -q .; then
        echo "Preparing writable directory tree: $tree_path"
        sudo chown -R "$runtime_uid:$runtime_gid" "$tree_path"
    fi
}

repair_tree /home/coder/.local
repair_tree /home/coder/.config
repair_tree /home/coder/project

# The upstream entrypoint runs fixuid harmlessly a second time, applies
# DOCKER_USER, executes setup hooks, and starts code-server under dumb-init.
exec /usr/bin/entrypoint.sh "$@"
