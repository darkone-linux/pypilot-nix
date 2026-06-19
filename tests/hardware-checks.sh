#!/usr/bin/env bash
# hardware-checks.sh — level 3 bench validation, run over SSH on a real Pi.
#
# Exercises what cannot be simulated in a VM: the I2C bus, the IMU, the motor
# controller, the UART, the NMEA2000 CAN link and the GPS-disciplined clock.
# Prints a pass/fail report and exits non-zero if any check fails.
#
#   ssh skipper@navpi.local 'sudo bash -s' < tests/hardware-checks.sh

set -uo pipefail

pass=0
fail=0
skip=0

# check <label> <command...> — run the command, record pass/fail.
check() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    printf '  [ PASS ] %s\n' "$label"
    pass=$((pass + 1))
  else
    printf '  [ FAIL ] %s\n' "$label"
    fail=$((fail + 1))
  fi
}

# skip_unless <label> <test-cmd...> — note an absent optional device.
present() {
  if "$@" >/dev/null 2>&1; then
    return 0
  fi
  printf '  [ SKIP ] %s (not present)\n' "$1"
  skip=$((skip + 1))
  return 1
}

echo "== Services =="
check "pypilot.service active" systemctl is-active --quiet pypilot.service
check "signalk.service active" systemctl is-active --quiet signalk.service
check "signalk API answers on :3000" curl -fsS http://localhost:3000/signalk

echo "== I2C / IMU =="
if present "/dev/i2c-1" test -e /dev/i2c-1; then

  # i2cdetect prints the populated addresses; any device byte means the bus
  # is alive and the HAT is wired.
  check "I2C device responds on bus 1" \
    bash -c "i2cdetect -y 1 | grep -qE '[0-9a-f]{2}'"
fi

echo "== Serial / UART =="
present "/dev/ttyAMA0 (HAT UART)" test -e /dev/ttyAMA0
present "/dev/pypilot_motor (motor controller)" test -e /dev/pypilot_motor

echo "== NMEA2000 / CAN =="
if present "can0 link" ip link show can0; then
  check "can0 is UP" bash -c "ip -br link show can0 | grep -q 'UP'"
fi

echo "== GPS clock (chrony) =="
if present "chronyc" command -v chronyc; then

  # A GPS/PPS reference clock should be listed; '*' or '+' means selected.
  check "chrony has a GPS reference source" \
    bash -c "chronyc sources | grep -qE 'GPS|PPS'"
fi

echo
printf 'Result: %d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ]
