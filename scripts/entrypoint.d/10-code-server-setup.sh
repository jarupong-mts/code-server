#!/bin/sh
set -eu

# Create a default theme only for a new profile. Existing user settings win.
# code-server stores VS Code user data and extensions here by default.
settings_dir="${HOME}/.local/share/code-server/User"
settings_file="${settings_dir}/settings.json"
mkdir -p "$settings_dir"
if [ ! -f "$settings_file" ]; then
    jq -n \
        --arg theme "${CODE_SERVER_THEME:-Default Dark Modern}" \
        '{"workbench.colorTheme": $theme}' \
        > "$settings_file"
fi

# Install missing extensions into the persisted code-server profile. The value
# is comma-separated so it can be configured in Compose without YAML arrays.
extensions="${VSCODE_EXTENSIONS:-ms-python.python,ms-python.vscode-pylance,charliermarsh.ruff,esbenp.prettier-vscode,dbaeumer.vscode-eslint,redhat.vscode-yaml,yzhang.markdown-all-in-one}"
installed_extensions="$(code-server --list-extensions 2>/dev/null || true)"

printf '%s' "$extensions" | tr ',' '\n' | while IFS= read -r extension; do
    extension="$(printf '%s' "$extension" | sed 's/^ *//; s/ *$//')"
    [ -n "$extension" ] || continue

    if ! printf '%s\n' "$installed_extensions" | grep -Fxq "$extension"; then
        echo "Installing VS Code extension: $extension"
        code-server --install-extension "$extension"
    fi
done
