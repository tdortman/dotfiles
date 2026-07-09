#!/usr/bin/env bash

alias ls=eza
alias l='eza -laah --colour=always --icons=always --group-directories-first -s name --time-style "+%d %b %y %X"'
alias t='eza --tree -lah --colour=always --icons=always --group-directories-first -s name --time-style "+%d %b %y %X"'
alias s='source $HOME/.zshrc'
alias c=clear
alias gst='git status'
alias rgi='rg --ignore-case'
alias cat='bat --theme "OneDark" --paging=never'
alias gcam='git add . && git commit -m'
alias gam='git add --all && git commit --amend --no-edit'
alias gc='git commit -m'
alias gco='git checkout'
alias gp='git push'
alias gpl='git pull'
alias gsta='git stash'
alias gd='git diff'
alias gl='git log'
alias rgi='rg --ignore-case'
alias wiki='wiki-tui'
alias drs='danbooru-rs'
alias dgo='danbooru-go'
alias cnew=cargo-new
alias cnewtokio=cargo-new-tokio
alias cb='cargo build'
alias cbr='cargo build --release'
alias cr='cargo run'
alias crr='cargo run --release'
alias cip='cargo install --path .'
alias ci='cargo install'
alias where='which'
alias e=explorer.exe
alias code='code -r'
alias zeditor='zeditor -r'
alias gpt="copilot -s --model \"gpt-5-mini\" -p"
alias suggest="copilot -s --model \"gpt-5-mini\" -p"
alias cm=chezmoi
alias lg=lazygit
alias cursor-agent='cursor-agent --plan'

# Encrypt a file using SSH key from 1Password via ssh-agent
# Usage: age-encrypt <input-file> [output-file]
age-encrypt() {
    local input_file="$1"
    local output_file="${2:-${input_file}.age}"

    # Check if input file exists
    if [[ ! -f "$input_file" ]]; then
        echo "Error: Input file '$input_file' does not exist" >&2
        return 1
    fi

    # Check if ssh-agent has keys
    if ! ssh-add -L | grep -q "Git"; then
        echo "Error: No Git SSH key found in ssh-agent" >&2
        echo "Make sure 1Password SSH agent is running and your key is loaded" >&2
        return 1
    fi

    # Encrypt the file
    if ssh-add -L | grep "Git" | awk '{ print $1, $2 }' | age -R - -o "$output_file" "$input_file"; then
        echo "✅ Encrypted '$input_file' to '$output_file'"
    else
        echo "❌ Failed to encrypt '$input_file'" >&2
        return 1
    fi
}

# Decrypt a file using SSH key from 1Password
# Usage: age-decrypt <encrypted-file> [output-file]
age-decrypt() {
    local encrypted_file="$1"
    local output_file="$2"

    # Check if encrypted file exists
    if [[ ! -f "$encrypted_file" ]]; then
        echo "Error: Encrypted file '$encrypted_file' does not exist" >&2
        return 1
    fi

    # If no output file specified, remove .age extension or use .decrypted
    if [[ -z "$output_file" ]]; then
        if [[ "$encrypted_file" == *.age ]]; then
            output_file="${encrypted_file%.age}"
        else
            output_file="${encrypted_file}.decrypted"
        fi
    fi

    # Decrypt the file
    if age -d -i <(op read "op://Personal/Git/private key") "$encrypted_file" >"$output_file"; then
        echo "✅ Decrypted '$encrypted_file' to '$output_file'"
    else
        echo "❌ Failed to decrypt '$encrypted_file'" >&2
        return 1
    fi
}

# Helper function to encrypt/decrypt in place
# Usage: age-toggle <file>
age-toggle() {
    local file="$1"

    if [[ -z "$file" ]]; then
        echo "Usage: age-toggle <file>" >&2
        return 1
    fi

    if [[ "$file" == *.age ]]; then
        # File is encrypted, decrypt it
        local decrypted_file="${file%.age}"
        age-decrypt "$file" "$decrypted_file"
    else
        # File is not encrypted, encrypt it
        age-encrypt "$file"
    fi
}

create_man_wrapper() {
    local man_path
    man_path=$(command -v man)
    eval "
    man() {
        $man_path \"\$@\" | bat --language=Manpage --style=plain
    }
    "
}

skills() {
    bunx skills "$@"
}

skills-add() {
    bunx skills add "$@" -g -y
    chezmoi add ~/.agents/skills
}

_omp_commit_state_file="$HOME/.local/state/omp-backups/last"

# Regenerable build/dependency artifacts excluded from backups (at any depth).
# Add entries here as needed.
_omp_commit_excludes=(
    node_modules .pnpm-store target .venv venv .tox .nox __pycache__
    .pytest_cache .mypy_cache .ruff_cache .next .nuxt .svelte-kit .turbo
    .vite .parcel-cache .cache dist build coverage .pixi .zig-cache .zig-out
    zig-cache zig-out result
)

_omp_commit_save_state() {
    mkdir -p "${_omp_commit_state_file:h}"
    printf 'snap=%q\nbackup=%q\nroot=%q\n' "$1" "$2" "$3" >"$_omp_commit_state_file"
}

_omp_commit_load_state() {
    [[ -f "$_omp_commit_state_file" ]] || return 1
    snap=""
    backup=""
    root=""
    # shellcheck disable=SC1090
    source "$_omp_commit_state_file" || return 1
    [[ -n $snap && -n $backup && -n $root ]] || return 1
}

_omp_commit_clear_state() {
    rm -f "$_omp_commit_state_file"
}

_omp_commit_show_recovery() {
    local -a _xflags=(--exclude=.git "${_omp_commit_excludes[@]/#/--exclude=}")
    local snap=$1 backup=$2 root=$3 recover cleanup xflags="${_xflags[*]}"
    recover="git reset --hard $(printf %q "$snap") && rsync -a --delete $xflags $(printf %q "$backup/") $(printf %q "$root/")"
    cleanup="rm -rf $(printf %q "$backup")"

    echo "kept agent's changes; backup at $backup"
    echo
    echo "restore:  omp-commit-restore"
    echo "cleanup:  omp-commit-cleanup"
    echo
    print -r -- "$recover"
    print -r -- "$cleanup"
}

omp-commit-restore() {
    _omp_commit_load_state || {
        echo "no omp-commit backup state" >&2
        return 1
    }
    git reset --hard "$snap" &&
        rsync -a --delete --exclude=.git "${_omp_commit_excludes[@]/#/--exclude=}" "$backup/" "$root/" &&
        rm -rf "$backup" &&
        git tag -d "$snap" >/dev/null 2>&1 &&
        _omp_commit_clear_state &&
        echo "restored"
}

omp-commit-cleanup() {
    _omp_commit_load_state || {
        echo "no omp-commit backup state" >&2
        return 1
    }
    rm -rf "$backup" &&
        git tag -d "$snap" >/dev/null 2>&1 &&
        _omp_commit_clear_state &&
        echo "cleaned up"
}

omp-commit() {
    local snap root backup
    snap="pre-omp-$(date +%s%N)-$$"
    command -v rsync >/dev/null || {
        echo "rsync required for omp-commit" >&2
        return 1
    }
    root=$(git rev-parse --show-toplevel 2>/dev/null) || {
        echo "not a git repo" >&2
        return 1
    }
    backup="$HOME/.local/state/omp-backups/$snap"
    mkdir -p "$backup" || {
        echo "mkdir failed" >&2
        return 1
    }
    git tag "$snap" HEAD || {
        rm -rf "$backup"
        echo "tag failed" >&2
        return 1
    }
    rsync -a --exclude=.git "${_omp_commit_excludes[@]/#/--exclude=}" "$root/" "$backup/" || {
        rm -rf "$backup"
        git tag -d "$snap" >/dev/null 2>&1
        echo "copy failed" >&2
        return 1
    }
    _omp_commit_save_state "$snap" "$backup" "$root"

    omp "$@" "$(
        cat <<EOF
Generate granular, atomic commits using the \`git-surgeon\` skill at
\`$HOME/.agents/skills/git-surgeon/SKILL.md\`.

Do not over-split the work. Focus on the most important changes.
Each commit should represent one coherent reason for change, not just
one edited file or one mechanical diff chunk.

Each commit must leave the repository in a valid state. After any
commit, I should be able to check it out and still have a functioning
repo. Do not create commits where the build only works again after a
later commit. If a safe split is not possible, keep the change together.

Stage changes deliberately. Do not include unrelated edits in a commit.
Use the smallest commit that still preserves a working state and a clear
reason for the change.

For each commit message:

- Use present tense.
- Use a semantic commit prefix.
- Keep the title to 50 characters or less.
- Keep an empty line between the title and body.
- Explain why the change was made, not just what changed.
- Focus the body on the most important context.
- Wrap code symbols in backticks.
- Body lines must not exceed 70 characters.
- Do not start any line with \`#\`.
- Do not use emojis.
- Do not use em dashes.
- Do not use semicolons.

Each \`git commit\` command must contain exactly one \`-m\` flag. Use a
single multi-line message argument instead of multiple \`-m\` flags, so
Git does not insert extra blank lines between body lines.

If the reason for a change is unclear, check the project's session
history under \`$HOME/.omp/agent/sessions\` before writing the commit
message.
EOF
    )"
    echo
    echo "agent commits since $snap:"
    git log --oneline "$snap..HEAD" 2>/dev/null | sed 's/^/  /'
    echo "worktree status:"
    git status -s 2>/dev/null | sed 's/^/  /'
    read -r -q "REPLY?Restore from backup ($backup)? [y/N] "
    echo
    if [[ $REPLY == y ]]; then
        if git reset --hard "$snap" &&
            rsync -a --delete --exclude=.git "${_omp_commit_excludes[@]/#/--exclude=}" "$backup/" "$root/" &&
            rm -rf "$backup" &&
            git tag -d "$snap" >/dev/null 2>&1; then
            _omp_commit_clear_state
            echo "restored"
        else
            echo "restore failed (state may be partial); backup still at $backup"
            echo
            _omp_commit_show_recovery "$snap" "$backup" "$root"
            return 1
        fi
    else
        _omp_commit_show_recovery "$snap" "$backup" "$root"
    fi
}

create_man_wrapper

create_mold_wrapper() {
    local tool=$1
    local tool_path
    tool_path=$(command -v "$tool")
    case "$tool" in
    make)
        eval "
            __mold_wrapped_$tool() {
                mold -run '$tool_path' \$MAKEFLAGS \"\$@\"
            }
            "
        ;;
    ninja)
        eval "
            __mold_wrapped_$tool() {
                mold -run '$tool_path' \$NINJAFLAGS \"\$@\"
            }
            "
        ;;
    *)
        eval "
            __mold_wrapped_$tool() {
                mold -run '$tool_path' \"\$@\"
            }
            "
        ;;
    esac
}

# Create wrappers for build tools
# build_tools=(make cmake ninja)
# for tool in "${build_tools[@]}"; do
#     create_mold_wrapper "$tool"
#     alias "$tool"="__mold_wrapped_$tool"
# done

alias -g -- -h='-h 2>&1 | bat --language=help --style=plain --paging=never --theme="OneDark"'
alias -g -- --help='--help 2>&1 | bat --language=help --style=plain --paging=never --theme="OneDark"'
