#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly DEFAULT_SKILLS_DIR="${SKILLS_DIR:-$HOME/.openclaw/workspace/skills}"
readonly TMP_DIR="${TMPDIR:-/tmp}/skill-installer-$$"

# --- helpers ---

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME <github-url> [options]
       $SCRIPT_NAME --list
       $SCRIPT_NAME --remove <skill-name>

Install skills from GitHub repositories.

Commands:
  <github-url>            Install skill from GitHub repo
  --list                  List installed skills
  --remove <name>         Remove installed skill

Install Options:
  --name <name>           Custom skill name (default: from SKILL.md)
  --path <subdir>         Subdirectory in repo containing the skill
  --force                 Overwrite existing skill
  --inspect               Read and inspect only (don't install)
  --skills-dir <dir>      Skills directory (default: $DEFAULT_SKILLS_DIR)

Examples:
  $SCRIPT_NAME https://github.com/qwwiwi/instagram-superpowers --path skills/instagram-loore
  $SCRIPT_NAME https://github.com/user/repo --name my-skill
  $SCRIPT_NAME https://github.com/user/monorepo --path skills/weather
  $SCRIPT_NAME https://github.com/user/repo --inspect
  $SCRIPT_NAME --list
  $SCRIPT_NAME --remove old-skill
EOF
    exit 0
}

die() { echo "ERROR: $*" >&2; cleanup; exit 1; }
info() { echo ":: $*"; }
success() { echo "OK: $*"; }

cleanup() {
    [[ -d "$TMP_DIR" ]] && rm -rf "$TMP_DIR" 2>/dev/null || true
}
trap cleanup EXIT

check_deps() {
    command -v git >/dev/null 2>&1 || die "git is required but not installed"
}

# Extract field from YAML frontmatter
extract_frontmatter() {
    local file="$1"
    local field="$2"
    # Handle both "field: value" and "field: |" (multiline)
    sed -n '/^---$/,/^---$/p' "$file" | grep -E "^${field}:" | head -1 | sed "s/^${field}:[[:space:]]*//" | sed 's/^["|'"'"']//' | sed 's/["|'"'"']$//'
}

# Extract full description (handles multiline)
extract_description() {
    local file="$1"
    python3 -c "
import sys
in_front = False
in_desc = False
desc_lines = []
for line in open('$file'):
    stripped = line.strip()
    if stripped == '---':
        if in_front:
            break
        in_front = True
        continue
    if not in_front:
        continue
    if stripped.startswith('description:'):
        rest = stripped[len('description:'):].strip()
        if rest and rest not in ('|', '>'):
            print(rest.strip('\"').strip(\"'\"))
            sys.exit()
        in_desc = True
        continue
    if in_desc:
        if line[0] not in (' ', '\t') and stripped:
            break
        desc_lines.append(stripped)
if desc_lines:
    print(' '.join(desc_lines)[:200])
" 2>/dev/null || extract_frontmatter "$file" "description"
}

normalize_url() {
    local url="$1"
    # Remove trailing slash
    url="${url%/}"
    # Add .git if missing
    if [[ "$url" != *.git ]]; then
        url="${url}.git"
    fi
    echo "$url"
}

# --- commands ---

cmd_list() {
    local skills_dir="$1"
    
    if [[ ! -d "$skills_dir" ]]; then
        die "Skills directory not found: $skills_dir"
    fi

    local count=0
    printf "%-30s %s\n" "SKILL" "DESCRIPTION"
    printf "%s\n" "$(printf '%.0s-' {1..80})"

    for skill_dir in "$skills_dir"/*/; do
        [[ ! -d "$skill_dir" ]] && continue
        local skill_md="${skill_dir}SKILL.md"
        local name=$(basename "$skill_dir")
        local desc="(no SKILL.md)"

        if [[ -f "$skill_md" ]]; then
            local extracted
            extracted=$(extract_description "$skill_md" 2>/dev/null || echo "")
            [[ -n "$extracted" ]] && desc="${extracted:0:60}"
        fi

        printf "%-30s %s\n" "$name" "$desc"
        count=$((count + 1))
    done

    echo ""
    echo "Total: $count skills in $skills_dir"
}

cmd_remove() {
    local skill_name="$1"
    local skills_dir="$2"
    local target="${skills_dir}/${skill_name}"

    if [[ ! -d "$target" ]]; then
        die "Skill not found: $skill_name (looked in $target)"
    fi

    info "Removing skill: $skill_name"
    info "Directory: $target"
    
    local file_count
    file_count=$(find "$target" -type f | wc -l | tr -d ' ')
    info "Files: $file_count"

    rm -rf "$target"
    success "Skill '$skill_name' removed"
}

cmd_inspect() {
    local repo_dir="$1"
    local skill_md="${repo_dir}/SKILL.md"

    echo ""
    echo "=== Repository Structure ==="
    find "$repo_dir" -not -path '*/\.git/*' -not -path '*/\.git' -type f | sed "s|${repo_dir}/||" | sort

    echo ""
    if [[ -f "$skill_md" ]]; then
        echo "=== SKILL.md ==="
        cat "$skill_md"
    else
        echo "WARNING: No SKILL.md found"
    fi

    echo ""
    echo "=== Scripts ==="
    if [[ -d "${repo_dir}/scripts" ]]; then
        for f in "${repo_dir}/scripts/"*; do
            [[ -f "$f" ]] && echo "  $(basename "$f") ($(wc -l < "$f" | tr -d ' ') lines)"
        done
    else
        echo "  (none)"
    fi

    echo ""
    echo "=== References ==="
    if [[ -d "${repo_dir}/references" ]]; then
        for f in "${repo_dir}/references/"*; do
            [[ -f "$f" ]] && echo "  $(basename "$f") ($(wc -l < "$f" | tr -d ' ') lines)"
        done
    else
        echo "  (none)"
    fi
}

cmd_install() {
    local url="$1"
    local custom_name="$2"
    local subpath="$3"
    local force="$4"
    local inspect_only="$5"
    local skills_dir="$6"

    # Clone
    local git_url
    git_url=$(normalize_url "$url")
    
    info "Cloning $git_url ..."
    mkdir -p "$TMP_DIR"
    git clone --depth 1 --quiet "$git_url" "${TMP_DIR}/repo" 2>&1 || die "Failed to clone $git_url"

    # Determine skill root
    local skill_root="${TMP_DIR}/repo"
    if [[ -n "$subpath" ]]; then
        skill_root="${skill_root}/${subpath}"
        [[ ! -d "$skill_root" ]] && die "Subdirectory not found: $subpath"
    fi

    # Inspect mode
    if [[ "$inspect_only" == "true" ]]; then
        cmd_inspect "$skill_root"
        return
    fi

    # Validate SKILL.md
    local skill_md="${skill_root}/SKILL.md"
    [[ ! -f "$skill_md" ]] && die "No SKILL.md found in repo. Not a valid skill."

    # Extract name
    local skill_name
    if [[ -n "$custom_name" ]]; then
        skill_name="$custom_name"
    else
        skill_name=$(extract_frontmatter "$skill_md" "name" | tr -d '"' | tr -d "'")
        [[ -z "$skill_name" ]] && skill_name=$(basename "$url" .git)
    fi

    # Sanitize name
    skill_name=$(echo "$skill_name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//')

    local target_dir="${skills_dir}/${skill_name}"

    # Check existing
    if [[ -d "$target_dir" && "$force" != "true" ]]; then
        die "Skill '$skill_name' already exists at $target_dir. Use --force to overwrite."
    fi

    # Extract description
    local description
    description=$(extract_description "$skill_md" 2>/dev/null || echo "(no description)")

    info "Installing skill: $skill_name"
    info "Description: ${description:0:100}"
    info "Target: $target_dir"

    # Copy files (exclude .git)
    [[ -d "$target_dir" ]] && rm -rf "$target_dir"
    mkdir -p "$target_dir"
    
    # Copy everything except .git
    (cd "$skill_root" && find . -not -path './.git/*' -not -path './.git' -not -name '.git' | while read -r f; do
        if [[ -d "$skill_root/$f" ]]; then
            mkdir -p "$target_dir/$f"
        else
            cp "$skill_root/$f" "$target_dir/$f"
        fi
    done)

    # Set permissions on scripts
    if [[ -d "${target_dir}/scripts" ]]; then
        chmod +x "${target_dir}/scripts/"*.sh 2>/dev/null || true
        chmod +x "${target_dir}/scripts/"*.py 2>/dev/null || true
    fi

    # Report
    echo ""
    success "Skill '$skill_name' installed"
    echo ""
    echo "  Name:        $skill_name"
    echo "  Description: ${description:0:100}"
    echo "  Location:    $target_dir"
    echo ""
    echo "  Files:"
    find "$target_dir" -type f -not -path '*/.git/*' | sed "s|${target_dir}/|    |" | sort
    
    # Check dependencies
    echo ""
    if grep -q "curl" "$skill_md" 2>/dev/null; then
        if command -v curl >/dev/null 2>&1; then
            echo "  [ok] curl"
        else
            echo "  [!!] curl — not installed"
        fi
    fi
    if grep -q "jq" "$skill_md" 2>/dev/null; then
        if command -v jq >/dev/null 2>&1; then
            echo "  [ok] jq"
        else
            echo "  [!!] jq — not installed (brew install jq / apt install jq)"
        fi
    fi
    if grep -q "python3\|python" "$skill_md" 2>/dev/null; then
        if command -v python3 >/dev/null 2>&1; then
            echo "  [ok] python3"
        else
            echo "  [!!] python3 — not installed"
        fi
    fi
    if grep -q "ffmpeg" "$skill_md" 2>/dev/null; then
        if command -v ffmpeg >/dev/null 2>&1; then
            echo "  [ok] ffmpeg"
        else
            echo "  [!!] ffmpeg — not installed"
        fi
    fi

    # Check for env vars / API keys mentioned
    local env_vars
    env_vars=$(grep -oE '[A-Z_]{3,}_KEY|[A-Z_]{3,}_TOKEN|[A-Z_]{3,}_SECRET' "$skill_md" 2>/dev/null | sort -u || true)
    if [[ -n "$env_vars" ]]; then
        echo ""
        echo "  Required env vars / API keys:"
        echo "$env_vars" | while read -r var; do
            if [[ -n "${!var:-}" ]]; then
                echo "    [ok] $var"
            else
                echo "    [!!] $var — not set"
            fi
        done
    fi
}

# --- main ---

main() {
    check_deps

    [[ $# -eq 0 ]] && usage

    local url="" custom_name="" subpath="" force="false" inspect_only="false"
    local skills_dir="$DEFAULT_SKILLS_DIR"
    local cmd=""
    local cmd_arg=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)       usage ;;
            --list)          cmd="list" ;;
            --remove)        cmd="remove"; cmd_arg="${2:-}"; shift ;;
            --name|-n)       custom_name="$2"; shift ;;
            --path|-p)       subpath="$2"; shift ;;
            --force|-f)      force="true" ;;
            --inspect)       inspect_only="true" ;;
            --skills-dir)    skills_dir="$2"; shift ;;
            -*)              die "Unknown option: $1" ;;
            *)               url="$1" ;;
        esac
        shift
    done

    case "$cmd" in
        list)
            cmd_list "$skills_dir"
            ;;
        remove)
            [[ -z "$cmd_arg" ]] && die "Skill name required"
            cmd_remove "$cmd_arg" "$skills_dir"
            ;;
        *)
            [[ -z "$url" ]] && die "GitHub URL required"
            cmd_install "$url" "$custom_name" "$subpath" "$force" "$inspect_only" "$skills_dir"
            ;;
    esac
}

main "$@"
