# polaris

A system monitor for the Deepin desktop: a [dde-shell](https://github.com/linuxdeepin/dde-shell)
dock applet in the left part of the taskbar, plus a control centre plugin that
decides what it shows.

- CPU usage
- CPU temperature
- Memory usage
- Swap usage
- Network download / upload rate (`↓` / `↑`)
- Power draw and fan speed, when the hardware reports them (off by default)

Readings are taken straight from `/proc/stat`, `/proc/meminfo`, `/proc/net/dev`
and the hwmon/thermal sysfs entries — the dock item and the control centre need no
daemon and no privileges. The one reading the kernel keeps to root (the CPU
package power counter) comes from an optional helper package instead, see
[Power and fan speed](#power-and-fan-speed).

```
CPU 23% · TEMP 56℃ · MEM 45% · SWP 12% · ↓ 1.2M/s · ↑ 340K/s
CPU 23% · TEMP 56℃ · MEM 45% · SWP 12% · ↓ 1.2M/s · ↑ 340K/s · PWR 46W · FAN 914
```

Power and fan speed are switched off by default because they make the line half
again as wide; both are in the control centre, and both show `--` when the
hardware has nothing to say.

Hovering shows a tooltip with the exact `used / total GiB` figures and the
transfer rates, and lights up the dock's own hover background, inset a few pixels
so it reads as a pill around the digits.

### Charts on the taskbar

The line can also draw the history of each reading, so the taskbar shows where a
reading is going and not only where it is. **Taskbar charts** in the control
centre picks one of three:

| Mode | The item shows |
| --- | --- |
| `off` (default) | the numbers, as above |
| `both` | each number with its history drawn under it |
| `line` | the histories with their labels and no numbers |

One setting for the whole line rather than one per metric: *which* readings are
watched is already a per-metric switch, and a taskbar whose figures were half
numbers and half charts would read as neither. Which metrics get a chart is
therefore the same switch list as above — `line` mode with only CPU and memory
switched on is a two-chart taskbar.

A chart sits **beside** its number on a horizontal dock — about a dock-thickness
and a quarter long, which is as wide as the label and the number it follows —, where the taskbar has
width to spare, and under it on a vertical one, which is only `dockSize` wide and
has no room for that. Both the chart and the text follow the dock's own thickness
setting — the item takes its size from `Panel.rootObject.dockSize`, the thickness
the dock hands it, and deliberately not from `dockItemMaxSize`, which the task
manager solves for the space each item gets and which does not move when the
taskbar is made taller.

Each chart is scaled to what it measures rather than to its own window: usage and
temperature are drawn against 0..100 (`%` and `°C`), a fan against its chip's own
ceiling — the same rule as its gauge in the panel — and a transfer rate, which has
no ceiling, fits its own samples. A chart is sized from the taskbar, never from
its samples, so switching the charts on does not cost the item its no-jitter
guarantee: `tests/test_no_jitter.qml` fails if a chart ever grows with its data,
and fails if the item stops following the dock size it is given.

## The detail panel

Clicking the item opens a panel with everything the taskbar line has no room for:
where the cpu time went (user / system / iowait / idle in one bar), a bar per
core, memory split into used / cache / free the way `free(1)` splits it, swap as
its own bar under it — it fills and empties on its own timescale, and a machine
that has swapped everything out is not a machine with full memory — download and
upload with their transfer history, and the busiest processes with a bar per
row. Power and cooling get a card of their own — with
the power history and one gauge per fan — but only when the machine reports
either. Every chart keeps the last 60 samples, which is two minutes at the
default interval.

The process list can be read two ways round — by CPU or by memory — with a switch
in the table's own header; the rows, the in-row bars and the accent colour all
follow the order that is on, and the choice is stored with the other settings, so
it survives a restart and shows up in the control centre as well.

The colours come from one palette per theme, so the panel follows the system's
light or dark mode; each metric owns a colour, and the temperature moves through
green, amber and red as it climbs.

Both the panel and the hover preview are `Window`s sharing one placement rule
(`package/DockPopup.qml`), anchored with the layer shell to the dock item's edge
the way the notification centre anchors itself — instead of dde-shell's shared
panel popup, because each needs its own size, its own frosted background and its
own behaviour. The panel closes when it loses focus, when the dock is clicked,
when the panel hides, or on Escape.

The `×` button sends `SIGTERM` to the process — a request to quit, which is what
a process is supposed to handle by saving and exiting. Two refusals are
deliberate: the applet never signals itself or `init`, and it re-checks the
command name before signalling, because between filling the panel and the click
the pid may already belong to a different program.

## Settings

The dock item reads its settings through DConfig (`org.deepin.ds.dock.polaris`),
so the readings the control centre switches off disappear from the taskbar
immediately, with no service in between.

| Key | Default | Meaning |
| --- | --- | --- |
| `showCpu` | `true` | CPU usage |
| `showTemperature` | `true` | CPU temperature |
| `showMemory` | `true` | Memory usage |
| `showSwap` | `true` | Swap usage |
| `showNetwork` | `true` | Download / upload rate |
| `refreshIntervalMs` | `2000` | How often the readings update (500–10000) |
| `processCount` | `8` | Processes listed in the panel (3–30) |
| `processSort` | `cpu` | Process list ordered by `cpu` or by `memory` |
| `showPower` | `false` | Power draw on the dock item |
| `showFan` | `false` | Highest fan speed on the dock item |
| `fanScaleRpm` | `3000` | RPM the fan gauges treat as full speed, when the chip reports no ceiling |
| `dockChartMode` | `off` | How the item draws its metrics: `off`, `both` or `line` |

The same values can be set from a shell:

```shell
dde-dconfig set -a org.deepin.ds.dock.polaris -r org.deepin.ds.dock.polaris -k refreshIntervalMs -v 1000
```

## Network interfaces

Only interfaces that a driver is bound to are summed (`/sys/class/net/<name>/device`
exists). Bridges, bonds, VLANs, container veth pairs, VM taps and VPN tunnels
such as `tailscale0` or `wg0` ride on top of another interface whose counters
already include their bytes, so counting them as well would report up to twice
the traffic that really crossed the wire. On a machine where no interface has
that link — a modem-only `ppp0`, for instance — everything but loopback is
counted instead of showing nothing.

## Power and fan speed

Fan speeds come from the hwmon chips (`fan*_input`, named by their `fan*_label`
when the chip has one). A header with nothing plugged into it reads zero exactly
like a fan that has stopped, so zeros are only shown when the whole machine
reports zeros — a stopped fan stays visible, an unused header does not become
noise. The gauge next to each fan is drawn against the ceiling the chip reports
(`fan*_max`), or against `fanScaleRpm` when it reports none, so a fan at 900 RPM
out of a 3000 RPM ceiling reads as a third full rather than as "as fast as the
fastest fan installed". Desktop Super-I/O chips, laptop EC drivers and GPU fans all live under
hwmon, so the scan finds them by the interface rather than by a driver list; a
machine whose EC exposes no fan at all simply shows `--`.

Power is taken from the first of these that answers, and the panel names which
one it was, because they do not measure the same thing:

| Source | Measures | Where it exists | Readable as a user |
| --- | --- | --- | --- |
| ACPI battery `power_now` | the whole machine | laptops | yes |
| `polaris-sensord` (see below) | the cpu package | wherever the counter exists | yes, via the helper |
| powercap `intel-rapl` (`energy_uj`) | the cpu package | most x86 since Sandy Bridge / Zen | **no — the kernel ships it root-only** |
| hwmon `power*_average` | one device, named in the panel | some gpus and laptops | yes |
| NVML (`libnvidia-ml`) | the graphics card | machines with the NVIDIA driver | yes |

Every source that answers is listed in the panel, each row naming what it
measures, because the readings a machine calls "power" are not the same thing: a
laptop's battery is the whole machine while an NVIDIA card is only the card. The
dock line shows the first one. So a laptop shows the machine's draw out of the
box, a desktop usually shows the cpu package through the helper described next,
and a machine with neither says so instead of inventing a number.

The graphics card is read through NVML, which is opened at runtime and needs no
privileges and no build dependency — a machine without the driver simply has no
such row. The counter is read as a rate between two samples,
with the wrap at `max_energy_range_uj` handled.

### polaris-sensord

`polaris-sensord` is a small system service, shipped in its own package, that
samples the readings the kernel keeps to root and publishes them as named values:

```
# /run/polaris/sensors
format=1
time=1790144630
power-watts=25.01
power-source=rapl
```

The dock item reads that file and believes it only while it is fresh — a stopped
service leaves its last reading behind, and yesterday's watts are worse than
none — so removing the package simply falls back to whatever the applet can read
itself, which is why `polaris` only *recommends* it.

If a second privileged reading is ever needed, it is one more line in the file
and one more key in the parser — the same shape as the readings that needed no
privilege at all. See below for what keeps the privilege narrow.

The alternative, if you would rather not run a service, is to open the counter to
every user yourself:

```
# /etc/udev/rules.d/99-powercap.rules  (example; not verified on this machine)
SUBSYSTEM=="powercap", ACTION=="add", RUN+="/bin/chmod 0444 /sys%p/energy_uj"
```

## What runs with privileges

Only `polaris-sensord` does, and it is deliberately narrow: it reads three sysfs
files and writes one file of its own. It takes **no input from any client** — no
socket, no bus name, no configuration parsing — so there is no way to ask root for
anything; the set of readings it can hand out is fixed at build time, and it
publishes named values rather than accepting a path or a command. systemd pins it
down further: `ProtectSystem=strict` with `ReadWritePaths=/run/polaris` means it
cannot write outside its own directory even if it were misconfigured,
`NoNewPrivileges` closes the door on regaining privileges, `ProtectHome` and no
network keep the rest away. Its temporary file is unlinked and then created
exclusively, so a symlink planted at that name is not followed. What it publishes
is a power figure — not a secret, which is why the file is world-readable on
purpose.

Everything else runs unprivileged, and the one place the dock item acts on the
system is ending a process, which it does as the user: it never signals `init` or
itself, it re-reads `/proc/<pid>/stat` and requires **both the command name and
the start time** to still match what the panel listed, and it signals through a
pidfd so the check and the signal cannot be split by the pid being recycled in
between.

## Load colours

Each value is coloured by its own load level, in three steps. The shades are
chosen per theme so every one of them stays at **4.5:1 or better** against the
background `DockPalette.iconTextPalette` assumes (white in light, near-black in
dark):

| Level | Usage | Temperature | Light theme | Dark theme |
| --- | --- | --- | --- | --- |
| normal | < 60% | < 70 °C | `#157F45` | `#5FD08A` |
| high | ≥ 60% | ≥ 70 °C | `#A55F00` | `#F2B441` |
| extreme | ≥ 85% | ≥ 85 °C | `#C62828` | `#FF6B6B` |

When no temperature sensor is found the value is `--` in a dimmed neutral colour.

## No jitter

Every value is drawn inside a cell sized for the widest text it can ever show
(`100%` / `100℃` / `999.9M/s`) and right aligned, so the item keeps exactly the
same size while the numbers change — no twitching of the taskbar.
`tests/test_no_jitter.qml` fails if that ever stops holding, including when
metrics are switched off in the control centre and when the taskbar charts are
switched on.

A vertical dock is only `dockSize` pixels wide, so there the values are stacked
instead of sharing one line, the labels disappear and the rates drop their unit
(`12M`). The font follows the dock size (`clamp(dockSize * 0.34, 13, 18)`).

## Layout

| Path | Purpose |
| --- | --- |
| `src/polarisapplet.{h,cpp}` | `DApplet` plugin: sampling, settings, process list, kill |
| `src/systemreader.h` | Pure parsers for `/proc/stat`, `/proc/meminfo`, `/proc/net/dev`, `/proc/<pid>/stat`, hwmon, powercap and the helper's file |
| `src/sensord/main.cpp` | The privileged helper: samples what root can read, publishes named values |
| `data/polaris-sensord.service` | Its unit: sandboxed, `/run/polaris` runtime directory |
| `package/main.qml` | Dock glue: `AppletItem`, hover background, tooltip, the panel window |
| `package/MonitorItem.qml` | The metric line itself, numbers and taskbar charts (no dde-shell imports, so it can be rendered standalone) |
| `package/DetailWindow.qml` | The panel's own layer-shell window, its palette and its placement |
| `package/DetailPanel.qml` | The panel body: the sections and their readings |
| `package/Sparkline.qml` | The transfer/usage history chart |
| `package/SegmentedBar.qml` | The proportional multi-segment bar |
| `package/SwapBar.qml` | Swap as its own bar, empty on a machine without swap |
| `package/ProcessTable.qml` | The process list with its per-row bars |
| `package/format.js` | The one place rates and byte counts are spelled out |
| `package/metadata.json` | Dock plugin metadata, `Parent: org.deepin.ds.dock` |
| `dcc/` | Control centre plugin (`DccObject` page on top of `dccData`) |
| `configs/` | DConfig schema, installed to `/usr/share/dsg/configs/` |
| `tests/test_systemreader.cpp` | Checks for the parsers |
| `tests/test_no_jitter.qml` | Checks that the item never resizes |
| `tests/test_charts.qml` | Checks the chart, bar and swap-bar geometry on empty, single, junk and oversized input |
| `tests/test_applet_bindings.py` | Checks every property the QML reads or sets actually exists |
| `debian/` | DEB packaging |

## Build & test

```shell
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
ctest --test-dir build --output-on-failure
```

The control centre plugin is built only where its development files are
installed; `-DBUILD_DCC_PLUGIN=OFF` builds the dock applet on its own.

## Build the DEB

```shell
sudo apt build-dep .
dpkg-buildpackage -b -uc -us
```

The build produces `polaris` (dock item and control centre page) and
`polaris-sensord` (the privileged helper).

`polaris_*.deb` installs:

- `/usr/lib/<triplet>/dde-shell/org.deepin.ds.dock.polaris.so`
- `/usr/share/dde-shell/org.deepin.ds.dock.polaris/` — the dock item and the panel's QML
- `/usr/lib/<triplet>/dde-control-center/plugins_v1.1/polaris/` — the control centre page
- `/usr/share/dsg/configs/org.deepin.ds.dock.polaris/org.deepin.ds.dock.polaris.json`

Restart the dock to pick the applet up:

```shell
systemctl --user restart dde-shell-plugin@org.deepin.ds.dock.service
```

## Notes

- `dockOrder: 10` is the last slot of the left dock part (`(0, 10]`), so the
  item sits just before the centre group (launcher and running apps).
- Temperature resolution prefers a real CPU sensor (`coretemp`, `k10temp`,
  `zenpower`, `x86_pkg_temp`, ...) and only falls back to `acpitz`.
- To disable the applet without uninstalling, set `enable` to `false` in the
  DConfig subpath `org.deepin.dde.shell/org.deepin.ds.dock.polaris`.
