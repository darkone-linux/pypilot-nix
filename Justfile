# pypilot-nix — Justfile
# Recipes extracted from the Darkone framework common.just.

# Per-line bash with strict flags for non-shebang recipes.
set shell := ["bash", "-euo", "pipefail", "-c"]

alias c := clean

_default:
    @just --list

#==============================================================================
# Development
#==============================================================================

# clean: fix + check + format
[group('dev')]
clean: fix check format

# Fix with statix
[group('dev')]
fix:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "[ {{ CYAN }}NPY{{ NORMAL }} ] STATIX • Full fixing..."
    statix fix .

# treefmt orchestrates formatters in parallel (via treefmt.toml)
[group('dev')]
format:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "[ {{ CYAN }}NPY{{ NORMAL }} ] TREEFMT • Full formatting..."
    treefmt --no-cache --quiet

#==============================================================================
# Check
#==============================================================================

# Recursive deadnix on nix files
[group('check')]
check:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "[ {{ CYAN }}NPY{{ NORMAL }} ] DEADNIX • Full checking..."
    find . -name "*.nix" -exec deadnix -eq {} \;
