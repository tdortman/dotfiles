#!/usr/bin/env zsh

auto_venv() {
    local dir="$PWD"
    local target=""

    # Find nearest .venv in this directory or a parent.
    while [[ "$dir" != "/" ]]; do
        if [[ -d "$dir/.venv" ]]; then
            target="$dir/.venv"
            break
        fi
        dir="${dir:h}"
    done

    # Already using the correct environment.
    if [[ -n "$target" && "$VIRTUAL_ENV" == "$target" ]]; then
        return
    fi

    # Leave the current environment.
    if [[ -n "$VIRTUAL_ENV" ]]; then
        echo "🐍 Deactivating venv from $VIRTUAL_ENV"

        if (($+functions[deactivate])); then
            deactivate
        else
            # We inherited an activated venv from a parent shell, so there is
            # no shell-local `deactivate` function. Remove it manually.
            path=("${(@)path:#$VIRTUAL_ENV/bin}")
            unset VIRTUAL_ENV VIRTUAL_ENV_PROMPT
        fi
    fi

    # Enter the desired environment.
    if [[ -n "$target" ]]; then
        echo "🐍 Activating venv from $target"
        source "$target/bin/activate"
    fi
}

autoload -Uz add-zsh-hook
add-zsh-hook chpwd auto_venv
auto_venv
