# Using OpenOPC — A Simple Guide

OpenOPC is an AI company you run from your browser. You give it a goal, it
builds a small team of AI "employees" (or uses a single agent for quick
tasks), and it works until the job is done. This guide covers the everyday
basics — not every feature, just what you need to get going.

Everything below assumes OpenOPC is already running at **http://localhost:8765**.
(If it's not, see `INSTRUCTIONS.md`.)

---

## The two modes

Every new chat starts with a choice:

| Mode | Use it when... | What happens |
|---|---|---|
| **Task Mode** | You have one clear, contained job — fix a bug, write a script, research a topic. | A single agent (OpenOPC Native, Codex, Claude Code, Cursor, or OpenCode) does the work directly. |
| **Company Mode** | The job is bigger or fuzzier — "build me an app," "write an investment memo," "produce a short video." | OpenOPC assembles a small team (CEO, CTO, engineers, reviewers, etc.), splits the work, and runs it as a project. |

If you're not sure which to pick: small, well-defined task → **Task Mode**.
Anything that sounds like a whole project → **Company Mode**.

---

## Your first run

1. Open **http://localhost:8765**.
2. Pick or create a **project** (top of the screen) — this is just a folder
   to keep related work together.
3. Click **New Chat**.
4. Choose **Task** or **Company**.
   - Task Mode: also pick which agent should do the work.
   - Company Mode: pick **Corporate** (the built-in default team) or a saved
     organization if you've made/imported one.
5. Type your brief and send it.

That's it — once you send the first message, the mode is locked for that
chat. Start a new chat to switch modes.

---

## The three pages

| Page | What it's for |
|---|---|
| **Workspace** | Your main screen — chat, kanban board of tasks, and progress panels. You'll live here most of the time. |
| **Office** | A visual office map. Each AI employee shows up as a little character you can click to see what they're doing right now. |
| **Org** | Where you design the team — add/remove roles, hire specialists, save an organization for reuse. |

---

## Watching progress

- **Chat tab** — the running conversation and status updates.
- **Agents tab** — see which role is working, waiting, or done, and what
  tool they're currently using.
- **Kanban board** — tasks move left to right: Todo → In Progress → Review → Done.
- **Office page** — a literal animated view of your team at their desks.

If something needs your input (a decision, an approval, a blocker only you
can resolve), OpenOPC pauses and asks — check the Chat tab.

---

## Building a team (Company Mode)

You don't have to design a team from scratch every time — **Corporate** is a
sensible default with a CEO, CTO, engineers, and reviewers already set up.

If you want a custom team:
1. Go to **Org → New organization**.
2. Give it a name, add at least two roles, and set who reports to whom.
3. Save — it now appears as an option whenever you start a Company Mode chat.

To bring in a pre-made specialist instead of writing one from scratch:
1. **Org → Employees**, search the talent library.
2. Click **Hire**, assign them to a role.
3. (Optional) **Team Roster → Deploy** to make them show up on the Office page.

---

## Finding your files

Agents don't write into the chat only — real deliverables (code, reports,
documents) get saved to disk. If you're running the Docker setup from
`INSTRUCTIONS.md`, that's the `data/workplace/<project>/` folder right next
to your `docker-compose.yml` — just open it in Explorer.

---

## Saving or sharing a whole organization

Built a team you like and want to reuse it later, hand it to a teammate, or
back it up? From a terminal:

```bash
opc org export --json > my-org.yaml
```

That produces one file with the whole team definition — roles, reporting
lines, everything. Someone else (or future you) can load it with:

```bash
opc market install my-org.yaml
```

If you're running via the Docker setup, run these inside the container:
```bash
docker exec -it openopc-openopc-1 opc org export --json > my-org.yaml
```

---

## Basic commands (if you'd rather use the terminal)

Everything above is also available from the command line, in case you want
to script something or don't want the browser open.

```bash
opc chat                          # interactive chat in the terminal
opc project list                  # see your projects
opc project create demo           # start a new project
opc session list -p demo          # see running/past sessions in a project
opc runtime status -p demo        # what's currently running
```

Inside `opc chat`, handy slash commands:
```
/status              # what's OpenOPC doing right now
/mode task           # switch to Task Mode
/mode company corporate   # switch to Company Mode with the default team
/project switch demo
```

---

## Quick troubleshooting

- **Nothing happens after I send a message** — check the Chat tab; OpenOPC
  may be waiting for an approval or a decision from you.
- **I want to stop a running job** — open the session and use the Stop
  control in the Team tab (Company Mode) or the task's right panel (Task Mode).
- **I picked the wrong mode** — you can't switch mid-chat; just start a new one.
- **An external agent (Codex/Claude Code/Cursor/OpenCode) isn't showing up
  as an option** — it isn't installed/detected. If you're on the Docker
  setup, check `INSTRUCTIONS.md` section 5.
