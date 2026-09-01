#!/usr/bin/env bash
set -euo pipefail

OPC_HOME="${OPC_HOME:-/app/.opc}"
TEMPLATE_DIR="/app/config"
CONFIG_DIR="${OPC_HOME}/config"

mkdir -p "$CONFIG_DIR"

# llm_config.yaml / system_config.yaml / agent_config.yaml / channel_config.yaml
# are .gitignore'd upstream, so a fresh checkout (and therefore a fresh image)
# never ships them under .opc/config. Seed them from the repo's config/
# templates the first time the container runs against an empty volume.
for f in llm_config.yaml system_config.yaml agent_config.yaml channel_config.yaml company_corporate_config.yaml; do
  if [ -f "${TEMPLATE_DIR}/${f}" ] && [ ! -f "${CONFIG_DIR}/${f}" ]; then
    cp "${TEMPLATE_DIR}/${f}" "${CONFIG_DIR}/${f}"
    echo "[entrypoint] seeded ${f}"
  fi
done

# Provision memory/skills/logs dirs. --yes skips the overwrite prompt on an
# already-initialized home; --no-external-agent-preflight/--no-trust-external-agents
# skip checks for CLIs (claude/codex/cursor-agent/opencode) that don't exist
# inside this container by default.
opc init --yes --no-external-agent-preflight --no-trust-external-agents

# Seed LLM credentials from the environment, but ONLY into fields that are
# still empty. .opc/ is bind-mounted from the host and shared with the local
# install, so a value you later hand-edit into llm_config.yaml must survive
# every container restart.
if [ -n "${OPC_LLM_API_KEY:-}" ] || [ -n "${OPC_LLM_MODEL:-}" ] || [ -n "${OPC_LLM_API_BASE:-}" ]; then
  python3 - "$CONFIG_DIR/llm_config.yaml" <<'PYEOF'
import sys, yaml, os

path = sys.argv[1]
with open(path) as f:
    data = yaml.safe_load(f) or {}

llm = data.setdefault("llm", {})
changed = False
for env_key, cfg_key in [
    ("OPC_LLM_API_KEY", "api_key"),
    ("OPC_LLM_MODEL", "default_model"),
    ("OPC_LLM_API_BASE", "api_base"),
]:
    val = os.environ.get(env_key)
    if val and not llm.get(cfg_key):
        llm[cfg_key] = val
        changed = True

if changed:
    with open(path, "w") as f:
        yaml.safe_dump(data, f, sort_keys=False)
    print("[entrypoint] seeded empty LLM config fields from environment")
else:
    print("[entrypoint] llm_config.yaml already populated; left as-is")
PYEOF
fi

# --- Git identity + GitHub auth, so agents (and `docker exec` sessions) can
# commit and push straight from the container. ---
if [ -n "${GIT_AUTHOR_NAME:-}" ]; then
  git config --global user.name "$GIT_AUTHOR_NAME"
fi
if [ -n "${GIT_AUTHOR_EMAIL:-}" ]; then
  git config --global user.email "$GIT_AUTHOR_EMAIL"
fi
if [ -n "${GH_TOKEN:-}" ]; then
  echo "$GH_TOKEN" | gh auth login --with-token 2>&1 | grep -v '^$' || true
  gh auth setup-git 2>&1 || true
  echo "[entrypoint] GitHub CLI authenticated (gh + git push over HTTPS enabled)"
fi

# --- Optional: wire up the built-in email channel from environment vars so
# an org can proactively email you progress updates (and you can email tasks
# back to it). Needs both IMAP (to receive) and SMTP (to send) credentials —
# e.g. a Gmail app password. Leave OPC_EMAIL_ENABLED unset to skip this. ---
if [ "${OPC_EMAIL_ENABLED:-false}" = "true" ]; then
  python3 - "$CONFIG_DIR/channel_config.yaml" <<'PYEOF'
import sys, yaml, os

path = sys.argv[1]
with open(path) as f:
    data = yaml.safe_load(f) or {}

email = data.setdefault("channels", {}).setdefault("email", {})
email["enabled"] = True
email["consent_granted"] = os.environ.get("OPC_EMAIL_CONSENT", "false").lower() == "true"
for env_key, cfg_key in [
    ("OPC_EMAIL_IMAP_HOST", "imap_host"),
    ("OPC_EMAIL_IMAP_USERNAME", "imap_username"),
    ("OPC_EMAIL_IMAP_PASSWORD", "imap_password"),
    ("OPC_EMAIL_SMTP_HOST", "smtp_host"),
    ("OPC_EMAIL_SMTP_USERNAME", "smtp_username"),
    ("OPC_EMAIL_SMTP_PASSWORD", "smtp_password"),
    ("OPC_EMAIL_FROM_ADDRESS", "from_address"),
]:
    if os.environ.get(env_key):
        email[cfg_key] = os.environ[env_key]

allow_from = os.environ.get("OPC_EMAIL_ALLOW_FROM", "")
if allow_from:
    email["allow_from"] = [a.strip() for a in allow_from.split(",") if a.strip()]

with open(path, "w") as f:
    yaml.safe_dump(data, f, sort_keys=False)
print("[entrypoint] applied email channel config from environment")
PYEOF
  if [ "${OPC_EMAIL_CONSENT:-false}" != "true" ]; then
    echo "[entrypoint] WARNING: OPC_EMAIL_ENABLED=true but OPC_EMAIL_CONSENT is not 'true' -- the email channel will refuse to start until you set OPC_EMAIL_CONSENT=true (this is an explicit consent gate, not a bug)."
  fi
fi

# --- Subscription-auth sanity check. Claude Code reads
# /root/.claude/.credentials.json and Codex reads /root/.codex/auth.json,
# both bind-mounted from this PC's logins. OpenOPC's preflight does NOT
# verify agent login state, so this is the only early warning. Non-fatal. ---
if [ ! -f /root/.claude/.credentials.json ]; then
  echo "[entrypoint] WARNING: /root/.claude/.credentials.json missing -- Claude Code has no subscription login. Check the ~/.claude bind mount, or run 'claude auth login' on the host."
else
  echo "[entrypoint] Claude Code subscription login present."
fi
if [ ! -f /root/.codex/auth.json ]; then
  echo "[entrypoint] WARNING: /root/.codex/auth.json missing -- Codex has no login. Check the ~/.codex bind mount, or run 'codex login' on the host."
else
  echo "[entrypoint] Codex login present ($(python3 -c "import json;print(json.load(open('/root/.codex/auth.json')).get('auth_mode','?'))" 2>/dev/null || echo '?'))."
fi

# --- Seed ~/.claude.json (non-credential Claude Code state: trusted dirs,
# project history, MCP config). It lives NEXT TO the ~/.claude dir we mount,
# not inside it, so it isn't shared -- and it must not be: the host rewrites
# it on every Claude Code action, so a shared copy would race and corrupt.
# Instead seed a container-local copy from the newest host backup (mounted
# read-only under ~/.claude/backups) so Claude Code starts configured rather
# than re-running first-run setup. This copy is never written back. ---
if [ ! -f /root/.claude.json ]; then
  seeded=""
  for f in $(ls -1t /root/.claude/backups/.claude.json.backup.* 2>/dev/null || true); do
    # skip stub/empty backups (a valid one is tens of KB)
    if [ "$(wc -c < "$f" 2>/dev/null || echo 0)" -gt 1024 ]; then
      cp "$f" /root/.claude.json
      echo "[entrypoint] seeded /root/.claude.json from $(basename "$f") (container-local, not written back)"
      seeded=1
      break
    fi
  done
  if [ -z "$seeded" ]; then
    echo '{}' > /root/.claude.json
    echo "[entrypoint] wrote empty /root/.claude.json (no usable host backup found)"
  fi
fi

exec "$@"

