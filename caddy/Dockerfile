# syntax=docker/dockerfile:1

FROM caddy:2

# Baked into the image instead of bind-mounted: compose bind paths are resolved
# on the Docker host, which differs from this workspace path.
COPY Caddyfile /etc/caddy/Caddyfile
