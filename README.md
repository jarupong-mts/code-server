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

3. Build and start the service:

   ```sh
   docker network create proxy
   docker compose up -d --build
   docker compose ps
   ```

4. Ensure Traefik is running on the external `proxy` network, then open
   <http://127.0.0.1:18080/code/> and sign in with `CODE_SERVER_PASSWORD`.

On startup, the image automatically prepares the home/workspace mount roots
and repairs nested files that are owned by another UID, including directories
that Docker or a deployment step previously created as root. The preparation
step uses the upstream image's passwordless sudo configuration; setup hooks and
code-server continue to run as the unprivileged `coder` account. No host-side
`mkdir`, `chown`, or sudo access is required.

The default runtime identity is `1000:1000`. This is enough for code-server to
work on any normal local bind mount. If the deploying account must also edit
the persisted files directly on a Linux host and uses a different numeric ID,
set these optional values once in `.env`:

```dotenv
CODE_SERVER_UID=1001
CODE_SERVER_GID=1001
```

Use `id -u` and `id -g` to find those values. The startup repair remains
automatic after setting them.

The service is reachable through Traefik at the `/code/` path and is attached
to the external Docker network named `proxy`. The Compose file does not publish
the code-server port to the host; Traefik connects to the container on port
`8080` and strips the `/code` prefix. Keep the trailing slash in the URL.
For non-local access, configure HTTPS/TLS and authentication in Traefik.

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

- The official image's default container user is UID 1000. Optional
  `CODE_SERVER_UID` and `CODE_SERVER_GID` overrides are useful only when files
  must have a different owner on the Linux host.
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
