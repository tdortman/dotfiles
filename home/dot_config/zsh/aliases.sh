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
alias cursor-agent='cursor-agent plan'

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
    local man_path=$(command -v man)
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

create_man_wrapper

create_mold_wrapper() {
    local tool=$1
    local tool_path=$(command -v "$tool")
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
