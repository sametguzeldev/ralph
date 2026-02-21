# Ralph

![Ralph](ralph.webp)

Ralph is an autonomous AI agent loop that runs AI coding tools ([Amp](https://ampcode.com) or [Claude Code](https://docs.anthropic.com/en/docs/claude-code)) repeatedly until all PRD items are complete. Each iteration is a fresh instance with clean context. Memory persists via git history, `progress.txt`, and `prd.json`.

Based on [Geoffrey Huntley's Ralph pattern](https://ghuntley.com/ralph/).

[Read my in-depth article on how I use Ralph](https://x.com/ryancarson/status/2008548371712135632)

## Prerequisites

- One of the following AI coding tools installed and authenticated:
  - [Amp CLI](https://ampcode.com) (default)
  - [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (`npm install -g @anthropic-ai/claude-code`)
- `jq` installed (`brew install jq` on macOS)
- A git repository for your project

## Setup

### Option 1: Copy to your project

Copy the ralph files into your project:

```bash
# From your project root
mkdir -p scripts/ralph

# For Amp:
cp /path/to/ralph/ralph.sh scripts/ralph/
cp /path/to/ralph/prompt.md scripts/ralph/prompt.md

# For Claude Code:
cp /path/to/ralph/ralph-cc.sh scripts/ralph/
cp /path/to/ralph/CLAUDE.md scripts/ralph/CLAUDE.md

chmod +x scripts/ralph/ralph.sh scripts/ralph/ralph-cc.sh
```

### Option 2: Install skills globally (Amp)

Copy the skills to your Amp or Claude config for use across all projects:

For AMP
```bash
cp -r skills/prd ~/.config/amp/skills/
cp -r skills/ralph ~/.config/amp/skills/
```

For Claude Code (manual)
```bash
cp -r skills/prd-questions ~/.claude/skills/
cp -r skills/prd ~/.claude/skills/
cp -r skills/ralph ~/.claude/skills/
```

### Option 3: Use as Claude Code Marketplace

Add the Ralph marketplace to Claude Code:

```bash
/plugin marketplace add snarktank/ralph
```

Then install the skills:

```bash
/plugin install ralph-skills@ralph-marketplace
```

Available skills after installation:
- `/prd-questions` - Generate clarifying questions for a feature
- `/prd` - Generate PRD from answered questions
- `/ralph` - Convert PRDs to prd.json format

Skills are automatically invoked when you ask Claude to:
- "prd questions for", "clarifying questions for", "what questions for"
- "create a prd", "write prd for", "plan this feature"
- "convert this prd", "turn into ralph format", "create prd.json"

### Configure Amp auto-handoff (recommended)

Add to `~/.config/amp/settings.json`:

```json
{
  "amp.experimental.autoHandoff": { "context": 90 }
}
```

This enables automatic handoff when context fills up, allowing Ralph to handle large stories that exceed a single context window.

## Workflow

Each step can be run non-interactively with `claude -p` (add `--dangerously-skip-permissions` for fully autonomous operation), or interactively in a Claude Code session.

### 1. Generate clarifying questions

```bash
claude -p "Load the prd-questions skill and generate questions for [your feature description]" --dangerously-skip-permissions
```

This saves questions to `tasks/prd-questions-[feature-name].md`. Open the file and fill in your answers.

If your answers raise new questions, re-run pointing at the same file:

```bash
claude -p "Load the prd-questions skill and follow up on tasks/prd-questions-[feature-name].md" --dangerously-skip-permissions
```

It will read your answers, identify gaps, and append follow-up questions. Repeat until satisfied.

### 2. Create a PRD

```bash
claude -p "Load the prd skill and generate a PRD from tasks/prd-questions-[feature-name].md" --dangerously-skip-permissions
```

The skill reads your answers and generates a structured PRD at `tasks/prd-[feature-name].md`.

### 3. Convert PRD to Ralph format

```bash
claude -p "Load the ralph skill and convert tasks/prd-[feature-name].md to prd.json" --dangerously-skip-permissions
```

This creates `prd.json` with user stories structured for autonomous execution.

### 4. Run Ralph

```bash
# Using Claude Code (recommended)
./scripts/ralph/ralph-cc.sh [max_iterations]

# Using Amp
./scripts/ralph/ralph.sh [max_iterations]

# Using Claude Code (legacy, pipes CLAUDE.md as stdin)
./scripts/ralph/ralph.sh --tool claude [max_iterations]
```

Default is 10 iterations.

Ralph will:
1. Create a feature branch (from PRD `branchName`)
2. Pick the highest priority story where `passes: false`
3. Implement that single story
4. Run quality checks (typecheck, tests)
5. Commit if checks pass
6. Update `prd.json` to mark story as `passes: true`
7. Append learnings to `progress.txt`
8. Repeat until all stories pass or max iterations reached

## Key Files

| File | Purpose |
|------|---------|
| `ralph-cc.sh` | Claude Code agent loop using `claude -p` with proper skill/project integration |
| `ralph.sh` | Legacy bash loop that supports both Amp (`--tool amp`) and Claude Code (`--tool claude`) |
| `prompt.md` | Prompt template for Amp |
| `CLAUDE.md` | Prompt template for Claude Code |
| `prd.json` | User stories with `passes` status (the task list) |
| `prd.json.example` | Example PRD format for reference |
| `progress.txt` | Append-only learnings for future iterations |
| `skills/prd-questions/` | Skill for generating clarifying questions before writing a PRD |
| `skills/prd/` | Skill for generating PRDs from answered questions |
| `skills/ralph/` | Skill for converting PRDs to JSON (works with Amp and Claude Code) |
| `.claude-plugin/` | Plugin manifest for Claude Code marketplace discovery |
| `flowchart/` | Interactive visualization of how Ralph works |

## Flowchart

[![Ralph Flowchart](ralph-flowchart.png)](https://snarktank.github.io/ralph/)

**[View Interactive Flowchart](https://snarktank.github.io/ralph/)** - Click through to see each step with animations.

The `flowchart/` directory contains the source code. To run locally:

```bash
cd flowchart
npm install
npm run dev
```

## Critical Concepts

### Each Iteration = Fresh Context

Each iteration spawns a **new AI instance** (Amp or Claude Code) with clean context. The only memory between iterations is:
- Git history (commits from previous iterations)
- `progress.txt` (learnings and context)
- `prd.json` (which stories are done)

### Parallel Execution

Ralph automatically runs stories in **parallel** when they share the same `priority` number. Each story gets its own git worktree via `claude --worktree`, so their code changes never clobber each other.

```
priority 1 — schema migration                    ← runs alone first
priority 2 — UI component A (independent)        ← these two run
priority 2 — UI component B (independent)        ←   simultaneously
priority 3 — dashboard view (depends on A + B)   ← runs alone after
```

After all worktrees in a wave finish, Ralph merges them back sequentially. If two stories edited the same file and a merge conflict occurs, the conflicting story is skipped and retried in the next iteration.

The orchestrator (`ralph-cc.sh`) handles `prd.json` updates and `progress.txt` in parallel mode — agents only commit their code changes and output a `<story-done>US-XXX</story-done>` signal.

**Rule:** Only assign the same priority to stories that edit completely different files. Parallel stories that touch the same file will conflict on merge.

### Small Tasks

Each PRD item should be small enough to complete in one context window. If a task is too big, the LLM runs out of context before finishing and produces poor code.

Right-sized stories:
- Add a database column and migration
- Add a UI component to an existing page
- Update a server action with new logic
- Add a filter dropdown to a list

Too big (split these):
- "Build the entire dashboard"
- "Add authentication"
- "Refactor the API"

### AGENTS.md Updates Are Critical

After each iteration, Ralph updates the relevant `AGENTS.md` files with learnings. This is key because AI coding tools automatically read these files, so future iterations (and future human developers) benefit from discovered patterns, gotchas, and conventions.

Examples of what to add to AGENTS.md:
- Patterns discovered ("this codebase uses X for Y")
- Gotchas ("do not forget to update Z when changing W")
- Useful context ("the settings panel is in component X")

### Feedback Loops

Ralph only works if there are feedback loops:
- Typecheck catches type errors
- Tests verify behavior
- CI must stay green (broken code compounds across iterations)

### Browser Verification for UI Stories

Frontend stories must include "Verify in browser using dev-browser skill" in acceptance criteria. Ralph will use the dev-browser skill to navigate to the page, interact with the UI, and confirm changes work.

### Stop Condition

When all stories have `passes: true`, Ralph outputs `<promise>COMPLETE</promise>` and the loop exits.

## Debugging

If a parallel run was interrupted, any leftover worktrees are cleaned up automatically the next time `ralph-cc.sh` starts.

Check current state:

```bash
# See which stories are done
cat prd.json | jq '.userStories[] | {id, title, passes}'

# See learnings from previous iterations
cat progress.txt

# Check git history
git log --oneline -10
```

## Customizing the Prompt

After copying `prompt.md` (for Amp) or `CLAUDE.md` (for Claude Code) to your project, customize it for your project:
- Add project-specific quality check commands
- Include codebase conventions
- Add common gotchas for your stack

## Archiving

Ralph automatically archives previous runs when you start a new feature (different `branchName`). Archives are saved to `archive/YYYY-MM-DD-feature-name/`.

## References

- [Geoffrey Huntley's Ralph article](https://ghuntley.com/ralph/)
- [Amp documentation](https://ampcode.com/manual)
- [Claude Code documentation](https://docs.anthropic.com/en/docs/claude-code)
