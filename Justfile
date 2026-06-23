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

# Recursive deadnix on nix files
[group('dev')]
check:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "[ {{ CYAN }}NPY{{ NORMAL }} ] DEADNIX • Full checking..."
    find . -name "*.nix" -exec deadnix -eq {} \;

# treefmt orchestrates formatters in parallel (via treefmt.toml)
[group('dev')]
format:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "[ {{ CYAN }}NPY{{ NORMAL }} ] TREEFMT • Full formatting..."
    treefmt --no-cache --quiet

#==============================================================================
# Build
#==============================================================================

# Build the SD image for a host (navpi, lab-rpi4, lab-rpi5)
[group('build')]
sd-image host:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "[ {{ CYAN }}NPY{{ NORMAL }} ] SD-IMAGE • Building {{ host }}..."
    nix build ".#packages.aarch64-linux.{{ host }}-sdImage" -o "result-{{ host }}"
    echo "[ {{ CYAN }}NPY{{ NORMAL }} ] SD-IMAGE • $(ls result-{{ host }}/sd-image/*.img.zst)"

#==============================================================================
# Deploy
#==============================================================================

# Deploy a host over SSH (action: switch, boot, test, dry-activate...)
[group('deploy')]
apply host action="switch":
    #!/usr/bin/env bash
    set -euo pipefail
    echo "[ {{ CYAN }}NPY{{ NORMAL }} ] APPLY • {{ action }} {{ host }}..."
    nixos-rebuild {{ action }} --flake ".#{{ host }}" \
      --target-host "skipper@{{ host }}" --sudo

# Update flake inputs, commit flake.lock if it changed
[group('deploy')]
update:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "[ {{ CYAN }}NPY{{ NORMAL }} ] UPDATE • Updating flake inputs..."
    nix flake update
    if git diff --quiet -- flake.lock; then
      echo "[ {{ CYAN }}NPY{{ NORMAL }} ] UPDATE • No changes."
    else
      git add flake.lock
      git commit -m "Flake input updates - $(date +%Y-%m-%d)"
    fi

# Free space on a host: collect garbage, then regenerate boot entries
[group('deploy')]
gc host:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "[ {{ CYAN }}NPY{{ NORMAL }} ] GC • Cleaning {{ host }}..."
    ssh "skipper@{{ host }}" \
      "sudo nix-collect-garbage -d && \
       sudo /nix/var/nix/profiles/system/bin/switch-to-configuration boot"
