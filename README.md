# radianse_diag.sh

A diagnostic script for Radianse kiosk Raspberry Pi units. Intended for use when a Pi is reported as slow, unresponsive, or is being evaluated for RMA. Collects system health data, runs performance benchmarks, and packages service logs into a timestamped `.tar.gz` archive.

---

## Usage

```bash
sudo bash radianse_diag.sh
```

> `sudo` is required for cache flushing (disk read benchmarks) and some `dmesg` / kernel reads. Run it from whatever directory you want the output archive dropped in.

**Output:** A single archive named:
```
radianse_diag_<hostname>_<YYYYMMDD_HHMMSS>.tar.gz
```

The archive contains a `report.txt` with all diagnostic output and a `logs/` subdirectory with copies of all collected service logs.

---

## What It Checks

### 1. System Overview
- Kernel version and OS release (`uname`, `/etc/os-release`)
- Raspberry Pi model, serial number, and board revision (from `/proc/device-tree/model` and `/proc/cpuinfo`)
- System uptime

### 2. CPU
- Full CPU info via `lscpu`
- Current frequency per core (from `/sys/devices/system/cpu/*/cpufreq/scaling_cur_freq`)
- Active CPU governor (e.g. `ondemand`, `powersave`, `performance`)
- **Throttle flag decode via `vcgencmd get_throttled`** — each bit of the throttle register is checked and reported in plain English:

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

This is the most reliable way to confirm whether thermal or power issues are causing slowness.

### 2b. CPU Benchmark
- Uses `sysbench` (if installed) to run a prime-number computation test on both a single core and all cores
- Falls back to a timed `bc` computation of 2,000 digits of π if `sysbench` is not available
- Install sysbench with: `sudo apt install sysbench`

### 3. Temperature
- SoC temperature via `vcgencmd measure_temp`
- All thermal zones from `/sys/class/thermal/`
- Threshold warnings:
  - **> 70°C** — Caution
  - **> 80°C** — Critical warning

### 4. Memory
- Current usage summary (`free -h`) and full `/proc/meminfo`

### 4b. Memory Benchmark
- Uses `sysbench` to measure sequential memory throughput (512MB transfer test)

### 5. Storage & Disk Health
- Disk usage (`df -h`) and block device layout (`lsblk`)
- **Write benchmark:** 64MB write via `dd` with `conv=fsync` to force a physical write
- **Read benchmark:** 64MB read via `dd` after flushing the page cache, so it reflects actual SD card read speed rather than cached data
- **dmesg scan** for I/O errors, MMC/SD card errors, EXT4 filesystem errors, and bad sector reports
- `/proc/mounts` check — if a filesystem has remounted itself read-only, that's a sign it recovered from a serious error

### 6. Processes
- Top 20 processes by CPU usage
- Top 20 processes by memory usage
- Total process count
- Zombie process count

### 7. Load Average
- Current 1, 5, and 15-minute load averages
- Warns if the 1-minute load average exceeds the number of CPU cores (indicating the system is overloaded)

### 8. Network
- All interface addresses and routes
- Per-interface packet/error/drop statistics
- DNS resolution test (`nslookup` or `dig`)
- Basic connectivity ping to `8.8.8.8`

### 9. Chromium & Display
- Lists all running Chromium processes and their arguments
- Display environment (`$DISPLAY`, `xrandr` output)
- ARM/GPU memory split via `vcgencmd get_mem`

### 10. Systemd Services
- All failed units
- Full list of all service states (active, inactive, failed)

### 11. Journal / Syslog Errors
- Last 200 log entries at warning level or above (via `journalctl -p warning`)
- Falls back to `/var/log/syslog` if `journalctl` is unavailable

### 12. Log Collection
- Copies all files from the configured service log directories into the archive
- Also exports the last 2,000 lines of the full system journal to `logs/journal_full.txt`

---

## Adding More Log Directories

Open the script and find the `LOG_DIRS` array near the top:

```bash
LOG_DIRS=(
    "/home/Director/RadianseServices/logs"
    "/home/Director/UpdateService/logs"
    # "/home/Director/AnotherService/logs"   # <-- add more paths here
)
```

Add a new quoted path on its own line. Missing directories are skipped gracefully and noted in the report.

---

## Archive Contents

```
radianse_diag_<hostname>_<timestamp>/
├── report.txt                  # Full diagnostic report (all sections above)
└── logs/
    ├── home_Director_RadianseServices_logs/   # Copied service logs
    ├── home_Director_UpdateService_logs/      # Copied service logs
    └── journal_full.txt                       # Last 2000 system journal entries
```

---

## Dependencies

| Tool | Required | Notes |
|------|----------|-------|
| `bash` | Yes | Script interpreter |
| `vcgencmd` | Recommended | CPU throttle + temperature checks. Present by default on Raspberry Pi OS. |
| `sysbench` | Optional | CPU and memory benchmarks. `sudo apt install sysbench` |
| `bc` | Optional | Fallback CPU benchmark if sysbench is absent |
| `journalctl` | Optional | Falls back to `/var/log/syslog` |
| `xrandr` | Optional | Display info only |
| `nslookup` / `dig` | Optional | DNS test only |

All checks involving optional tools are skipped gracefully if the tool is not present.

---

## Interpreting Results — Common Causes of Slowness

| Symptom in Report | Likely Cause |
|-------------------|-------------|
| `vcgencmd get_throttled` bits 0–3 set | Active under-voltage or thermal throttling — check PSU and cooling |
| Bits 16–19 set (but not 0–3) | Throttling occurred since last boot — may be intermittent |
| Temperature > 70°C at idle | Poor airflow or missing heatsink |
| dd write speed < 5 MB/s | Degraded or low-quality SD card |
| dmesg contains `mmcblk` I/O errors | Failing SD card — replace immediately |
| `/proc/mounts` shows `ro` on rootfs | Filesystem error recovery — SD card likely corrupted |
| Load average > core count | CPU-bound process hogging resources — check top consumers |
| Chromium processes with `--disable-gpu` | GPU acceleration may be disabled, causing CPU-rendered display |

---

## Notes

- The script does **not** modify any system settings or files outside of `/tmp` (temporary dd test file, removed after use).
- It is safe to run on a live, in-service kiosk, though the disk benchmark will cause brief I/O load.
- For a Pi with a completely unresponsive display, the script can be run headlessly over SSH.