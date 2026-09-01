# syntax=docker/dockerfile:1

########################################
# Stage 1: build the Office UI frontend
########################################
FROM node:20-slim AS frontend

WORKDIR /src
COPY opc/plugins/office_ui/frontend_src/package*.json ./
RUN npm install
COPY opc/plugins/office_ui/frontend_src/ ./
RUN npm run build
# vite.config.ts sets build.outDir to "../frontend_dist", i.e. /frontend_dist


########################################
# Stage 2: runtime image
########################################
FROM python:3.12-slim AS runtime

# Set to "false" to skip the Chromium download if you don't need OpenOPC's
# browser tools (browser_navigate, browser_click, etc.).
ARG INSTALL_PLAYWRIGHT=true
# Set any of these to "false" to skip installing that external agent CLI.
ARG INSTALL_CLAUDE_CODE=true
ARG INSTALL_CODEX=true
ARG INSTALL_CURSOR_AGENT=true
ARG INSTALL_OPENCODE=true

WORKDIR /app

# curl/gnupg: agent installers. git: git_status/git_commit tools and pushing
# to GitHub. Node 20: runtime for claude/codex/opencode CLIs.
#
# gh is installed from its GitHub release .deb rather than the
# cli.github.com apt repo -- that repo intermittently 404s its Release file
# (seen 2026-09-01), and the .deb has no external repo dependency. Override
# the version with --build-arg GH_CLI_VERSION=x.y.z; "latest" resolves via
# the unauthenticated releases API (60 req/h/IP -- ample for image builds).
ARG GH_CLI_VERSION=latest
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl \
        ca-certificates \
        gnupg \
        git \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && if [ "$GH_CLI_VERSION" = "latest" ]; then \
         GH_CLI_VERSION="$(curl -fsSL https://api.github.com/repos/cli/cli/releases/latest \
           | grep -m1 '"tag_name"' | sed -E 's/.*"v?([^"]+)".*/\1/')"; \
       fi \
    && echo "Installing gh ${GH_CLI_VERSION}" \
    && curl -fsSL -o /tmp/gh.deb \
        "https://github.com/cli/cli/releases/download/v${GH_CLI_VERSION}/gh_${GH_CLI_VERSION}_linux_$(dpkg --print-architecture).deb" \
    && apt-get install -y --no-install-recommends /tmp/gh.deb \
    && rm -f /tmp/gh.deb \
    && rm -rf /var/lib/apt/lists/*

# --- External agent CLIs (opc init preflight looks for: claude, codex,
# cursor-agent, opencode on PATH) ---
RUN if [ "$INSTALL_CLAUDE_CODE" = "true" ]; then npm install -g @anthropic-ai/claude-code; fi
RUN if [ "$INSTALL_CODEX" = "true" ]; then npm install -g @openai/codex; fi
RUN if [ "$INSTALL_OPENCODE" = "true" ]; then npm install -g opencode-ai; fi
# Cursor's official installer ships a binary literally named `agent`, but
# OpenOPC's default agent_config.yaml looks for `cursor-agent` on PATH — so
# symlink it. If Cursor changes their install layout, this step becomes a
# no-op and you'll need to set `command: agent` under `cursor:` in
# .opc/config/agent_config.yaml instead.
RUN if [ "$INSTALL_CURSOR_AGENT" = "true" ]; then \
        curl -fsSL https://cursor.com/install | bash; \
        AGENT_BIN=$(find /root /usr/local /opt -maxdepth 6 -type f -name agent 2>/dev/null | head -n1); \
        if [ -n "$AGENT_BIN" ]; then ln -sf "$AGENT_BIN" /usr/local/bin/cursor-agent; fi; \
    fi

# Copy just the manifest first so dependency installs are cached across
# rebuilds that only touch application code.
COPY pyproject.toml README.md ./

COPY . .

# --retries/--timeout: the dependency tree is large (chromadb, litellm,
# playwright...) and files.pythonhosted.org occasionally stalls mid-wheel;
# without this a single slow download fails the whole build.
RUN pip install --no-cache-dir --retries 5 --timeout 120 -e .

RUN if [ "$INSTALL_PLAYWRIGHT" = "true" ]; then \
        python -m playwright install --with-deps chromium; \
    fi

# Drop in the pre-built frontend bundle so `opc ui` never needs Node at
# runtime (it only rebuilds if frontend_src is newer than frontend_dist).
COPY --from=frontend /frontend_dist ./opc/plugins/office_ui/frontend_dist

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# IS_SANDBOX=1: the container runs as root, and the Claude Code CLI refuses
# --dangerously-skip-permissions (which OpenOPC passes to run agents
# unattended) under uid 0 unless it believes it's in a sandbox. A container
# with no host network namespace and only explicit bind mounts is exactly
# that. Codex has no equivalent guard.
ENV OPC_HOME=/app/.opc \
    PYTHONUNBUFFERED=1 \
    HOME=/root \
    IS_SANDBOX=1

EXPOSE 8765

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s \
    CMD curl -fsS http://localhost:8765/ || exit 1

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["opc", "ui", "--port", "8765", "--host", "0.0.0.0"]
