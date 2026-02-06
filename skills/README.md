# Skills

Agent skills for extending AI coding assistants with reusable capabilities.

Skills follow the [Agent Skills](https://agentskills.io) open standard and work
across Cursor, Claude Code, Codex, and other compatible agents.

## Available Skills

### bead-memory

Persistent memory system for AI agents. Records insights, decisions, procedures,
and session summaries as beads (bd issues) so knowledge survives across sessions,
agents, and tools.

Agents use this skill proactively to remember what matters and recall it when
relevant. See [bead-memory/SKILL.md](bead-memory/SKILL.md) for details.

## Installation

Skills in this directory are project-level. To make them available globally,
symlink into your user-level skill directory:

```bash
ln -s "$(pwd)/skills/bead-memory" ~/.cursor/skills/bead-memory
ln -s "$(pwd)/skills/bead-memory" ~/.claude/skills/bead-memory
ln -s "$(pwd)/skills/bead-memory" ~/.codex/skills/bead-memory
```

## Adding a New Skill

Create a folder with a `SKILL.md` file:

```
skills/
  my-skill/
    SKILL.md          # Required: skill definition with YAML frontmatter
    scripts/          # Optional: executable scripts the agent can run
    references/       # Optional: additional docs loaded on demand
    assets/           # Optional: templates, config files, etc.
```

See the [Agent Skills docs](https://cursor.com/docs/context/skills) for the
full specification.
