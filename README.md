# code-server with Docker Compose

This deploys a custom code-server image based on the official container, with
Python, Node.js/npm, uv, Claude Code, Codex CLI, OpenCode CLI, and common
development utilities. Settings, CLI credentials, extensions, Git config, and
the workspace persist on the host.

## Quick start

1. Install Docker Engine/Desktop with the Compose plugin.
2. Copy the environment template and set a strong password:

   ```sh
   cp .env.example .env
   ```

   On PowerShell:

   ```powershell
   Copy-Item .env.example .env
   ```

3. On Linux, use the host user's numeric IDs so files created in the mounted
   directories remain editable by that user:

   ```sh
   sed -i "s/^CODE_SERVER_UID=.*/CODE_SERVER_UID=$(id -u)/; s/^CODE_SERVER_GID=.*/CODE_SERVER_GID=$(id -g)/" .env
   mkdir -p data/home workspace
   sudo chown -R "$(id -u):$(id -g)" data/home workspace
   ```

   Docker Desktop on macOS and Windows can use the defaults in `.env.example`.

4. Build and start the service:

   ```sh
   docker compose up -d --build
   docker compose ps
   ```

5. Open <http://127.0.0.1:8080> and sign in with `CODE_SERVER_PASSWORD`.

The default host port is bound to localhost. For access through a reverse proxy,
leave that host binding in place and proxy to `127.0.0.1:8080`; enable WebSocket
support in the proxy. For deliberate direct LAN access, set
`CODE_SERVER_BIND_IP=0.0.0.0` in `.env` and restrict the port with the host
firewall.

The first startup installs the configured missing extensions and creates the
default `CODE_SERVER_THEME`. Both are stored under `data/home`, so normal
container recreation does not remove them. Change `VSCODE_EXTENSIONS` in
`.env` to add more comma-separated extension IDs; the bootstrap only adds
missing extensions and does not remove existing ones.

## Operations

```sh
# Follow logs
docker compose logs -f code-server

# Stop/start without deleting persistent data
docker compose down
docker compose up -d

# Refresh all latest images and tools, then recreate
docker compose build --pull
docker compose up -d
```

Back up `data/home` and `workspace`. Do not run
`docker compose down -v` for this setup: the persistent data is in bind mounts,
but removing volumes is still an easy mistake to make if the compose file is
later extended.

## Notes

- The official image's default container user is UID 1000. `CODE_SERVER_UID`
  and `CODE_SERVER_GID` make that mapping explicit for Linux hosts.
- `PASSWORD` is supplied through `.env`, which is ignored by git. Do not put
  credentials in `compose.yaml` or commit `.env`.
- The health check uses code-server's `/healthz` endpoint, which does not
  require authentication.
- The default image and tool versions use `latest`, so rebuilds can change the
  environment. Review release notes and test after upgrades; pin versions in
  `.env` when reproducibility matters.
- Git and Git LFS come from the upstream code-server image. Python and Node.js
  are installed from the Debian base distribution; uv is copied from Astral's
  official image; the CLIs are installed from their official npm packages.
- This is a single-user code-server deployment. For multiple isolated users,
  use separate environments or a platform designed for multi-tenancy.

## Authenticate the coding agents

Run these from the code-server terminal after the first start. Credentials are
stored under the persisted `/home/coder` mount:

```sh
# Claude Code: choose /login for a browser-based account login
claude

# Codex CLI: Sign in with ChatGPT in the browser
codex --login

# OpenCode: choose a provider interactively
opencode
# then use /connect
```

Avoid putting `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, or provider keys in
`compose.yaml` or a committed file. If you prefer environment-based auth, use
an external secret manager or inject the variables only for the session that
needs them.

## What I recommend installing

The image includes a useful general-purpose baseline:

- Core: Git, Git LFS, OpenSSH client, curl, jq, ripgrep, fd-find, zip/unzip,
  tree, less, and build tools.
- Python: `python3`, `venv`, headers, pip, and uv. Use `uv venv` and
  `uv sync` per project rather than installing application dependencies
  globally.
- JavaScript: Node.js and npm for the coding-agent CLIs and project tooling.
- AI agents: Claude Code, Codex CLI, and OpenCode CLI.
- Editor setup: a default dark theme plus Python/Pylance/Ruff, Prettier,
  ESLint, YAML, and Markdown extensions. Edit `CODE_SERVER_THEME` and
  `VSCODE_EXTENSIONS` in `.env` to customize this baseline.

Add Docker CLI only if you need to control the host Docker daemon from inside
code-server. Mounting `/var/run/docker.sock` grants powerful host-level access,
so it should be an explicit opt-in rather than part of the default deployment.

## References

- [Official installation guide](https://coder.com/docs/code-server/install)
- [Official Docker image](https://hub.docker.com/r/codercom/code-server/)
- [Configuration and health-check FAQ](https://github.com/coder/code-server/blob/main/docs/FAQ.md)
- [Claude Code installation](https://support.claude.com/en/articles/14552382-your-first-day-in-claude-code)
- [Codex CLI getting started](https://help.openai.com/en/articles/11096431)
- [OpenCode installation](https://opencode.ai/v2/docs)
- [uv installation](https://docs.astral.sh/uv/getting-started/installation/)
