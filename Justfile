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
# Test
#==============================================================================

# Pure unit tests over lib/ (nix-unit)
[group('test')]
test:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "[ {{ CYAN }}NPY{{ NORMAL }} ] NIX-UNIT • Running unit tests..."

    # Eval the suites directly, not `--flake .#libTests`: nix-unit's strict
    # locker tries to re-lock the heavy nixos-raspberrypi input and fails in
    # pure mode, where `nix eval`/getFlake resolve the pinned lock fine. The
    # suites only need nixpkgs.lib. CI gate stays `nix flake check` (.#checks.unit).
    nix-unit --gc-roots-dir /tmp --impure \
        --expr 'import ./tests/unit { lib = (builtins.getFlake (toString ./.)).inputs.nixpkgs.lib; }'

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
      echo "[ {{ CYAN }}NPY{{ NORMAL }} ] INIT • unknown host '{{ host }}'." >&2
      exit 1
    fi

    mkdir -p "$key_dir"

    # 1. Per-host private age key — created once, never committed (.gitignore).
    if [ -f "$key_file" ]; then
      echo "[ {{ CYAN }}NPY{{ NORMAL }} ] INIT • key kept: $key_file"
    else
      age-keygen -o "$key_file" 2>/dev/null
      chmod 600 "$key_file"
      echo "[ {{ CYAN }}NPY{{ NORMAL }} ] INIT • key created: $key_file"
    fi
    pub="$(age-keygen -y "$key_file")"

    # 2. Register/refresh the PUBLIC key in .sops.yaml for secrets/<host>.yaml.
    if yq -e ".creation_rules[] | select(.path_regex == \"$rule\")" .sops.yaml >/dev/null 2>&1; then
      yq -i "(.creation_rules[] | select(.path_regex == \"$rule\")).age = \"$pub\"" .sops.yaml
    else
      yq -i ".creation_rules += [{\"path_regex\": \"$rule\", \"age\": \"$pub\"}]" .sops.yaml
    fi
    echo "[ {{ CYAN }}NPY{{ NORMAL }} ] INIT • recipient set in .sops.yaml"

    # 3. Wifi PSK — only for wifi hosts, only if not captured yet.
    wifi="$(nix eval --accept-flake-config ".#nixosConfigurations.{{ host }}.config.networking.wireless.enable" 2>/dev/null || echo false)"
    if [ "$wifi" != "true" ]; then
      echo "[ {{ CYAN }}NPY{{ NORMAL }} ] INIT • no wifi on {{ host }} — done."
      exit 0
    fi
    if [ -f "$secret" ]; then
      echo "[ {{ CYAN }}NPY{{ NORMAL }} ] INIT • wifi secret kept: $secret"
      exit 0
    fi

    read -rsp "Wifi password for {{ host }}: " psk; echo
    tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
    printf 'wifi_psk: %s\n' "$psk" > "$tmp"
    sops --encrypt --filename-override "$secret" "$tmp" > "$secret"
    echo "[ {{ CYAN }}NPY{{ NORMAL }} ] INIT • encrypted $secret"
    echo "[ {{ CYAN }}NPY{{ NORMAL }} ] INIT • before first boot, copy $key_file → SD /boot/firmware/secrets/age.txt"

# Deploy a host over SSH (action: switch, boot, test, dry-activate...)
[group('deploy')]
apply host action="switch":
    #!/usr/bin/env bash
    set -euo pipefail
    echo "[ {{ CYAN }}NPY{{ NORMAL }} ] APPLY • {{ action }} {{ host }}..."
    # --accept-flake-config: honor the flake's nixConfig (Pi kernel cache)
    # non-interactively, else nix declines it and recompiles the kernel.
    nixos-rebuild {{ action }} --flake ".#{{ host }}" \
      --target-host "skipper@{{ host }}" --sudo \
      --accept-flake-config

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

#==============================================================================
# Release
#==============================================================================

# Promote the Unreleased changelog to <version>, commit and tag v<version>
[group('release')]
bump version:
    #!/usr/bin/env bash
    set -euo pipefail
    v="{{ version }}"
    tag="v$v"
    repo="https://github.com/darkone-linux/pypilot-nix"
    say() { echo "[ {{ CYAN }}NPY{{ NORMAL }} ] BUMP • $*"; }

    # Guard: strict semver, clean tree, fresh tag.
    if [[ ! "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      say "invalid version '$v' (expected X.Y.Z)." >&2
      exit 1
    fi
    if ! git diff --quiet || ! git diff --cached --quiet; then
      say "working tree not clean, commit or stash first." >&2
      exit 1
    fi
    if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
      say "tag $tag already exists." >&2
      exit 1
    fi

    prev="$(git describe --tags --abbrev=0 2>/dev/null || true)"
    date="$(date +%Y-%m-%d)"

    # Open a new version section right under the Unreleased heading.
    awk -v ver="$v" -v d="$date" '
      /^## \[Unreleased\]/ && !seen {
        print; print ""; print "## [" ver "] - " d; seen = 1; next
      }
      { print }
    ' CHANGELOG.md > CHANGELOG.md.tmp

    # First release links to its tag; later ones diff against the previous tag.
    if [[ -n "$prev" ]]; then
      newlink="[$v]: $repo/compare/$prev...$tag"
    else
      newlink="[$v]: $repo/releases/tag/$tag"
    fi

    # Re-point Unreleased at the new tag and insert the version link.
    awk -v tag="$tag" -v repo="$repo" -v newlink="$newlink" '
      /^\[Unreleased\]:/ {
        print "[Unreleased]: " repo "/compare/" tag "...HEAD"; print newlink; next
      }
      { print }
    ' CHANGELOG.md.tmp > CHANGELOG.md
    rm -f CHANGELOG.md.tmp

    git add CHANGELOG.md
    git commit -m "chore(release): $tag"
    git tag -a "$tag" -m "Release $tag"
    say "tagged $tag — publish with: git push origin main $tag"
