# navpi — Justfile (downstream of pypilot-nix).
#
# Same recipes as the distro, made portable by `override`: when a local clone of
# pypilot-nix sits at ./navpi-nix, every nix command imports it instead of the
# online input (like /etc/nixos pointing at a local checkout). Absent it, the
# committed flake.lock pins the online distro.

set shell := ["bash", "-euo", "pipefail", "-c"]

# Prefer the local distro checkout when present, else the locked online input.
override := if path_exists("navpi-nix") == "true" { "--override-input pypilot-nix path:./navpi-nix" } else { "" }

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
    echo "[ {{ CYAN }}NAV{{ NORMAL }} ] STATIX • Full fixing..."

    # Skip the local distro clone (./navpi-nix) — it is the distro's tree, linted
    # in its own repo, not here.
    statix fix . -i 'navpi-nix/**'

# Recursive deadnix on nix files
[group('dev')]
check:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "[ {{ CYAN }}NAV{{ NORMAL }} ] DEADNIX • Full checking..."
    find . -path ./navpi-nix -prune -o -name "*.nix" -exec deadnix -eq {} \;

# treefmt orchestrates formatters in parallel
[group('dev')]
format:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "[ {{ CYAN }}NAV{{ NORMAL }} ] TREEFMT • Full formatting..."
    treefmt --no-cache --quiet

# Inspections (flake check)
[group('dev')]
inspect:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "[ {{ CYAN }}NAV{{ NORMAL }} ] FLAKE • Checking configurations..."
    nix flake check -L --no-build {{ override }}

#==============================================================================
# Build
#==============================================================================

# Build the SD image for a host (navpi)
[group('build')]
sd-image host:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "[ {{ CYAN }}NAV{{ NORMAL }} ] SD-IMAGE • Building {{ host }}..."
    nix build ".#packages.aarch64-linux.{{ host }}-sdImage" {{ override }} -o "result-{{ host }}"
    echo "[ {{ CYAN }}NAV{{ NORMAL }} ] SD-IMAGE • $(ls result-{{ host }}/sd-image/*.img.zst)"

#==============================================================================
# Deploy
#==============================================================================

# Init a host's secrets: one uncommitted sops age key, and (if it uses wifi) its
# encrypted PSK. Idempotent — re-run any time; existing key/secret are kept.
[group('deploy')]
init host:
    #!/usr/bin/env bash
    set -euo pipefail

    key_dir="secrets/keys"
    key_file="$key_dir/{{ host }}.txt"
    secret="secrets/{{ host }}.yaml"
    rule="secrets/{{ host }}\\.yaml\$"

    # Refuse an unknown host before touching any file.
    if ! nix eval --accept-flake-config {{ override }} ".#nixosConfigurations.{{ host }}" --apply 'x: true' >/dev/null 2>&1; then
      echo "[ {{ CYAN }}NAV{{ NORMAL }} ] INIT • unknown host '{{ host }}'." >&2
      exit 1
    fi

    mkdir -p "$key_dir"

    # 1. Per-host private age key — created once, never committed (.gitignore).
    if [ -f "$key_file" ]; then
      echo "[ {{ CYAN }}NAV{{ NORMAL }} ] INIT • key kept: $key_file"
    else
      age-keygen -o "$key_file" 2>/dev/null
      chmod 600 "$key_file"
      echo "[ {{ CYAN }}NAV{{ NORMAL }} ] INIT • key created: $key_file"
    fi
    pub="$(age-keygen -y "$key_file")"

    # 2. Register/refresh the PUBLIC key in .sops.yaml for secrets/<host>.yaml.
    if yq -e ".creation_rules[] | select(.path_regex == \"$rule\")" .sops.yaml >/dev/null 2>&1; then
      yq -i "(.creation_rules[] | select(.path_regex == \"$rule\")).age = \"$pub\"" .sops.yaml
    else
      yq -i ".creation_rules += [{\"path_regex\": \"$rule\", \"age\": \"$pub\"}]" .sops.yaml
    fi
    echo "[ {{ CYAN }}NAV{{ NORMAL }} ] INIT • recipient set in .sops.yaml"

    # 3. Wifi PSK — only for wifi hosts, only if not captured yet.
    wifi="$(nix eval --accept-flake-config {{ override }} ".#nixosConfigurations.{{ host }}.config.networking.wireless.enable" 2>/dev/null || echo false)"
    if [ "$wifi" != "true" ]; then
      echo "[ {{ CYAN }}NAV{{ NORMAL }} ] INIT • no wifi on {{ host }} — done."
      exit 0
    fi
    if [ -f "$secret" ]; then
      echo "[ {{ CYAN }}NAV{{ NORMAL }} ] INIT • wifi secret kept: $secret"
      exit 0
    fi

    read -rsp "Wifi password for {{ host }}: " psk; echo
    tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
    printf 'wifi_psk: %s\n' "$psk" > "$tmp"
    sops --encrypt --filename-override "$secret" "$tmp" > "$secret"
    echo "[ {{ CYAN }}NAV{{ NORMAL }} ] INIT • encrypted $secret"
    echo "[ {{ CYAN }}NAV{{ NORMAL }} ] INIT • before first boot, copy $key_file → SD /boot/firmware/secrets/age.txt"

# Deploy a host over SSH (action: switch, boot, test, dry-activate...)
[group('deploy')]
apply host action="switch":
    #!/usr/bin/env bash
    set -euo pipefail
    echo "[ {{ CYAN }}NAV{{ NORMAL }} ] APPLY • {{ action }} {{ host }}..."
    nixos-rebuild {{ action }} --flake ".#{{ host }}" {{ override }} \
      --target-host "skipper@{{ host }}" --sudo \
      --accept-flake-config

# Update flake inputs, commit flake.lock if it changed
[group('deploy')]
update:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "[ {{ CYAN }}NAV{{ NORMAL }} ] UPDATE • Updating flake inputs..."
    nix flake update
    if git diff --quiet -- flake.lock; then
      echo "[ {{ CYAN }}NAV{{ NORMAL }} ] UPDATE • No changes."
    else
      git add flake.lock
      git commit -m "Flake input updates - $(date +%Y-%m-%d)"
    fi

# Free space on a host: collect garbage, then regenerate boot entries
[group('deploy')]
gc host:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "[ {{ CYAN }}NAV{{ NORMAL }} ] GC • Cleaning {{ host }}..."
    ssh "skipper@{{ host }}" \
      "sudo nix-collect-garbage -d && \
       sudo /nix/var/nix/profiles/system/bin/switch-to-configuration boot"
