# Secrets (sops)

Encrypted secrets, committed in their encrypted form and decrypted on the device
at activation by [sops-nix](https://github.com/Mic92/sops-nix). Plaintext never
enters git nor the Nix store.

Layout (one key + one secret file per host):

- `secrets/<host>.yaml` — encrypted secret for that host (e.g. `wifi_psk`). **Committed.**
- `secrets/keys/<host>.txt` — that host's **private** age key. **Never committed** (gitignored).
- `.sops.yaml` — maps `secrets/<host>.yaml` to the host's age **public** key.

## Provision a host

```sh
nix develop          # brings just + sops + age + yq into PATH
just init <host>     # idempotent: mints the key, registers it, captures the PSK
```

`just init`:

1. creates `secrets/keys/<host>.txt` if missing (a per-host age key);
2. registers its public key in `.sops.yaml` for `secrets/<host>.yaml`;
3. if the host enables wifi, prompts once for the password and writes the
   encrypted `secrets/<host>.yaml`.

Re-running is safe — an existing key or secret is kept untouched. Then commit the
encrypted `secrets/<host>.yaml` and the updated `.sops.yaml`.

The SSID is **not** a secret; set it in `hosts/<host>/configuration.nix`.

## Put the key on the Pi (before first boot)

The Zero 2 W is headless: without its age key it cannot decrypt the PSK, cannot
join wifi, and is unreachable. After flashing the SD card, drop the **private**
key on the FAT boot partition where the host expects it:

```sh
# the boot partition mounts at /boot/firmware on the running Pi
mkdir -p /run/media/$USER/FIRMWARE/secrets
cp secrets/keys/<host>.txt /run/media/$USER/FIRMWARE/secrets/age.txt
```

(Path on the Pi: `/boot/firmware/secrets/age.txt`, see `sops.age.keyFile`.)

> Anyone who removes the SD card can read this key — and the on-card encrypted
> secret with it. That is inherent to a device with no TPM/secure element:
> physical possession = access. sops protects the **repo/CI/cache**, not against
> a stolen card. Rotate the PSK if a card is lost.

## Rotate / change a secret

```sh
sops secrets/<host>.yaml              # edit values in $EDITOR
sops updatekeys secrets/<host>.yaml   # after changing .sops.yaml recipients
```
