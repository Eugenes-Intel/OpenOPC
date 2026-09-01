# Running OpenOPC in Docker

This runs OpenOPC — the app, the Office UI, and the Claude Code + Codex
coding agents — in a container that shares the **same state as your local
install**: the same `.opc/` home (memories, skills, projects, sessions), the
same `OpenOPC_workplace/` deliverables, and the same Claude/Codex
**subscription logins** you already set up on this PC. Switching between
"local OpenOPC" and "containerised OpenOPC" is seamless.

> **Run only one at a time.** The container and a local `opc ui` / `opc chat`
> both open `.opc/global.db` and `.opc/ui_state.db`. Stop one before starting
> the other. Also don't *resume* a session that was created on the other OS —
> stored workspace paths (`E:\...` vs `/app_workplace/...`) won't resolve.
> Starting fresh work on either side is fine.

## 1. One-time setup

**Prerequisite:** [Docker Desktop](https://www.docker.com/products/docker-desktop/) installed and running.

**Prerequisites beyond Docker:**

- You've logged in to Claude Code and Codex **on this PC already**
  (`claude auth login`, `codex login`). The container reuses those logins —
  it does not log in itself.
- Docker Desktop with the WSL2 backend (shares all drives automatically). On
  the Hyper-V backend, add the repo's drive under
  Settings → Resources → File Sharing.

**Steps:**

1. Keep these files in your OpenOPC repo folder, next to `pyproject.toml`:
   - `Dockerfile`
   - `docker-entrypoint.sh`
   - `docker-compose.yml`
   - `.dockerignore`

2. In that same folder, create a file named `.env` (just `.env`). The only
   required part is the **Native** agent's LLM key (OpenOPC's own agent, used
   by Company Mode manager/reviewer roles and Task Mode "native"):

   ```
   OPC_LLM_API_KEY=sk-or-v1-your-key-here
   OPC_LLM_MODEL=openai/gpt-5.4
   OPC_LLM_API_BASE=https://openrouter.ai/api/v1
   ```

   > Using a provider other than OpenRouter? Point `OPC_LLM_API_BASE` and
   > `OPC_LLM_MODEL` at it. If `.opc/config/llm_config.yaml` already has a key
   > (shared from your local install), you can skip this entirely.

   **Do not** put `ANTHROPIC_API_KEY` or `OPENAI_API_KEY` in `.env` — Claude
   Code and Codex authenticate from your mounted subscription logins, and an
   API key in the environment would override that and switch to metered
   billing.

   Optional additions to the same `.env` file:

   ```
   # GitHub — lets agents push code / create repos for you
   GH_TOKEN=ghp_your_token_here
   GIT_AUTHOR_NAME=Your Name
   GIT_AUTHOR_EMAIL=you@example.com

   # Email — lets the org email you progress updates (off by default)
   OPC_EMAIL_ENABLED=true
   OPC_EMAIL_CONSENT=true
   OPC_EMAIL_IMAP_HOST=imap.gmail.com
   OPC_EMAIL_IMAP_USERNAME=you@gmail.com
   OPC_EMAIL_IMAP_PASSWORD=your-16-char-app-password
   OPC_EMAIL_SMTP_HOST=smtp.gmail.com
   OPC_EMAIL_SMTP_USERNAME=you@gmail.com
   OPC_EMAIL_SMTP_PASSWORD=your-16-char-app-password
   OPC_EMAIL_FROM_ADDRESS=you@gmail.com
   OPC_EMAIL_ALLOW_FROM=you@gmail.com

   # Only if your Claude/Codex config dirs aren't in the default location
   # CLAUDE_DIR=C:\Users\you\.claude
   # CODEX_DIR=C:\Users\you\.codex
   ```

   - GitHub token: create one at https://github.com/settings/tokens (`repo` scope is enough).
   - Gmail app password (not your login password): https://myaccount.google.com/apppasswords

   `.env` is git-ignored and is excluded from the image build — OpenOPC never
   reads it, only Docker Compose does.

## 2. Build and start

Open a terminal in the repo folder and run:

```powershell
docker compose up --build
```

First run takes a few minutes (downloads Node, the Claude Code + Codex CLIs,
and Chromium). Every run after that starts in seconds.

Once you see `Office-UI running at http://0.0.0.0:8765`, open:

**http://localhost:8765**

To run it in the background instead of watching logs:
```powershell
docker compose up -d --build
```

## 3. Everyday use

| I want to... | Command |
|---|---|
| Start it | `docker compose up -d` |
| Stop it | `docker compose down` |
| View logs | `docker compose logs -f` |
| Restart after editing `.env` | `docker compose up -d --force-recreate` |
| Rebuild after pulling repo updates | `docker compose up -d --build` |
| Get a shell inside the container | `docker exec -it openopc-openopc-1 bash` |

(Container name may differ slightly — run `docker ps` to check.)

## 4. Where your files are

There is **no `data/` folder**. The container mounts your real local
directories, so everything it reads or writes is exactly what your local
OpenOPC install uses:

| Container path | Host path (bind mount) | Contents |
|---|---|---|
| `/app/.opc` | `.\.opc` (in the repo) | config, memory, skills, projects, sessions, kanban, Office-UI state, DBs |
| `/app_workplace` | `..\OpenOPC_workplace` | everything agents write: reports, code, documents |
| `/root/.claude` | `%USERPROFILE%\.claude` | Claude Code subscription login + your global skills/agents/`CLAUDE.md` |
| `/root/.codex` | `%USERPROFILE%\.codex` | Codex subscription login + `config.toml` |

Open `..\OpenOPC_workplace\<project>` in Explorer any time to grab a file. If
you've set `GH_TOKEN`, ask an agent to push it to GitHub, or do it yourself:

```powershell
docker exec -it openopc-openopc-1 bash
cd /app_workplace/<project-name>
git init && git add -A && git commit -m "First cut" && gh repo create --source=. --push
```

> Because `.opc/` is shared, anything the container does (new projects,
> sessions, memories, learned skills) is immediately visible to your local
> `opc` CLI too — and vice versa. Just don't run both at once (§1).

## 5. How authentication works

Three independent credentials:

| Agent | Credential | Where it comes from |
|---|---|---|
| **Native** (OpenOPC's own) | `OPC_LLM_API_KEY` in `.env`, or `.opc/config/llm_config.yaml` | you |
| **Claude Code** | `/root/.claude/.credentials.json` | your PC's `claude auth login` (subscription), via the `~/.claude` mount |
| **Codex** | `/root/.codex/auth.json` | your PC's `codex login` (ChatGPT subscription), via the `~/.codex` mount |

You don't log in inside the container. It reuses the logins already on this
PC. When a token refreshes during a run, the new token is written straight
back to the host file, so your local CLI stays logged in too.

**Do not** set `ANTHROPIC_API_KEY` / `OPENAI_API_KEY` in `.env` — either one
overrides the subscription login and silently switches that CLI to metered
API billing.

On startup the entrypoint prints whether each login file was found:

```
[entrypoint] Claude Code subscription login present.
[entrypoint] Codex login present (chatgpt).
```

If you see a `WARNING: ... missing` line, the bind mount is wrong or you
haven't logged in on the host yet (`claude auth login` / `codex login` in a
normal terminal, then `docker compose up -d --force-recreate`).

### Running without a Native key (add one later)

`OPC_LLM_API_KEY` may be left **blank**. OpenOPC checks for a Native
credential *per call*, so you can start keyless today and drop a key in
whenever you get one — no rebuild, no config edit:

| | No `OPC_LLM_API_KEY` | With `OPC_LLM_API_KEY` |
|---|---|---|
| **Task Mode**, agent = Claude Code / Codex | ✅ works | ✅ works |
| **Task Mode**, agent = OpenOPC Native | ❌ fails (no LLM) | ✅ works |
| **Company Mode** | ⚠️ only if *every role* is set to `execution_strategy: external` + a preferred external agent | ✅ works as designed |

Why the Company Mode caveat: the stock `corporate` org has roles on `auto`
and `native` strategy (planning / review / env-setup). Keyless, `auto` roles
fall back to rule-based selection and use an external agent only for heavier
work items — lighter "native-friendly" turns still try Native and fail. To
run `corporate` fully keyless, open **Org → Runtime**, set each role's
execution strategy to `external`, and give it a preferred agent
(`claude_code` / `codex`).

When you later add the key: put it in `.env`, run
`docker compose up -d --force-recreate`. The LLM router and Native-backed
roles light up automatically. Roles you pinned to `external` stay external
(that's a hard constraint) — flip them back to `auto` if you want smart
per-task selection again.

## 6. Adding skills or rules to the agents

Everything is already on your host — the container just sees it through the
bind mounts. Nothing to add to Docker.

**OpenOPC's own skills (Native agent only)** — `SKILL.md` folders under the
shared `.opc/`:
```
.opc/skills/my-skill/SKILL.md                       ← system-wide
.opc/projects/<project>/skills/my-skill/SKILL.md    ← one project only
```
These are the same skills your local `opc` uses.

**Claude Code's own rules/skills** — it reads your real `~/.claude` (mounted
at `/root/.claude`), so your existing global setup already applies:
```
%USERPROFILE%\.claude\skills\my-skill\SKILL.md      ← global skill
%USERPROFILE%\.claude\CLAUDE.md                     ← global rules
```

**Codex's own config** — your real `~/.codex\config.toml` (mounted at
`/root/.codex`). In Company Mode OpenOPC mirrors `~/.codex/{auth.json,
config.toml}` into `.opc/agent_homes/codex/` per run; in Task Mode Codex
reads `/root/.codex` directly. Either way your host config is what's used.

**Per-project rules** — drop the file each CLI looks for into the project
workplace (its working directory); picked up fresh every run, no restart:
```
..\OpenOPC_workplace\<project>\CLAUDE.md    ← Claude Code
..\OpenOPC_workplace\<project>\AGENTS.md    ← Codex
```

## 7. Turning agents on/off at build time

`docker-compose.yml` builds with Claude Code + Codex + Chromium; Cursor and
OpenCode are **off** (`INSTALL_CURSOR_AGENT` / `INSTALL_OPENCODE` set to
`"false"` under `build.args`). To add one back, set it to `"true"` there and
mount its config dir (`~/.cursor` / `~/.config/opencode`) the same way
`~/.claude` and `~/.codex` are mounted, then `docker compose up -d --build`.

Available flags: `INSTALL_PLAYWRIGHT`, `INSTALL_CLAUDE_CODE`, `INSTALL_CODEX`,
`INSTALL_CURSOR_AGENT`, `INSTALL_OPENCODE`.

## 8. Troubleshooting

- **Port 8765 already in use:** edit the `ports:` line in `docker-compose.yml`,
  e.g. `"9000:8765"`, then open `localhost:9000` instead.
- **"OPC is already initialized" appears on every restart:** expected — it's
  OpenOPC preserving your existing config, not an error.
- **Changed something in `.env` but it's not taking effect:** run
  `docker compose up -d --force-recreate`.
- **`WARNING: /root/.claude/.credentials.json missing`:** the `~/.claude`
  bind mount didn't resolve. On Docker Desktop / Hy-V backend, share the
  drive under Settings → Resources → File Sharing. Check `CLAUDE_DIR` in
  `.env` if your profile isn't at `%USERPROFILE%`.
- **A session created locally won't resume in the container (or vice versa):**
  expected — its stored workspace path is for the other OS. Start a new
  session; leave old ones to the OS that made them.
- **Weird DB / lock errors:** you probably have local `opc ui` running too.
  Stop it (`opc ui` Ctrl-C, check `opc runtime status`) and restart the
  container.
- **Want a clean slate:** the container holds no state of its own — reset by
  cleaning `.opc/` on the host the same way you would for a local install
  (e.g. `python scripts/reset_stuck_task.py --all --apply`).
