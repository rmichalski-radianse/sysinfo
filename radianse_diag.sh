#!/usr/bin/env bash
# =============================================================================
#  Radianse Kiosk Diagnostic Script
#  Collects system health data and logs for RMA/troubleshooting analysis.
# =============================================================================

set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# CONFIGURATION — Add or remove log directories here as needed
# ──────────────────────────────────────────────────────────────────────────────
LOG_DIRS=(
    "/home/Director/RadianseServices/logs"
    "/home/Director/UpdateService/logs"
    # "/home/Director/AnotherService/logs"   # <-- add more paths here
)

# ──────────────────────────────────────────────────────────────────────────────
# SETUP
# ──────────────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
HOSTNAME_LABEL="$(hostname -s)"
WORK_DIR="${SCRIPT_DIR}/radianse_diag_${HOSTNAME_LABEL}_${TIMESTAMP}"
REPORT_FILE="${WORK_DIR}/report.txt"
ARCHIVE_NAME="${SCRIPT_DIR}/radianse_diag_${HOSTNAME_LABEL}_${TIMESTAMP}.tar.gz"

mkdir -p "${WORK_DIR}/logs"

# ──────────────────────────────────────────────────────────────────────────────
# HELPERS
# ──────────────────────────────────────────────────────────────────────────────
SEP="============================================================"
section() { echo -e "\n${SEP}\n  $1\n${SEP}" | tee -a "${REPORT_FILE}"; }
log()     { echo "$1" | tee -a "${REPORT_FILE}"; }
logcmd()  { echo "$ $1" >> "${REPORT_FILE}"; eval "$1" 2>&1 | tee -a "${REPORT_FILE}" || true; }

# ──────────────────────────────────────────────────────────────────────────────
# BANNER
# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "  ██████╗  █████╗ ██████╗ ██╗ █████╗ ███╗   ██╗███████╗███████╗"
echo "  ██╔══██╗██╔══██╗██╔══██╗██║██╔══██╗████╗  ██║██╔════╝██╔════╝"
echo "  ██████╔╝███████║██║  ██║██║███████║██╔██╗ ██║███████╗█████╗  "
echo "  ██╔══██╗██╔══██║██║  ██║██║██╔══██║██║╚██╗██║╚════██║██╔══╝  "
echo "  ██║  ██║██║  ██║██████╔╝██║██║  ██║██║ ╚████║███████║███████╗"
echo "  ╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚══════╝╚══════╝"
echo ""
echo "  Kiosk Diagnostic Tool"
echo "  Host: ${HOSTNAME_LABEL}  |  Started: $(date)"
echo "  Output: ${ARCHIVE_NAME}"
echo ""

{
  echo "Radianse Kiosk Diagnostic Report"
  echo "Host     : ${HOSTNAME_LABEL}"
  echo "Date/Time: $(date)"
  echo "Script   : ${BASH_SOURCE[0]}"
} >> "${REPORT_FILE}"

# ══════════════════════════════════════════════════════════════════════════════
# 1. SYSTEM OVERVIEW
# ══════════════════════════════════════════════════════════════════════════════
section "1. SYSTEM OVERVIEW"
logcmd "uname -a"
logcmd "cat /etc/os-release"

# Raspberry Pi model/revision
if [[ -f /proc/device-tree/model ]]; then
    log ""
    log "Pi Model   : $(tr -d '\0' < /proc/device-tree/model)"
fi
if [[ -f /proc/cpuinfo ]]; then
    SERIAL=$(grep -i "serial" /proc/cpuinfo | tail -1 | awk '{print $3}')
    REVISION=$(grep -i "revision" /proc/cpuinfo | tail -1 | awk '{print $3}')
    log "Serial     : ${SERIAL}"
    log "Revision   : ${REVISION}"
fi
logcmd "uptime"

# ══════════════════════════════════════════════════════════════════════════════
# 2. CPU
# ══════════════════════════════════════════════════════════════════════════════
section "2. CPU"
logcmd "lscpu"

log ""
log "--- Current CPU frequencies ---"
if ls /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq &>/dev/null; then
    for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq; do
        CPU=$(echo "$f" | grep -oP 'cpu\d+')
        FREQ=$(cat "$f")
        log "  ${CPU}: $((FREQ / 1000)) MHz"
    done
fi

log ""
log "--- CPU governor ---"
if ls /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor &>/dev/null; then
    cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor >> "${REPORT_FILE}" || true
fi

log ""
log "--- Throttling / under-voltage flags ---"
if command -v vcgencmd &>/dev/null; then
    logcmd "vcgencmd get_throttled"
    THROTTLE_HEX=$(vcgencmd get_throttled 2>/dev/null | grep -oP '0x[0-9a-fA-F]+' || echo "0x0")
    THROTTLE_INT=$((THROTTLE_HEX))
    log ""
    log "Throttle flag interpretation (bit decode of ${THROTTLE_HEX}):"
    [[ $((THROTTLE_INT & 0x1))    -ne 0 ]] && log "  [!] BIT 0  — Currently under-voltage"
    [[ $((THROTTLE_INT & 0x2))    -ne 0 ]] && log "  [!] BIT 1  — Currently ARM frequency capped"
    [[ $((THROTTLE_INT & 0x4))    -ne 0 ]] && log "  [!] BIT 2  — Currently throttled"
    [[ $((THROTTLE_INT & 0x8))    -ne 0 ]] && log "  [!] BIT 3  — Currently soft temperature limit active"
    [[ $((THROTTLE_INT & 0x10000)) -ne 0 ]] && log "  [~] BIT 16 — Under-voltage has occurred since last reboot"
    [[ $((THROTTLE_INT & 0x20000)) -ne 0 ]] && log "  [~] BIT 17 — Frequency capping has occurred since last reboot"
    [[ $((THROTTLE_INT & 0x40000)) -ne 0 ]] && log "  [~] BIT 18 — Throttling has occurred since last reboot"
    [[ $((THROTTLE_INT & 0x80000)) -ne 0 ]] && log "  [~] BIT 19 — Soft temperature limit has occurred since last reboot"
    [[ $((THROTTLE_INT & 0xF000F)) -eq 0 ]] && log "  [OK] No active throttling or past throttling events."
fi

# ── CPU benchmark (single and multi core) ──────────────────────────────────
section "2b. CPU BENCHMARK (sysbench)"
if command -v sysbench &>/dev/null; then
    log "--- Single-core prime number test (10,000 primes) ---"
    logcmd "sysbench cpu --cpu-max-prime=10000 --threads=1 run"
    CORES=$(nproc)
    log ""
    log "--- Multi-core prime number test (${CORES} threads) ---"
    logcmd "sysbench cpu --cpu-max-prime=10000 --threads=${CORES} run"
else
    log "[SKIP] sysbench not installed.  Install with: sudo apt install sysbench"
    log "Falling back to built-in timing test..."
    log ""
    log "--- Pi digits computation timing (bc) ---"
    if command -v bc &>/dev/null; then
        TIME_START=$(date +%s%3N)
        echo "scale=2000; 4*a(1)" | bc -l &>/dev/null || true
        TIME_END=$(date +%s%3N)
        log "  2000 digits of π computed in $((TIME_END - TIME_START)) ms"
    fi
fi

# ══════════════════════════════════════════════════════════════════════════════
# 3. TEMPERATURE
# ══════════════════════════════════════════════════════════════════════════════
section "3. TEMPERATURE"
if command -v vcgencmd &>/dev/null; then
    TEMP_RAW=$(vcgencmd measure_temp 2>/dev/null)
    log "GPU/SoC Temperature : ${TEMP_RAW}"
    TEMP_VAL=$(echo "${TEMP_RAW}" | grep -oP '\d+\.\d+')
    if (( $(echo "$TEMP_VAL > 80" | bc -l 2>/dev/null || echo 0) )); then
        log "  [!!] WARNING: Temperature is critically high (>80°C)"
    elif (( $(echo "$TEMP_VAL > 70" | bc -l 2>/dev/null || echo 0) )); then
        log "  [!]  CAUTION: Temperature is elevated (>70°C)"
    else
        log "  [OK] Temperature is within normal range"
    fi
fi

if [[ -d /sys/class/thermal ]]; then
    log ""
    log "--- Thermal zones ---"
    for zone in /sys/class/thermal/thermal_zone*; do
        TYPE=$(cat "${zone}/type" 2>/dev/null || echo "unknown")
        TEMP=$(cat "${zone}/temp" 2>/dev/null || echo "N/A")
        [[ "$TEMP" != "N/A" ]] && TEMP_C=$(echo "scale=1; $TEMP/1000" | bc -l 2>/dev/null || echo "$TEMP") || TEMP_C="N/A"
        log "  ${TYPE}: ${TEMP_C}°C"
    done
fi

# ══════════════════════════════════════════════════════════════════════════════
# 4. MEMORY
# ══════════════════════════════════════════════════════════════════════════════
section "4. MEMORY"
logcmd "free -h"
log ""
logcmd "cat /proc/meminfo"

# Memory speed benchmark
section "4b. MEMORY BENCHMARK (sysbench)"
if command -v sysbench &>/dev/null; then
    logcmd "sysbench memory --memory-total-size=512M run"
else
    log "[SKIP] sysbench not installed — skipping memory benchmark"
fi

# ══════════════════════════════════════════════════════════════════════════════
# 5. STORAGE / SD CARD
# ══════════════════════════════════════════════════════════════════════════════
section "5. STORAGE & DISK HEALTH"
logcmd "df -h"
log ""
logcmd "lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE,MODEL"

log ""
log "--- Disk I/O benchmark (dd write + read) ---"
TMP_TESTFILE="/tmp/diag_dd_test_$$"

# Write test
log "  Write test (64MB, bs=4K):"
DD_WRITE=$(dd if=/dev/zero of="${TMP_TESTFILE}" bs=4k count=16384 conv=fsync 2>&1 | tail -1)
log "    ${DD_WRITE}"

# Flush caches then read test
sync
echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
log "  Read test (64MB, bs=4K):"
DD_READ=$(dd if="${TMP_TESTFILE}" of=/dev/null bs=4k 2>&1 | tail -1)
log "    ${DD_READ}"
rm -f "${TMP_TESTFILE}"

# SD card bad blocks check (quick, non-destructive)
log ""
log "--- Filesystem error check (dmesg | grep for I/O / MMC errors) ---"
dmesg 2>/dev/null | grep -iE "(error|mmc|mmcblk|i/o error|bad sector|corruption|ext4-fs)" \
    | tail -40 >> "${REPORT_FILE}" 2>&1 || log "  (no relevant dmesg entries, or dmesg requires root)"

log ""
log "--- Mount options (check for remount-ro indicating FS errors) ---"
cat /proc/mounts >> "${REPORT_FILE}" 2>&1 || true

# ══════════════════════════════════════════════════════════════════════════════
# 6. PROCESSES & TOP CONSUMERS
# ══════════════════════════════════════════════════════════════════════════════
section "6. PROCESSES"
log "--- Top 20 CPU consumers ---"
ps aux --sort=-%cpu | head -21 | tee -a "${REPORT_FILE}"

log ""
log "--- Top 20 memory consumers ---"
ps aux --sort=-%mem | head -21 | tee -a "${REPORT_FILE}"

log ""
log "--- Total process count ---"
logcmd "ps aux | wc -l"

log ""
log "--- Zombie processes ---"
ZOMBIES=$(ps aux | awk '{print $8}' | grep -c "^Z$" || true)
log "  Zombie count: ${ZOMBIES}"

# ══════════════════════════════════════════════════════════════════════════════
# 7. SYSTEM LOAD & UPTIME
# ══════════════════════════════════════════════════════════════════════════════
section "7. LOAD AVERAGE & UPTIME"
logcmd "uptime"
logcmd "cat /proc/loadavg"
CORES=$(nproc)
LOAD1=$(awk '{print $1}' /proc/loadavg)
log ""
log "  CPU cores: ${CORES}"
log "  Note: Load avg > ${CORES} means the system is overloaded"
if (( $(echo "$LOAD1 > $CORES" | bc -l 2>/dev/null || echo 0) )); then
    log "  [!] WARNING: Load average (${LOAD1}) exceeds core count (${CORES})"
fi

# ══════════════════════════════════════════════════════════════════════════════
# 8. NETWORK
# ══════════════════════════════════════════════════════════════════════════════
section "8. NETWORK"
logcmd "ip addr show"
log ""
logcmd "ip route show"
log ""

log "--- Network interface stats ---"
logcmd "cat /proc/net/dev"

log ""
log "--- Network errors / drops (non-zero values indicate problems) ---"
ip -s link 2>/dev/null | tee -a "${REPORT_FILE}" || true

log ""
log "--- DNS resolution test ---"
if command -v nslookup &>/dev/null; then
    logcmd "nslookup google.com" || log "  [!] DNS resolution failed"
elif command -v dig &>/dev/null; then
    logcmd "dig +short google.com" || log "  [!] DNS resolution failed"
fi

log ""
log "--- Basic connectivity test ---"
if ping -c 3 -W 2 8.8.8.8 &>/dev/null; then
    log "  [OK] Internet connectivity confirmed (8.8.8.8)"
else
    log "  [!] No response from 8.8.8.8 — network may be down"
fi

# ══════════════════════════════════════════════════════════════════════════════
# 9. CHROMIUM / DISPLAY
# ══════════════════════════════════════════════════════════════════════════════
section "9. CHROMIUM & DISPLAY"
log "--- Chromium processes ---"
pgrep -a chromium 2>/dev/null | tee -a "${REPORT_FILE}" || log "  (no chromium processes running)"

log ""
log "--- Display environment ---"
logcmd "echo \$DISPLAY" || true
logcmd "xrandr 2>/dev/null" || log "  (xrandr unavailable or no display)"

log ""
log "--- GPU memory split (vcgencmd) ---"
if command -v vcgencmd &>/dev/null; then
    logcmd "vcgencmd get_mem arm"
    logcmd "vcgencmd get_mem gpu"
fi

# ══════════════════════════════════════════════════════════════════════════════
# 10. SYSTEMD SERVICES
# ══════════════════════════════════════════════════════════════════════════════
section "10. SYSTEMD SERVICES"
log "--- Failed units ---"
systemctl --failed --no-pager 2>/dev/null | tee -a "${REPORT_FILE}" || log "  (systemctl unavailable)"

log ""
log "--- All service states (active/inactive/failed) ---"
systemctl list-units --type=service --no-pager 2>/dev/null | tee -a "${REPORT_FILE}" || true

# ══════════════════════════════════════════════════════════════════════════════
# 11. SYSTEM JOURNAL / SYSLOG ERRORS
# ══════════════════════════════════════════════════════════════════════════════
section "11. JOURNAL ERRORS (last 200 lines, warnings and above)"
journalctl -p warning --no-pager -n 200 2>/dev/null | tee -a "${REPORT_FILE}" \
    || tail -200 /var/log/syslog 2>/dev/null | tee -a "${REPORT_FILE}" \
    || log "  (journal/syslog unavailable)"

# ══════════════════════════════════════════════════════════════════════════════
# 12. LOG COLLECTION
# ══════════════════════════════════════════════════════════════════════════════
section "12. COLLECTING SERVICE LOGS"

LOGS_COLLECTED=0
LOGS_MISSING=()

for DIR in "${LOG_DIRS[@]}"; do
    if [[ -d "${DIR}" ]]; then
        log "  [+] Found: ${DIR}"
        DEST="${WORK_DIR}/logs/$(echo "${DIR}" | sed 's|/|_|g' | sed 's|^_||')"
        mkdir -p "${DEST}"
        cp -r "${DIR}/." "${DEST}/" 2>/dev/null || true
        COUNT=$(find "${DEST}" -type f | wc -l)
        log "      → Copied ${COUNT} file(s)"
        LOGS_COLLECTED=$((LOGS_COLLECTED + COUNT))
    else
        log "  [-] Missing (skipped): ${DIR}"
        LOGS_MISSING+=("${DIR}")
    fi
done

log ""
log "  Total log files collected: ${LOGS_COLLECTED}"
[[ ${#LOGS_MISSING[@]} -gt 0 ]] && log "  Missing directories: ${LOGS_MISSING[*]}"

# Also grab journalctl service-specific logs if available
log ""
log "  Saving full journal to logs/journal_full.txt ..."
journalctl --no-pager -n 2000 > "${WORK_DIR}/logs/journal_full.txt" 2>/dev/null \
    || log "  (journal export unavailable)"

# ══════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ══════════════════════════════════════════════════════════════════════════════
section "DIAGNOSTIC SUMMARY"
TEMP_FINAL=""
THROTTLE_FINAL=""
command -v vcgencmd &>/dev/null && TEMP_FINAL=$(vcgencmd measure_temp 2>/dev/null) || true
command -v vcgencmd &>/dev/null && THROTTLE_FINAL=$(vcgencmd get_throttled 2>/dev/null) || true

log "Host         : ${HOSTNAME_LABEL}"
log "Date/Time    : $(date)"
log "Temperature  : ${TEMP_FINAL:-N/A}"
log "Throttle     : ${THROTTLE_FINAL:-N/A}"
log "Load avg     : $(cat /proc/loadavg)"
log "Memory free  : $(free -h | awk '/^Mem:/{print $4}')"
log "Disk free /  : $(df -h / | awk 'NR==2{print $4}')"
log ""
log "Archive will be saved to:"
log "  ${ARCHIVE_NAME}"

# ══════════════════════════════════════════════════════════════════════════════
# PACKAGE INTO ARCHIVE
# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo "Packaging results..."
tar -czf "${ARCHIVE_NAME}" -C "${SCRIPT_DIR}" "$(basename "${WORK_DIR}")"
rm -rf "${WORK_DIR}"

echo ""
echo "  ✓ Done! Archive saved to:"
echo "    ${ARCHIVE_NAME}"
echo ""
echo "  Contents:"
tar -tzf "${ARCHIVE_NAME}" | head -40
echo ""
