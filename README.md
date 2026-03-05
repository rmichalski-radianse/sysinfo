# radianse_diag.sh

A diagnostic script for Radianse kiosk Raspberry Pi units. Intended for use when a Pi is reported as slow, unresponsive, or is being evaluated for RMA. Launches an interactive menu with four options covering full diagnostics, quick health checks, SD card testing, and log collection.

---

## Usage

```bash
sudo bash radianse_diag.sh
```

> The script requires `sudo` and will exit immediately with an error message if run without it. `sudo` is needed for cache flushing (disk read benchmarks), some `dmesg` / kernel reads, and raw device access during the SD card test. Run it from whatever directory you want output archives dropped in.

---

## Menu Overview

```
[1]  Full System Diagnostic       → saves .tar.gz
[2]  Quick Snapshot               → terminal output only
[3]  SD Card Health Test          → terminal output only
[4]  Collect & Archive Logs       → saves .tar.gz
[Q]  Quit
```

Options **1** and **4** produce a `.tar.gz` file in the same directory the script was run from. Options **2** and **3** are live terminal readouts only — nothing is written to disk.

---

## Option 1 — Full System Diagnostic

Runs a comprehensive system analysis and packages everything into a timestamped archive:

```
radianse_diag_<hostname>_<YYYYMMDD_HHMMSS>.tar.gz
```

### Archive Contents

```
radianse_diag_<hostname>_<timestamp>/
├── report.txt                         # Full diagnostic report
└── logs/
    ├── home_Director_RadianseServices_logs/   # Copied service logs
    ├── home_Director_UpdateService_logs/      # Copied service logs
    └── journal_full.txt                       # Last 2000 system journal entries
```

### What the report covers

**System overview** — kernel, OS release, Pi model, serial number, board revision, uptime.

**CPU** — full `lscpu` output, per-core frequencies, active CPU governor, and a full decode of the `vcgencmd get_throttled` register. Each bit is checked and reported in plain English:

| Flag | Meaning |
|------|---------|
| Bit 0 | Currently under-voltage |
| Bit 1 | Currently ARM frequency capped |
| Bit 2 | Currently throttled |
| Bit 3 | Soft temperature limit active |
| Bit 16 | Under-voltage has occurred since last boot |
| Bit 17 | Frequency capping has occurred since last boot |
| Bit 18 | Throttling has occurred since last boot |
| Bit 19 | Soft temperature limit has occurred since last boot |

**CPU benchmark** — single-core and multi-core prime number test via `sysbench`. Falls back to a timed `bc` computation of 2,000 digits of π if sysbench is not installed.

**Temperature** — SoC temperature via `vcgencmd`, all thermal zones, with threshold warnings (caution >70°C, critical >80°C).

**Memory** — `free -h` summary and full `/proc/meminfo`. Memory benchmark via `sysbench` (512MB transfer).

**Storage** — `df -h`, `lsblk`, 64MB read/write `dd` benchmark with cache flush between tests. dmesg scan for I/O errors, MMC/SD errors, and EXT4 filesystem errors. `/proc/mounts` check for read-only remounts.

**Processes** — top 20 by CPU, top 20 by memory, total count, zombie count.

**Load average** — 1/5/15-minute averages with a warning if 1-minute load exceeds core count.

**Network** — interface addresses, routes, per-interface stats, DNS resolution test, connectivity ping to 8.8.8.8.

**Chromium & display** — running Chromium processes, `xrandr` output, ARM/GPU memory split.

**Systemd services** — all failed units, full service state list.

**Journal errors** — last 200 entries at warning level or above.

**Serial/USB devices** — `/dev/ttyUSB*` and `/dev/ttyACM*` enumeration, `lsusb` output.

**Log collection** — copies all directories listed in `FULL_DIAG_LOG_DIRS` into the archive as-is, preserving file structure. Also exports last 2000 journal lines to `logs/journal_full.txt`.

---

## Option 2 — Quick Snapshot

Live terminal readout of current system state. Nothing is saved to disk.

Displays: uptime, load average, temperature, CPU throttle flags decoded, memory usage with swap, disk usage per mount with fill-level warnings, SD card filesystem health indicators, CPU usage percentage, top 8 processes by CPU and memory, **SecureVendor / BackOffice network status** (see below), connected serial/USB devices with manufacturer info, and any failed systemd units.

### SecureVendor / BackOffice IP Check

The quick snapshot checks all assigned IPv4 addresses and reports one of three states:

| Result | Meaning |
|--------|---------|
| `[OK] Hub has the correct SecureVendor IP: 172.16.50.2` | The hub is on the SecureVendor network with the expected static IP |
| `[OK] Hub is utilizing BackOffice Network (IP: x.x.x.x)` | The hub has an address in the `192.168.200.0/24` subnet |
| `[!!] Neither SecureVendor IP nor BackOffice subnet detected` | Unexpected network configuration — current IPs are listed below the warning |

---

## Option 3 — SD Card Health Test

A focused test suite for diagnosing failing or degraded SD cards. Nothing is saved to disk.

**Device identification** — model, manufacturer ID, OEM ID, serial number, firmware revision, and manufacture date read from sysfs.

**Filesystem status** — checks if any partition has remounted itself read-only. This is an automatic kernel response to filesystem errors and is a near-certain indicator of prior SD card corruption.

**dmesg scan** — searches kernel ring buffer for `mmcblk` errors, I/O errors, `blk_update_request`, bad sector reports, and EXT4 filesystem errors.

**Journal scan** — searches recent journal for filesystem and I/O error entries.

**SMART** — runs `smartctl -H` and `smartctl -A` if installed. Note: SMART support varies widely across SD card models; the other tests below are generally more reliable for SD diagnosis.

**MMC wear leveling** — uses `mmc extcsd read` to retrieve wear leveling counters and pre-EOL status indicators if the card supports Extended CSD (requires `mmc-utils`).

**Read/write speed** — 64MB sequential read from the raw device (after cache flush) and 32MB write to `/tmp`. Results are compared against thresholds with plain-English verdicts.

**Bad block scan** — opt-in `badblocks -sv` scan of the entire card surface. Safe and non-destructive but slow (10–30 min depending on card size).

**Summary** — re-evaluates all key signals and presents a final verdict with confidence indicators.

### Speed thresholds

| Speed | Read | Write |
|-------|------|-------|
| Critical | < 5 MB/s | < 2 MB/s |
| Warning | < 15 MB/s | < 6 MB/s |
| OK | ≥ 15 MB/s | ≥ 6 MB/s |

---

## Option 4 — Collect & Archive Logs

Compresses the configured log directories into a standalone timestamped archive. Nothing else is included — no report, no benchmarks.

```
radianse_logs_<hostname>_<YYYYMMDD_HHMMSS>.tar.gz
```

Also includes a `journal_full.txt` with the last 2000 system journal lines.

Directories are configured via `LOG_COLLECTION_DIRS` at the top of the script (separate from the full diagnostic list, but can overlap). Missing directories are skipped gracefully and reported at the end.

---

## Configuration

Both log directory lists are at the top of the script:

```bash
# Logs included in the Full Diagnostic archive (Option 1)
FULL_DIAG_LOG_DIRS=(
    "/home/radianse/Director/RadianseServices/logs"
    "/home/radianse/Director/UpdateService/logs"
    "/home/radianse/Director/ServiceManager/logs"
    "/home/radianse/Hub/HubManager/logs"
    "/home/radianse/RadianseInstallManager/logs"
    "/home/radianse/logs"
    # "/home/radianse/AnotherService/logs"
)

# Logs collected by the Log Collection tool (Option 4)
LOG_COLLECTION_DIRS=(
    "/home/radianse/Director/RadianseServices/logs"
    "/home/radianse/Director/UpdateService/logs"
    "/home/radianse/Director/ServiceManager/logs"
    "/home/radianse/Hub/HubManager/logs"
    "/home/radianse/RadianseInstallManager/logs"
    "/home/radianse/logs"
    # "/home/radianse/AnotherService/logs"
    # "/var/log/radianse"
)
```

Add a new quoted path on its own line. Both lists support any number of entries. Missing paths are always skipped gracefully.

---

## Interpreting Results — Common Causes of Slowness

| Symptom | Likely Cause |
|---------|-------------|
| `vcgencmd get_throttled` bits 0–3 active | Active under-voltage or thermal throttling — check PSU and cooling |
| Bits 16–19 set (but not 0–3) | Throttling has occurred since last boot — may be intermittent |
| Temperature > 70°C at idle | Poor airflow or missing heatsink |
| dd read speed < 5 MB/s | Degraded or low-quality SD card |
| dmesg contains `mmcblk` I/O errors | Failing SD card — replace immediately |
| Filesystem mounted read-only | Automatic error recovery — SD card likely corrupted, replace |
| Load average > core count | CPU-bound process hogging resources — check top consumers |
| High memory usage (>90%) | Memory pressure causing swap thrashing — check top memory consumers |

---

## Dependencies

| Tool | Used by | Install |
|------|---------|---------|
| `vcgencmd` | Options 1, 2, 3 | Pre-installed on Raspberry Pi OS |
| `sysbench` | Option 1 (benchmarks) | `sudo apt install sysbench` |
| `bc` | Options 1, 2, 3 (threshold math) | `sudo apt install bc` |
| `smartctl` | Option 3 | `sudo apt install smartmontools` |
| `mmc` | Option 3 (wear data) | `sudo apt install mmc-utils` |
| `badblocks` | Option 3 (block scan) | `sudo apt install e2fsprogs` |
| `journalctl` | Options 1, 4 | Pre-installed on Raspberry Pi OS |
| `lsusb` | Options 1, 2 | `sudo apt install usbutils` |
| `xrandr` | Option 1 | `sudo apt install x11-xserver-utils` |

All checks involving optional tools are skipped gracefully with an install hint if the tool is absent.

---

## Notes

- The script does not modify any system settings or files. The only writes are the `/tmp` test file used for the `dd` write benchmark (removed immediately after) and the output archives themselves.
- It is safe to run on a live, in-service kiosk, though the disk benchmark and bad block scan will cause brief I/O load.
- For a Pi with a completely unresponsive display, all options can be run headlessly over SSH.
- The `TIMESTAMP` variable is set once at script startup. Running multiple options in a single session will produce archives with the same timestamp prefix — this is intentional and makes it easy to correlate files from the same session.