#!/usr/bin/env bash
exec "$(dirname "$0")/../update-github-release.sh" ovnfs stencil-hq/ovnfs hash=src vendorHash=goModules
