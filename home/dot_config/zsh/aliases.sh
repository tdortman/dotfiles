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
# alias zeditor='zeditor -r'
alias gpt="copilot -s --model \"gpt-5-mini\" -p"
alias suggest="copilot -s --model \"gpt-5-mini\" -p"
alias cm=chezmoi
alias lg=lazygit
alias cursor-agent='cursor-agent --plan'
alias hd='hunk diff'
alias hs='hunk show'

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
_omp_commit_backup_dir="$HOME/.local/state/omp-backups"

_omp_commit_save_state() {
    mkdir -p "${_omp_commit_state_file:h}"
    printf 'backup=%q\nroot=%q\n' "$1" "$2" >"$_omp_commit_state_file"
}

_omp_commit_load_state() {
    [[ -f "$_omp_commit_state_file" ]] || return 1
    backup=""
    root=""
    # shellcheck disable=SC1090
    source "$_omp_commit_state_file" || return 1
    [[ -n $backup && -n $root ]] || return 1
}

_omp_commit_clear_state() {
    rm -f "$_omp_commit_state_file"
}

_omp_commit_restore_snapshot() {
    local cwd=$PWD
    local parent=${root:h}
    local old
    local rc
    local rollback_failed=0
    local had_root=0

    if [[ -z "$root" || -z "$backup" || "$root" == / || "$root" == "$backup" ]]; then
        print -u2 -r -- "invalid snapshot paths"
        return 1
    fi

    old="${root}.omp-old-$$-$RANDOM"
    while [[ -e "$old" ]]; do
        old="${root}.omp-old-$$-$RANDOM"
    done

    cd "$parent" || return 1

    if [[ ! -d "$backup" ]]; then
        print -u2 -r -- "backup snapshot does not exist: $backup"
        cd "$cwd" 2>/dev/null || cd "$parent" || return 1
        return 1
    fi

    # Move the current project aside without deleting it yet.
    if [[ -e "$root" ]]; then
        mv -- "$root" "$old"
        rc=$?

        if ((rc != 0)); then
            cd "$cwd" 2>/dev/null || cd "$parent" || return 1
            return "$rc"
        fi

        had_root=1
    fi

    # Promote the backup snapshot to the original project path.
    mv -- "$backup" "$root"
    rc=$?

    if ((rc != 0)); then
        if ((had_root)); then
            mv -- "$old" "$root" >/dev/null 2>&1 ||
                print -u2 -r -- \
                    "failed to move the original subvolume back to: $root"
        fi

        cd "$cwd" 2>/dev/null || cd "$parent" || return 1
        return "$rc"
    fi

    # Keep the old project around until the saved state is cleared.
    _omp_commit_clear_state
    rc=$?

    if ((rc != 0)); then
        # Attempt to undo the filesystem changes.
        mv -- "$root" "$backup" >/dev/null 2>&1 ||
            rollback_failed=1

        if ((had_root)); then
            mv -- "$old" "$root" >/dev/null 2>&1 ||
                rollback_failed=1
        fi

        if ((rollback_failed)); then
            print -u2 -r -- \
                "failed to clear state and could not completely roll back the restore"
        fi

        cd "$cwd" 2>/dev/null || cd "$parent" || return 1
        return "$rc"
    fi

    # Restoration succeeded. Failure to remove the previous tree is only
    # a cleanup failure, since the backup is already active at $root.
    if ((had_root)); then
        if ! sudo btrfs subvolume delete "$old" >/dev/null; then
            print -u2 -r -- \
                "restored, but failed to delete the previous subvolume: $old"
        fi
    fi

    # The old working directory may not exist in the restored snapshot.
    cd "$cwd" 2>/dev/null ||
        cd "$root" 2>/dev/null ||
        cd "$parent" ||
        return 1

    print -r -- "restored"
}

_omp_commit_show_recovery() {
    local backup=$1 root=$2

    echo "kept agent's changes; backup at $backup"
    echo
    echo "restore:  omp-commit-restore"
    echo "cleanup:  omp-commit-cleanup"
}

omp-commit-restore() {
    _omp_commit_load_state || {
        echo "no omp-commit backup state" >&2
        return 1
    }
    _omp_commit_restore_snapshot
}

omp-commit-cleanup() {
    _omp_commit_load_state || {
        echo "no omp-commit backup state" >&2
        return 1
    }
    sudo btrfs subvolume delete "$backup" >/dev/null &&
        _omp_commit_clear_state &&
        echo "cleaned up"
}

_omp_commit() {
    local omp_command=$1
    shift
    local root backup filesystem_type filesystem_uuid
    local backup_filesystem_uuid commit timestamp path_name

    command -v findmnt >/dev/null || {
        echo "findmnt required for omp-commit" >&2
        return 1
    }

    filesystem_type=$(findmnt -T . -no FSTYPE 2>/dev/null) || {
        echo "could not determine filesystem type" >&2
        return 1
    }

    [[ "$filesystem_type" == btrfs ]] || {
        echo "omp-commit backups require a Btrfs filesystem" >&2
        return 1
    }

    command -v btrfs >/dev/null || {
        echo "btrfs required for omp-commit" >&2
        return 1
    }

    root=$(git rev-parse --show-toplevel 2>/dev/null) || {
        echo "not a git repo" >&2
        return 1
    }

    # All subvolumes have inode 256 on Btrfs
    [[ $(stat -Lc '%i' -- "$root") == 256 ]] || {
        echo "git root must be a Btrfs subvolume" >&2
        return 1
    }

    mkdir -p "$_omp_commit_backup_dir" || {
        echo "mkdir failed" >&2
        return 1
    }

    filesystem_uuid=$(findmnt -T "$root" -no UUID 2>/dev/null)
    backup_filesystem_uuid=$(findmnt -T "$_omp_commit_backup_dir" -no UUID 2>/dev/null)

    [[ -n "$filesystem_uuid" && "$filesystem_uuid" == "$backup_filesystem_uuid" ]] || {
        echo "backup directory must be on the same Btrfs filesystem" >&2
        return 1
    }

    commit=$(git rev-parse --short HEAD)
    timestamp=$(date +%s%N)
    path_name="${root//\//-}"
    backup="$_omp_commit_backup_dir/${path_name}-${commit}-${timestamp}"
    btrfs subvolume snapshot "$root" "$backup" || {
        echo "snapshot failed" >&2
        return 1
    }
    _omp_commit_save_state "$backup" "$root"

    "$omp_command" "$@" "$(
        cat <<EOF
Generate granular, atomic commits using the \`git-surgeon\` skill at
\`$HOME/.agents/skills/git-surgeon/SKILL.md\`.

Prefer \`git-surgeon\` commands for inspection, staging, splitting,
validation, and commit preparation. Use raw Git commands only when
\`git-surgeon\` does not provide the needed operation, or when the prompt
explicitly constrains the exact Git command format.

Do not over-split the work. Focus on the most important changes.
Each commit should represent one coherent reason for change, not just
one edited file or one mechanical diff chunk.

Each commit must leave the repository in a valid state. After any
commit, I should be able to check it out and still have a functioning
repo. Do not create commits where the build only works again after a
later commit. If a safe split is not possible, keep the change together.

After creating the commit series, verify that each commit leaves the
repository in a functioning state.

Prefer using temporary Git worktrees to test commits independently
instead of repeatedly moving the main working tree. For each commit, check
out that commit in a clean worktree and run the relevant build, tests, or
checks for the project. Always ensure temporary worktrees are removed when
testing completes, even if a test fails.

If testing every commit is too expensive, test the commits most likely to
break the build, such as commits that change APIs, move files, update
dependencies, alter build configuration, or split a larger change across
multiple commits.

Stage changes deliberately. Do not include unrelated edits in a commit.
Use the smallest commit that still preserves a working state and a clear
reason for the change.

Before creating commits, inspect the full working tree using the
\`git-surgeon\` workflow and its most appropriate granular inspection
commands. Do not fall back to broad manual Git commands when a
\`git-surgeon\` command exists for the task.

Use \`git-surgeon\` to understand changed files, hunks, lines, untracked files,
dependencies between changes, and safe staging boundaries. Build a commit
plan that groups changes by intent. For each planned commit, identify the
specific project problem, constraint, bug, design pressure, or user-facing
need that explains why the repository needs the change.
Keep agent workflow reasoning out of the commit message.

Commit bodies must give a concrete rationale. Avoid vague explanations
such as "improves maintainability", "cleans up the code", "updates logic",
or "makes things better" unless they are immediately followed by the
specific reason this matters in the project.

A good commit body should usually answer:
- What project problem, limitation, or design pressure made this change
  necessary?
- Why is this implementation approach appropriate for the codebase?
- What behaviour, API, workflow, or future change does this enable?
- What compatibility or migration constraint matters to future maintainers?

If the change is mechanical, explain the non-mechanical reason it is
needed, such as preparing for an API split, reducing duplicated state,
making later validation possible, or keeping generated artefacts in sync.

### Commit Message Constraints

For each commit message, you must strictly adhere to these rules:
- Use British English spelling and wording, for example \`optimise\`,
  \`favour\`, \`colour\`, and \`behaviour\`.
- Use present tense.
- Use a semantic commit prefix.
- Title length: Maximum 50 characters.
- Body line length: Maximum 70 characters.
- Keep an empty line between the title and body.
- Explain why the change was made, not just what changed.
- For every commit body, explain the cause or pressure behind the change,
  not merely the resulting code difference.
- Focus the body on the most important context.
- Wrap code symbols in \`backticks\`.
- Do not start any line with \`#\`.
- Do not use emojis, em dashes, or semicolons.

Commit bodies must not explain the agent's process, commit-planning
decision, or validation workflow unless that information is directly useful
to a future maintainer of the repository.

Do not write phrases such as "this stays one commit", "this was split",
"the risk is prompt drift", "validation checks", or similar process notes
in commit messages. Keep that reasoning in the final summary instead.

The commit body should explain why the repository needs the change from the
project's perspective. It should not justify why the agent chose a
particular commit boundary.

Commit messages must describe the repository change from the project's
perspective. Do not describe the agent's workflow, commit planning, series
splitting, or validation process.

Never include process phrases such as:
- "validated earlier"
- "before the series was split"
- "this commit is kept as one boundary"
- "this split is kept in one commit"
- "the workspace would not compile otherwise"
- "tested in a temporary worktree"
- "validation checks"

Keep validation details in the final response after the commits are
created, not in the commit message body.

It is acceptable to mention compile-time constraints only when they are a
real architectural reason for the change, not as a justification for how
the agent split the series.

Bad body:
"Updates parser handling and refactors helpers."

Good body:
"The parser now accepts shared input paths from multiple call sites, so the
normalisation step needs to live behind a single helper. Keeping the helper
inside the parser avoids duplicating path handling before later callers are
added."

### Semantic Versioning

If a commit adds, removes, or changes functionality, find every place in
the codebase that sets the software version and update it according to
these rules.

Never automatically promote a pre-\`1.0.0\` codebase to \`1.0.0\`. The
transition to \`1.0.0\` is a deliberate project decision and must only
happen when the user explicitly requests it.

Version components are not limited to single digits. Versions such as
\`0.10.0\`, \`0.27.4\`, and \`0.100.0\` are valid. Do not promote a project to
\`1.0.0\` merely because its current minor version is \`9\` or greater.

When the current version is below \`1.0.0\`:

- Increment the minor version for incompatible API changes, removed
  functionality, or other breaking changes.
- Increment the minor version for new backwards-compatible functionality.
- Increment the patch version for backwards-compatible bug fixes.
- Reset the patch version to zero whenever the minor version is
  incremented.

For example:

- \`0.3.4\` becomes \`0.4.0\` after a breaking API change.
- \`0.3.4\` becomes \`0.4.0\` after adding functionality.
- \`0.3.4\` becomes \`0.3.5\` after a backwards-compatible bug fix.
- \`0.9.7\` becomes \`0.10.0\` after adding functionality or making a
  breaking change.
- \`0.9.7\` must not become \`1.0.0\` without an explicit user instruction.

When the current version is at least \`1.0.0\`:

- Increment the major version for incompatible API changes or removed
  functionality.
- Increment the minor version for new backwards-compatible functionality.
- Increment the patch version for backwards-compatible bug fixes.
- Reset all less significant version components to zero when incrementing
  a more significant component.

When one commit contains multiple kinds of change, apply the highest
required increment. A breaking change takes precedence over added
functionality, and added functionality takes precedence over a bug fix.

### Shell Formatting Safety

Each \`git commit\` command must contain exactly one \`-m\` flag. Use a
single multi-line message argument instead of multiple \`-m\` flags.

Wrap the entire commit message argument in single quotes, not double
quotes. If you must use an apostrophe inside the message, escape it safely
for Bash using \`'\\''\`, for example \`don'\\''t\`. Otherwise, completely
avoid apostrophes.

If there is even a sliver of uncertainty about the reason behind a change,
check the project's session history under \`$HOME/.omp/agent/sessions\`
before writing the commit message.

Do not invent rationale. If the reason for a change is unclear after
inspecting the diff and session history, say so in the commit body using
careful wording, or keep the body limited to the observable reason.

After creating the commit series, audit the commit messages using
\`git-surgeon\`, Git history inspection, or an equivalent command. Verify
that every commit message satisfies the title length, body line length,
semantic prefix, British English, quoting, and formatting constraints. Fix
any commit message that fails the audit.
EOF
    )"
    echo
    echo "worktree status:"
    git status -s 2>/dev/null | sed 's/^/  /'
    read -r -q "REPLY?Restore from backup ($backup)? [y/N] "
    echo
    if [[ $REPLY == y ]]; then
        if _omp_commit_restore_snapshot; then
            :
        else
            echo "restore failed (state may be partial); backup still at $backup"
            echo
            _omp_commit_show_recovery "$backup" "$root"
            return 1
        fi
    else
        _omp_commit_show_recovery "$backup" "$root"
    fi
}

omp-commit() {
    _omp_commit omp "$@"
}

unsafe-omp-commit() {
    _omp_commit unsafe-omp "$@"
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
