# Secrets (sops)

Encrypted secrets, committed in their encrypted form and decrypted on the device
at activation by [sops-nix](https://github.com/Mic92/sops-nix). Plaintext never
enters git nor the Nix store.

Currently: `wifi.yaml` holds the `lab-rpi02` wifi PSK (`wifi_psk`).

## One-time setup (workstation)

```sh
nix develop            # brings sops + age into PATH

# 1. Mint the device age key. Keep the private key OUT of git.
age-keygen -o age-key.txt
age-keygen -y age-key.txt          # prints the public key (age1…)

# 2. Put that public key in ../.sops.yaml (replace the placeholder).

# 3. Create the encrypted secret. sops opens $EDITOR; write one line:
#      wifi_psk: your-wifi-password
sops secrets/wifi.yaml
```

`secrets/wifi.yaml` is now safe to commit (encrypted). The SSID is **not** here —
it is not a secret; set it in `hosts/lab-rpi02/configuration.nix` (`wifiSsid`).

## Provision the key on the Pi (before first boot)

The Zero 2 W is headless: without the age key it cannot decrypt the PSK, cannot
join wifi, and is unreachable. After flashing the SD card, drop the **private**
key on the FAT boot partition where the host expects it:

```sh
# the boot partition mounts at /boot/firmware on the running Pi
mkdir -p /run/media/$USER/FIRMWARE/secrets
cp age-key.txt /run/media/$USER/FIRMWARE/secrets/age.txt
```

(Path on the Pi: `/boot/firmware/secrets/age.txt`, see `sops.age.keyFile`.)

## Rotate / add recipients

```sh
sops secrets/wifi.yaml              # change values
sops updatekeys secrets/wifi.yaml   # after editing .sops.yaml recipients
```
