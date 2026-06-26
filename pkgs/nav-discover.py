#!/usr/bin/env python3
"""nav-discover — list serial devices and HATs, emit ready-to-paste Nix snippets.

Mirrors OpenPlotter's "Serial" app: enumerate tty devices with pyudev, read
their USB identity (vendor/product/serial) or device-tree port, optionally sniff
NMEA0183 to guess the role, then print the matching
`services.navigation.serialDevices.*` (or `services.navigation.gps`) block.

It also probes i2c-1 and USB to spot the fitted HATs and emits the matching
`services.navigation.hardware.hats.*` / `.modules.*` toggles.

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

# I2C signatures on i2c-1 used to recognise a fitted HAT (probed read-only).
I2C_BUS = 1
MACARTHUR_ADDR = 0x4D  # SC16IS752 dual UART — unique to the MacArthur HAT
IMU_ADDRS = (0x68, 0x69)  # ICM20948 IMU — Pypilot HAT (0x68 also = MacArthur RTC)

# USB vendor id of the SIM7600X cellular modem (SimTech Inc.).
SIM7600X_VENDOR = "1e0e"


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

    props = dev.properties
    return {
        "devname": props.get("DEVNAME"),
        "vendor": props.get("ID_VENDOR_ID"),
        "product": props.get("ID_MODEL_ID"),
        "serial": props.get("ID_SERIAL_SHORT") or props.get("ID_USB_SERIAL_SHORT"),
        "port": port_path(dev),
    }


def list_serial(context):
    """Real serial ports only: skip pty/console virtuals and the ttyS dummies."""

    out = []
    for dev in context.list_devices(subsystem="tty"):
        props = dev.properties
        devpath = props.get("DEVPATH", "")
        if not props.get("DEVNAME"):
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


def emit(info, role, baud, sniffed, used):
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

    # Keep registry keys unique within a scan (two NMEA sensors would otherwise
    # both suggest ttyOP_nmea — a duplicate attribute when pasted).
    base = ROLE_SYMLINK.get(role, "ttyOP_nmea")
    name = base
    suffix = 2
    while name in used:
        name = f"{base}{suffix}"
        suffix += 1
    used.add(name)

    print(
        f"services.navigation.serialDevices.{name} = {{\n"
        f"  {match}\n"
        f'  role = "{role}";\n'
        f"  baudrate = {baud};\n"
        "};\n"
    )


def probe_i2c(addrs):
    """Read-byte probe on i2c-1; return the subset of `addrs` that ACK.

    Returns None when the bus itself is unreachable (no i2c-1, or missing i2c
    group / root) — distinct from an empty set (bus present, no device).
    """

    from smbus2 import SMBus

    try:
        present = set()
        with SMBus(I2C_BUS) as bus:
            for addr in addrs:
                try:

                    # A single byte read ACKs the address without writing; safe
                    # on the RTC / IMU / UART-expander chips we look for.
                    bus.read_byte(addr)
                    present.add(addr)
                except OSError:
                    pass
        return present
    except (FileNotFoundError, PermissionError, OSError):
        return None


def usb_vendor_present(context, vendor):
    """True if any USB device exposes the given vendor id."""

    for dev in context.list_devices(subsystem="usb"):
        if dev.properties.get("ID_VENDOR_ID") == vendor:
            return True
    return False


def detect_hats(context):
    """Print the `services.navigation.hardware.*` block for the fitted HATs."""

    print("# --- HATs / hardware modules ---")

    # Pypilot and MacArthur both live on i2c-1; the SC16IS752 at 0x4d is unique
    # to MacArthur, so it disambiguates the shared IMU/RTC address 0x68.
    present = probe_i2c((MACARTHUR_ADDR, *IMU_ADDRS))
    if present is None:
        print("# i2c-1 unreadable (no bus, or run as root / i2c group) — HAT probe skipped")
    elif MACARTHUR_ADDR in present:
        print(
            "services.navigation.hardware.hats.enableMacArthur = true;"
            f"  # SC16IS752 @ i2c-1 0x{MACARTHUR_ADDR:02x}"
        )
    elif present & set(IMU_ADDRS):
        hit = min(present & set(IMU_ADDRS))
        print(
            "services.navigation.hardware.hats.enablePypilot = true;"
            f"  # IMU @ i2c-1 0x{hit:02x}"
        )
    else:
        print("# no Pypilot/MacArthur signature on i2c-1 (IMU 0x68/0x69, SC16IS752 0x4d)")

    # SIM7600X enumerates as a SimTech USB modem.
    if usb_vendor_present(context, SIM7600X_VENDOR):
        print(
            "services.navigation.hardware.hats.enableSim7600x = true;"
            f"  # SimTech modem (USB {SIM7600X_VENDOR})"
        )

    # No safe bus probe without loading their drivers — flagged for manual enable.
    print("# XPT2046 touchscreen: not auto-detectable (SPI) — set hats.enableXpt2046 if fitted")
    print("# Camera Module 3 Wide: not auto-detectable (CSI) — set modules.enableCamera3Wide if fitted")


def emit_serial(devices, sniff_ports):
    """Print the serial-device section (one Nix snippet per port)."""

    print("# --- serial devices ---")

    # Track suggested registry keys to keep them unique across the scan.
    used = set()

    for dev in devices:
        info = describe(dev)
        if sniff_ports:
            role, baud, err = sniff(info["devname"])
            if err:
                ident = " ".join(
                    f"{k}={info[k]}" for k in ("vendor", "product", "serial") if info[k]
                )
                print(f"# {info['devname']}  {ident or 'no USB id'}  — {err}\n")
                continue
            emit(info, role, baud, sniffed=True, used=used)
        else:
            emit(info, guess_role(info), baud=38400, sniffed=False, used=used)


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

    context = pyudev.Context()

    devices = list_serial(context)
    if devices:
        emit_serial(devices, sniff_ports=args.sniff)
    else:
        print("# --- serial devices ---")
        print("# none found")

    print()
    detect_hats(context)


if __name__ == "__main__":
    main()
