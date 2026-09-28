#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Checks the properties the privileged helper must not lose: it publishes a rate
# from the energy counter, it keeps updating that file, and it never writes
# through something planted at its temporary path.

import os
import pathlib
import subprocess
import sys
import tempfile
import time

DAEMON = sys.argv[1] if len(sys.argv) > 1 else "polaris-sensord"


def fail(message):
    print(f"FAILED: {message}")
    sys.exit(1)


def write(path, contents):
    pathlib.Path(path).parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as handle:
        handle.write(contents)


def main():
    with tempfile.TemporaryDirectory() as root:
        powercap = os.path.join(root, "powercap")
        zone = os.path.join(powercap, "intel-rapl:0")
        write(os.path.join(zone, "name"), "package-0\n")
        write(os.path.join(zone, "max_energy_range_uj"), "262143328850\n")
        write(os.path.join(zone, "energy_uj"), "1000000000\n")

        output = os.path.join(root, "sensors")
        daemon = subprocess.Popen(
            [DAEMON, "--powercap-root", powercap, "--output", output],
            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)

        try:
            # 5 J every 100 ms is 50 W; the daemon samples every 2 s.
            deadline = time.time() + 8
            reading = ""
            while time.time() < deadline:
                write(os.path.join(zone, "energy_uj"), str(1000000000 + int((time.time() % 100) * 50000000)))
                time.sleep(0.05)
                if os.path.exists(output):
                    reading = open(output).read()
                    if "power-watts" in reading:
                        break

            if "time=" not in reading:
                fail(f"no timestamp published: {reading!r}")
            if "power-watts" not in reading:
                fail(f"no power published after 8 s: {reading!r}")
            if "power-source=rapl" not in reading:
                fail(f"no source published: {reading!r}")

            first = reading
            deadline = time.time() + 6
            while time.time() < deadline:
                write(os.path.join(zone, "energy_uj"), str(2000000000 + int((time.time() % 100) * 50000000)))
                time.sleep(0.05)
                reading = open(output).read()
                if reading != first and "power-watts" in reading:
                    break
            if reading == first:
                fail("the published file stopped updating")

            # A symlink planted at the temporary path must not be written through.
            victim = os.path.join(root, "victim")
            write(victim, "untouched\n")
            os.remove(output)
            os.symlink(victim, output + ".new")

            deadline = time.time() + 6
            while time.time() < deadline:
                write(os.path.join(zone, "energy_uj"), str(3000000000 + int((time.time() % 100) * 50000000)))
                time.sleep(0.05)
                if os.path.exists(output) and open(output).read() != "":
                    break

            if open(victim).read() != "untouched\n":
                fail("wrote through a symlink planted at the temporary path")
            if not os.path.exists(output) or os.path.islink(output):
                fail("did not publish over the planted symlink")
        finally:
            daemon.terminate()
            daemon.wait(timeout=5)

    print("sensord publish checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
