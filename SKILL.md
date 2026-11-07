---
name: skill-installer
description: |
  Install, inspect, and manage OpenClaw/Claude Code skills from GitHub repositories.
  Use when: (1) user shares a GitHub link to a skill repo, (2) asks to install a skill,
  (3) asks to read/review a repo, (4) asks "what does this repo do",
  (5) asks to update an existing skill from GitHub, (6) asks to list installed skills.
  Triggers: "install skill", "add skill", "clone skill", "скачай скилл", "установи скилл",
  "what's in this repo", "read this repo", "review repo", "update skill",
  GitHub URLs (github.com/*/), "git clone", "list skills", "installed skills".
---

# Skill Installer

Install and manage skills from GitHub. No GitHub auth needed for public repos.

## Install a skill from GitHub

```bash
bash scripts/install.sh <github-url> [--name custom-name]
```

What it does:
1. Clones the repo to a temp directory
2. Validates: checks for SKILL.md (required), scripts/, references/
3. Reads SKILL.md frontmatter to extract skill name
4. Copies to `~/.openclaw/workspace/skills/<name>/`
5. Sets permissions: `chmod +x scripts/*.sh` (if scripts/ exists)
6. Cleans up temp directory
7. Reports: name, description, files installed, dependencies

### Examples

```bash
# Install by GitHub URL
bash scripts/install.sh https://github.com/qwwiwi/instagram-superpowers --path skills/instagram-loore

# Install with custom name
bash scripts/install.sh https://github.com/user/repo --name my-instagram

# Install from a subdirectory (monorepo with multiple skills)
bash scripts/install.sh https://github.com/user/repo --path skills/weather

# Update existing skill (overwrites)
bash scripts/install.sh https://github.com/qwwiwi/instagram-superpowers --path skills/instagram-loore --force
```

## Read / inspect a repo without installing

```bash
bash scripts/install.sh <github-url> --inspect
```

Clones to temp, prints structure, SKILL.md content, scripts list, then cleans up. Does not install.

## List installed skills

```bash
bash scripts/install.sh --list
```

Shows all skills in `~/.openclaw/workspace/skills/` with name and description from frontmatter.

## Remove a skill

```bash
bash scripts/install.sh --remove <skill-name>
```

Removes skill directory after confirmation.

## How it works

- Public repos: `git clone` over HTTPS — no auth needed
- Private repos: requires `gh` CLI authenticated or SSH keys
- Validation: SKILL.md must exist with `name` and `description` in YAML frontmatter
- No git history copied: uses `--depth 1` for speed
- Skills directory: `~/.openclaw/workspace/skills/` (configurable via `SKILLS_DIR` env)

## Dependencies

- `git` — cloning repos
- `grep`, `sed` — parsing frontmatter

Optional:
- `gh` — for private repos only
