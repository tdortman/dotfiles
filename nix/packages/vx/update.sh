#!/usr/bin/env bash
exec "$(dirname "$0")/../update-github-release.sh" vx vx-lang/Vx hash=src cargoHash=cargoDeps
