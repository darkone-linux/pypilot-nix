# navpi — Justfile (downstream of pypilot-nix).
#
# Single source switch, like /etc/nixos pointing at a local checkout: the distro
# is whatever `flake.lock` pins. `just update` decides it — local clone
# (./navpi-nix) if present, else the online distro — and every other recipe just
# reads the lock. Never local+online mixed, never a silent runtime override.

set shell := ["bash", "-euo", "pipefail", "-c"]

alias c := clean

_default:
    @just --list

# Print the distro source pinned in flake.lock: local | online | unpinned.
[private]
pin:
    #!/usr/bin/env bash
    set -euo pipefail
    [ -f flake.lock ] || { echo unpinned; exit 0; }
    t="$(nix eval --impure --raw --expr \
      'let l = builtins.fromJSON (builtins.readFile ./flake.lock); in (l.nodes.pypilot-nix.locked.type or "unpinned")' \
      2>/dev/null || echo unpinned)"
    case "$t" in path) echo local ;; github) echo online ;; *) echo "$t" ;; esac

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

    # Skip the local distro clone — it is linted in its own repo, not here.
    statix fix . -i 'navpi-nix/**'

# Recursive deadnix on nix files
[group('dev')]
check:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "[ {{ CYAN }}NAV{{ NORMAL }} ] DEADNIX • Full checking..."
    find . -path ./navpi-nix -prune -o -name "*.nix" -exec deadnix -eq {} \;

# treefmt orchestrates formatters in parallel (respects .gitignore → skips navpi-nix)
[group('dev')]
format:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "[ {{ CYAN }}NAV{{ NORMAL }} ] TREEFMT • Full formatting..."
    treefmt --no-cache --quiet

# Inspections (flake check) — reads the lock, no override
[group('dev')]
inspect:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "[ {{ CYAN }}NAV{{ NORMAL }} ] FLAKE • Checking ($(just pin) distro)..."
    nix flake check -L --no-build

#==============================================================================
# Build
#==============================================================================

# Build the SD image for a host (navpi) — reads the lock
[group('build')]
sd-image host:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "[ {{ CYAN }}NAV{{ NORMAL }} ] SD-IMAGE • Building {{ host }} ($(just pin) distro)..."
    nix build ".#packages.aarch64-linux.{{ host }}-sdImage" -o "result-{{ host }}"
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
    if ! nix eval --accept-flake-config ".#nixosConfigurations.{{ host }}" --apply 'x: true' >/dev/null 2>&1; then
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
    wifi="$(nix eval --accept-flake-config ".#nixosConfigurations.{{ host }}.config.networking.wireless.enable" 2>/dev/null || echo false)"
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

# Deploy a host over SSH (action: switch, boot, test, dry-activate...) — reads the lock
[group('deploy')]
apply host action="switch":
    #!/usr/bin/env bash
    set -euo pipefail
    echo "[ {{ CYAN }}NAV{{ NORMAL }} ] APPLY • {{ action }} {{ host }} ($(just pin) distro)..."
    nixos-rebuild {{ action }} --flake ".#{{ host }}" \
      --target-host "skipper@{{ host }}" --sudo \
      --accept-flake-config

# Free space on a host: collect garbage, then regenerate boot entries
[group('deploy')]
gc host:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "[ {{ CYAN }}NAV{{ NORMAL }} ] GC • Cleaning {{ host }}..."
    ssh "skipper@{{ host }}" \
      "sudo nix-collect-garbage -d && \
       sudo /nix/var/nix/profiles/system/bin/switch-to-configuration boot"

#==============================================================================
# Distro source & co-development (git on both repos at once)
#==============================================================================

# Re-pin the distro in flake.lock: LOCAL ./navpi-nix if present, else ONLINE.
[group('git')]
update:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -d navpi-nix ]; then
      echo "[ {{ CYAN }}NAV{{ NORMAL }} ] UPDATE • pinning LOCAL ./navpi-nix"
      nix flake lock --override-input pypilot-nix path:navpi-nix
    else
      echo "[ {{ CYAN }}NAV{{ NORMAL }} ] UPDATE • pinning ONLINE distro"
      nix flake update pypilot-nix
    fi

# git status of both repos, plus the current distro pin.
[group('git')]
status:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "[ {{ CYAN }}NAV{{ NORMAL }} ] SOURCE • distro pinned: $(just pin)"
    echo "[ {{ CYAN }}NAV{{ NORMAL }} ] STATUS • navpi:"
    git status -s
    if [ -d navpi-nix ]; then
      echo "[ {{ CYAN }}NAV{{ NORMAL }} ] STATUS • navpi-nix (distro clone):"
      git -C navpi-nix status -s
    fi

# Commit both repos with the same message: distro first, re-pin, then navpi.
[group('git')]
commit msg:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -d navpi-nix ] && [ -n "$(git -C navpi-nix status --porcelain)" ]; then
      echo "[ {{ CYAN }}NAV{{ NORMAL }} ] COMMIT • navpi-nix..."
      git -C navpi-nix add -A
      git -C navpi-nix commit -m "{{ msg }}"

      # New distro state → refresh the local pin so navpi's lock matches it.
      just update
    fi
    echo "[ {{ CYAN }}NAV{{ NORMAL }} ] COMMIT • navpi..."
    git add -A
    git commit -m "{{ msg }}"

# Amend the last commit of both repos (keeps messages), then refresh the pin.
[group('git')]
amend:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -d navpi-nix ] && [ -n "$(git -C navpi-nix status --porcelain)" ]; then
      echo "[ {{ CYAN }}NAV{{ NORMAL }} ] AMEND • navpi-nix..."
      git -C navpi-nix add -A
      git -C navpi-nix commit --amend --no-edit
      just update
    fi
    echo "[ {{ CYAN }}NAV{{ NORMAL }} ] AMEND • navpi..."
    git add -A
    git commit --amend --no-edit
