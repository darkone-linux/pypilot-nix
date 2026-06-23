#!/usr/bin/env python3
"""nav-discover — list serial devices and emit ready-to-paste Nix snippets.

Mirrors OpenPlotter's "Serial" app: enumerate tty devices with pyudev, read
their USB identity (vendor/product/serial) or device-tree port, optionally sniff
NMEA0183 to guess the role, then print the matching
`services.navigation.serialDevices.*` (or `services.navigation.gps`) block.

The tool is read-only: it never edits configuration. Paste its output into the
host file and `nixos-rebuild switch`.
"""

import argparse
import sys

import pyudev

# Baud rates probed while sniffing, common first (NMEA0183 std, then GPS, AIS).
SNIFF_BAUDS = [4800, 9600, 38400, 115200]

# NMEA0183 sentence types grouped by the role they reveal.
GNSS_TYPES = {"GGA", "RMC", "GLL", "VTG", "GSA", "GSV", "ZDA"}
AIS_TYPES = {"VDM", "VDO"}

# USB vendor ids known to be GNSS receivers (kept in sync with the module's
# gps.autodetectIds); used to guess "gps" when not sniffing.
GNSS_VENDORS = {"1546", "091e", "0e8d", "1163"}

# Suggested /dev symlink name (and registry key) per role.
ROLE_SYMLINK = {"ais": "ttyOP_ais", "nmea0183": "ttyOP_nmea", "pilot": "ttyOP_pilot"}


def port_path(dev):
    """Device-tree/USB port path used for a `match.port` (soldered UART) rule."""

    # USB device: the interface node name, e.g. "1-1.4:1.0".
    iface = dev.find_parent("usb", "usb_interface")
    if iface is not None:
        return iface.sys_name

    # Onboard UART: the serial controller ancestor, e.g. "fe201000.serial:0.0".
    node = dev
    while node is not None:
        if ".serial" in (node.sys_name or ""):
            return node.sys_name
        node = node.parent
    return None


def describe(dev):
    """Extract the identity fields nav-discover reasons about."""

    return {
        "devname": dev.get("DEVNAME"),
        "vendor": dev.get("ID_VENDOR_ID"),
        "product": dev.get("ID_MODEL_ID"),
        "serial": dev.get("ID_SERIAL_SHORT") or dev.get("ID_USB_SERIAL_SHORT"),
        "port": port_path(dev),
        "driver": dev.get("ID_USB_DRIVER") or (dev.parent and dev.parent.driver),
    }


def list_serial(context):
    """Real serial ports only: skip pty/console virtuals and the ttyS dummies."""

    out = []
    for dev in context.list_devices(subsystem="tty"):
        devpath = dev.get("DEVPATH", "")
        if not dev.get("DEVNAME"):
            continue

        # Pseudo-terminals and the legacy serial8250 placeholders are not gear.
        if "/virtual/" in devpath or "/devices/platform/serial8250" in devpath:
            continue
        out.append(dev)
    return out


def classify(types):
    """Map the set of observed sentence types to a navigation role."""

    if types & AIS_TYPES:
        return "ais"
    if types & GNSS_TYPES:
        return "gps"

    # Depth (DPT/DBT), wind (MWV/MWD), heading… all ride the generic provider.
    return "nmea0183"


def sniff(devname):
    """Open the port, collect NMEA sentence types, return (role, baud, error)."""

    import serial

    for baud in SNIFF_BAUDS:
        try:
            with serial.Serial(devname, baud, timeout=0.5) as port:
                types = set()

                # ~3 s budget: enough for a 1 Hz GPS or a sporadic AIS target.
                for _ in range(6):
                    raw = port.readline().decode("latin-1", "ignore").strip()
                    if raw[:1] in ("$", "!") and len(raw) >= 6:
                        types.add(raw[3:6])
        except (OSError, serial.SerialException) as err:

            # Busy means a service already holds it — sniff before assigning.
            return None, None, f"cannot open (in use by gpsd/signalk?): {err}"

        if types:
            return classify(types), baud, None
    return None, None, "no NMEA0183 sentences detected"


def guess_role(info):
    """Best-effort role without sniffing, from the USB vendor id."""

    if info["vendor"] in GNSS_VENDORS:
        return "gps"
    return "nmea0183"


def match_block(info):
    """The `match = { … };` body, preferring a precise USB identity."""

    if info["vendor"] and info["product"]:
        parts = [f'vendorId = "{info["vendor"]}";', f'productId = "{info["product"]}";']
        if info["serial"]:
            parts.append(f'serial = "{info["serial"]}";')
        return "match = { " + " ".join(parts) + " };"
    if info["port"]:
        return f'match = {{ port = "{info["port"]}"; }};'
    return None


def emit(info, role, baud, sniffed):
    """Print the Nix snippet for one device (with a context comment header)."""

    ident = " ".join(
        f"{k}={info[k]}" for k in ("vendor", "product", "serial", "port") if info[k]
    )
    print(f"# {info['devname']}  {ident or 'no USB id'}")

    if not sniffed:
        print("# role guessed from USB id — run with --sniff to confirm")

    # GPS is owned by gpsd through its own option, not the serial registry.
    if role == "gps":
        if not (info["vendor"] and info["product"]):
            print("# (onboard/portless GPS: wire it via services.navigation.gps.device)\n")
            return
        print(
            "services.navigation.gps = {\n"
            f'  vendorId = "{info["vendor"]}";\n'
            f'  productId = "{info["product"]}";\n'
            "};\n"
        )
        return

    match = match_block(info)
    if match is None:
        print("# no stable identifier (USB id or port) — cannot pin this device\n")
        return

    name = ROLE_SYMLINK.get(role, "ttyOP_nmea")
    print(
        f"services.navigation.serialDevices.{name} = {{\n"
        f"  {match}\n"
        f'  role = "{role}";\n'
        f"  baudrate = {baud};\n"
        "};\n"
    )


def main():
    parser = argparse.ArgumentParser(
        description="Discover serial navigation devices and emit Nix snippets."
    )
    parser.add_argument(
        "--sniff",
        action="store_true",
        help="open each port and read NMEA0183 to detect the role (opt-in: "
        "skips ports already held by gpsd/signalk).",
    )
    args = parser.parse_args()

    devices = list_serial(pyudev.Context())
    if not devices:
        print("# no serial devices found", file=sys.stderr)
        return

    for dev in devices:
        info = describe(dev)
        if args.sniff:
            role, baud, err = sniff(info["devname"])
            if err:
                ident = " ".join(
                    f"{k}={info[k]}" for k in ("vendor", "product", "serial") if info[k]
                )
                print(f"# {info['devname']}  {ident or 'no USB id'}  — {err}\n")
                continue
            emit(info, role, baud, sniffed=True)
        else:
            emit(info, guess_role(info), baud=38400, sniffed=False)


if __name__ == "__main__":
    main()
