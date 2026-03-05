#!/usr/bin/env bash
# =============================================================================
#  Radianse Kiosk Diagnostic Tool
#  Raspberry Pi health analysis for kiosk troubleshooting and RMA evaluation.
# =============================================================================

set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# CONFIGURATION
# ──────────────────────────────────────────────────────────────────────────────

# Directories whose logs are bundled in the Full Diagnostic (Option 1) archive.
FULL_DIAG_LOG_DIRS=(
    "/home/Director/RadianseServices/logs"
    "/home/Director/UpdateService/logs"
    # "/home/Director/AnotherService/logs"   # <-- add more here
)

# Directories collected by the Log Collection tool (Option 4).
# Can overlap with the above — add any extra paths you want here too.
LOG_COLLECTION_DIRS=(
    "/home/Director/RadianseServices/logs"
    "/home/Director/UpdateService/logs"
    # "/home/Director/AnotherService/logs"   # <-- add more here
    # "/var/log/radianse"                    # <-- example: system-level log dir
    # "/home/Director/SomeOtherService/logs" # <-- add as many as needed
)

# ──────────────────────────────────────────────────────────────────────────────
# GLOBALS
# ──────────────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
HOSTNAME_LABEL="$(hostname -s)"

# ──────────────────────────────────────────────────────────────────────────────
# COLORS
# ──────────────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'

# ──────────────────────────────────────────────────────────────────────────────
# SHARED HELPERS
# ──────────────────────────────────────────────────────────────────────────────
SEP="──────────────────────────────────────────────────────────"

print_banner() {
    clear
    echo -e "${CYAN}"
    echo "  ██████╗  █████╗ ██████╗ ██╗ █████╗ ███╗   ██╗███████╗███████╗"
    echo "  ██╔══██╗██╔══██╗██╔══██╗██║██╔══██╗████╗  ██║██╔════╝██╔════╝"
    echo "  ██████╔╝███████║██║  ██║██║███████║██╔██╗ ██║███████╗█████╗  "
    echo "  ██╔══██╗██╔══██║██║  ██║██║██╔══██║██║╚██╗██║╚════██║██╔══╝  "
    echo "  ██║  ██║██║  ██║██████╔╝██║██║  ██║██║ ╚████║███████║███████╗"
    echo "  ╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚══════╝╚══════╝"
    echo -e "${RESET}"
    echo -e "  ${BOLD}Kiosk Diagnostic Tool${RESET}  ${DIM}|  Host: ${HOSTNAME_LABEL}  |  $(date)${RESET}"
    echo ""
}

section()      { echo -e "\n${BOLD}${CYAN}${SEP}${RESET}"; echo -e "  ${BOLD}$1${RESET}"; echo -e "${CYAN}${SEP}${RESET}"; }
ok()           { echo -e "  ${GREEN}[OK]${RESET}  $1"; }
warn()         { echo -e "  ${YELLOW}[!!]${RESET}  $1"; }
err()          { echo -e "  ${RED}[!!]${RESET}  $1"; }
info()         { echo -e "  ${DIM}      $1${RESET}"; }
kv()           { printf "  ${BOLD}%-28s${RESET} %s\n" "$1" "$2"; }
press_enter()  { echo ""; echo -e "  ${DIM}Press Enter to return to the menu...${RESET}"; read -r; }

# ══════════════════════════════════════════════════════════════════════════════
#  OPTION 1 — FULL DIAGNOSTIC  [produces .tar.gz]
# ══════════════════════════════════════════════════════════════════════════════
run_full_diagnostic() {
    WORK_DIR="${SCRIPT_DIR}/radianse_diag_${HOSTNAME_LABEL}_${TIMESTAMP}"
    REPORT_FILE="${WORK_DIR}/report.txt"
    ARCHIVE_NAME="${SCRIPT_DIR}/radianse_diag_${HOSTNAME_LABEL}_${TIMESTAMP}.tar.gz"
    mkdir -p "${WORK_DIR}"

    rlog()   { echo "$1" | tee -a "${REPORT_FILE}"; }
    hdr()    { echo -e "\n============================================================\n  $1\n============================================================" | tee -a "${REPORT_FILE}"; }
    logcmd() { echo "$ $1" >> "${REPORT_FILE}"; eval "$1" 2>&1 | tee -a "${REPORT_FILE}" || true; }

    print_banner
    echo -e "  ${BOLD}Running full diagnostic...${RESET}"
    echo -e "  ${DIM}Output: ${ARCHIVE_NAME}${RESET}"
    echo ""

    { echo "Radianse Kiosk Diagnostic Report"; echo "Host: ${HOSTNAME_LABEL}"; echo "Date: $(date)"; } >> "${REPORT_FILE}"

    hdr "1. SYSTEM OVERVIEW"
    logcmd "uname -a"; logcmd "cat /etc/os-release"
    [[ -f /proc/device-tree/model ]] && rlog "Pi Model   : $(tr -d '\0' < /proc/device-tree/model)"
    SERIAL=$(grep -i "serial"   /proc/cpuinfo | tail -1 | awk '{print $3}' 2>/dev/null || echo "N/A")
    REVISION=$(grep -i "revision" /proc/cpuinfo | tail -1 | awk '{print $3}' 2>/dev/null || echo "N/A")
    rlog "Serial     : ${SERIAL}"; rlog "Revision   : ${REVISION}"
    logcmd "uptime"

    hdr "2. CPU"
    logcmd "lscpu"
    rlog ""; rlog "--- Current CPU frequencies ---"
    for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq; do
        CPU=$(echo "$f" | grep -oP 'cpu\d+'); FREQ=$(cat "$f")
        rlog "  ${CPU}: $((FREQ / 1000)) MHz"
    done 2>/dev/null || true
    rlog ""; rlog "--- CPU governor ---"
    cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor >> "${REPORT_FILE}" 2>/dev/null || true
    rlog ""; rlog "--- Throttle flags ---"
    if command -v vcgencmd &>/dev/null; then
        logcmd "vcgencmd get_throttled"
        THROTTLE_HEX=$(vcgencmd get_throttled 2>/dev/null | grep -oP '0x[0-9a-fA-F]+' || echo "0x0")
        T=$((THROTTLE_HEX))
        [[ $((T & 0x1))     -ne 0 ]] && rlog "  [!] BIT 0  — Currently under-voltage"
        [[ $((T & 0x2))     -ne 0 ]] && rlog "  [!] BIT 1  — Currently ARM frequency capped"
        [[ $((T & 0x4))     -ne 0 ]] && rlog "  [!] BIT 2  — Currently throttled"
        [[ $((T & 0x8))     -ne 0 ]] && rlog "  [!] BIT 3  — Soft temp limit active"
        [[ $((T & 0x10000)) -ne 0 ]] && rlog "  [~] BIT 16 — Under-voltage occurred since boot"
        [[ $((T & 0x20000)) -ne 0 ]] && rlog "  [~] BIT 17 — Freq cap occurred since boot"
        [[ $((T & 0x40000)) -ne 0 ]] && rlog "  [~] BIT 18 — Throttling occurred since boot"
        [[ $((T & 0x80000)) -ne 0 ]] && rlog "  [~] BIT 19 — Soft temp limit occurred since boot"
        [[ $((T & 0xF000F)) -eq 0 ]] && rlog "  [OK] No throttling events."
    fi

    hdr "2b. CPU BENCHMARK"
    if command -v sysbench &>/dev/null; then
        logcmd "sysbench cpu --cpu-max-prime=10000 --threads=1 run"
        logcmd "sysbench cpu --cpu-max-prime=10000 --threads=$(nproc) run"
    else
        rlog "[SKIP] sysbench not installed (sudo apt install sysbench)"
        if command -v bc &>/dev/null; then
            TS=$(date +%s%3N); echo "scale=2000; 4*a(1)" | bc -l &>/dev/null || true; TE=$(date +%s%3N)
            rlog "  Fallback: 2000 digits of pi in $((TE - TS)) ms"
        fi
    fi

    hdr "3. TEMPERATURE"
    if command -v vcgencmd &>/dev/null; then
        T_RAW=$(vcgencmd measure_temp 2>/dev/null); rlog "SoC Temp: ${T_RAW}"
        T_VAL=$(echo "${T_RAW}" | grep -oP '\d+\.\d+')
        (( $(echo "$T_VAL > 80" | bc -l 2>/dev/null || echo 0) )) && rlog "  [!!] CRITICAL: >80C"
        (( $(echo "$T_VAL > 70" | bc -l 2>/dev/null || echo 0) )) && rlog "  [!]  CAUTION: >70C"
    fi
    for zone in /sys/class/thermal/thermal_zone*; do
        TYPE=$(cat "${zone}/type" 2>/dev/null || echo "unknown")
        RAW=$(cat "${zone}/temp" 2>/dev/null || echo "N/A")
        [[ "$RAW" != "N/A" ]] && C=$(echo "scale=1; $RAW/1000" | bc -l 2>/dev/null || echo "$RAW") || C="N/A"
        rlog "  ${TYPE}: ${C}C"
    done 2>/dev/null || true

    hdr "4. MEMORY"
    logcmd "free -h"; rlog ""; logcmd "cat /proc/meminfo"
    hdr "4b. MEMORY BENCHMARK"
    if command -v sysbench &>/dev/null; then logcmd "sysbench memory --memory-total-size=512M run"
    else rlog "[SKIP] sysbench not installed"; fi

    hdr "5. STORAGE & DISK HEALTH"
    logcmd "df -h"; rlog ""; logcmd "lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE,MODEL"
    rlog ""; rlog "--- dd benchmark ---"
    TMP_T="/tmp/diag_dd_$$"
    DD_W=$(dd if=/dev/zero of="${TMP_T}" bs=4k count=16384 conv=fsync 2>&1 | tail -1)
    rlog "  Write (64MB): ${DD_W}"
    sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
    DD_R=$(dd if="${TMP_T}" of=/dev/null bs=4k 2>&1 | tail -1)
    rlog "  Read  (64MB): ${DD_R}"
    rm -f "${TMP_T}"
    rlog ""; rlog "--- dmesg I/O / MMC errors ---"
    dmesg 2>/dev/null | grep -iE "(error|mmc|mmcblk|i/o error|bad sector|corruption|ext4-fs)" | tail -40 >> "${REPORT_FILE}" 2>&1 || true
    rlog ""; rlog "--- Mount options ---"
    cat /proc/mounts >> "${REPORT_FILE}" 2>&1 || true

    hdr "6. PROCESSES"
    ps aux --sort=-%cpu | head -21 | tee -a "${REPORT_FILE}"
    rlog ""; ps aux --sort=-%mem | head -21 | tee -a "${REPORT_FILE}"
    ZOMBIES=$(ps aux | awk '{print $8}' | grep -c "^Z$" || true)
    rlog "Zombie count: ${ZOMBIES}"

    hdr "7. LOAD AVERAGE"
    logcmd "uptime"; logcmd "cat /proc/loadavg"
    CORES=$(nproc); LOAD1=$(awk '{print $1}' /proc/loadavg)
    (( $(echo "$LOAD1 > $CORES" | bc -l 2>/dev/null || echo 0) )) && rlog "  [!] Load (${LOAD1}) exceeds core count (${CORES})"

    hdr "8. NETWORK"
    logcmd "ip addr show"; rlog ""; logcmd "ip route show"
    logcmd "cat /proc/net/dev"; ip -s link >> "${REPORT_FILE}" 2>/dev/null || true
    command -v nslookup &>/dev/null && logcmd "nslookup google.com" || true
    ping -c 3 -W 2 8.8.8.8 &>/dev/null && rlog "  [OK] Connectivity to 8.8.8.8" || rlog "  [!] No response from 8.8.8.8"

    hdr "9. CHROMIUM & DISPLAY"
    pgrep -a chromium >> "${REPORT_FILE}" 2>/dev/null || rlog "  (no chromium processes)"
    xrandr >> "${REPORT_FILE}" 2>/dev/null || rlog "  (xrandr unavailable)"
    if command -v vcgencmd &>/dev/null; then logcmd "vcgencmd get_mem arm"; logcmd "vcgencmd get_mem gpu"; fi

    hdr "10. SYSTEMD SERVICES"
    systemctl --failed --no-pager >> "${REPORT_FILE}" 2>/dev/null || true
    systemctl list-units --type=service --no-pager >> "${REPORT_FILE}" 2>/dev/null || true

    hdr "11. JOURNAL ERRORS"
    journalctl -p warning --no-pager -n 200 >> "${REPORT_FILE}" 2>/dev/null \
        || tail -200 /var/log/syslog >> "${REPORT_FILE}" 2>/dev/null || true

    hdr "12. SERIAL / USB DEVICES"
    logcmd "ls -la /dev/ttyUSB* /dev/ttyACM* 2>/dev/null || echo '  (none found)'"
    rlog ""; logcmd "lsusb"

    hdr "13. COLLECTING SERVICE LOGS"
    LOGS_COLLECTED=0
    for DIR in "${FULL_DIAG_LOG_DIRS[@]}"; do
        if [[ -d "${DIR}" ]]; then
            rlog "  [+] Copying: ${DIR}"
            DEST="${WORK_DIR}/logs/$(echo "${DIR}" | sed 's|^/||; s|/|_|g')"
            mkdir -p "${DEST}"
            cp -r "${DIR}/." "${DEST}/" 2>/dev/null || true
            COUNT=$(find "${DEST}" -type f | wc -l)
            rlog "      -> ${COUNT} file(s) copied"
            LOGS_COLLECTED=$((LOGS_COLLECTED + COUNT))
        else
            rlog "  [-] Not found (skipped): ${DIR}"
        fi
    done
    rlog "  Total log files collected: ${LOGS_COLLECTED}"
    journalctl --no-pager -n 2000 > "${WORK_DIR}/logs/journal_full.txt" 2>/dev/null || true

    hdr "SUMMARY"
    rlog "Host       : ${HOSTNAME_LABEL}"
    rlog "Date       : $(date)"
    command -v vcgencmd &>/dev/null && rlog "Temp       : $(vcgencmd measure_temp 2>/dev/null)" || true
    command -v vcgencmd &>/dev/null && rlog "Throttle   : $(vcgencmd get_throttled 2>/dev/null)" || true
    rlog "Load avg   : $(cat /proc/loadavg)"
    rlog "Mem free   : $(free -h | awk '/^Mem:/{print $4}')"
    rlog "Disk free  : $(df -h / | awk 'NR==2{print $4}')"

    echo ""; echo -e "  ${DIM}Packaging archive...${RESET}"
    tar -czf "${ARCHIVE_NAME}" -C "${SCRIPT_DIR}" "$(basename "${WORK_DIR}")"
    rm -rf "${WORK_DIR}"
    echo -e "  ${GREEN}${BOLD}Done! Archive saved:${RESET}"
    echo -e "    ${ARCHIVE_NAME}"
    echo ""; tar -tzf "${ARCHIVE_NAME}" | head -50
    press_enter
}

# ══════════════════════════════════════════════════════════════════════════════
#  OPTION 2 — QUICK SNAPSHOT  [terminal output only, no file saved]
# ══════════════════════════════════════════════════════════════════════════════
run_brief_snapshot() {
    print_banner
    echo -e "  ${BOLD}Quick System Snapshot${RESET}  ${DIM}— $(date)${RESET}"
    echo -e "  ${DIM}Live readout only — no file is saved.${RESET}"
    echo ""

    section "UPTIME & LOAD"
    UPTIME_STR=$(uptime -p 2>/dev/null || uptime)
    LOAD=$(awk '{print $1, $2, $3}' /proc/loadavg)
    CORES=$(nproc)
    LOAD1=$(awk '{print $1}' /proc/loadavg)
    kv "Uptime:" "${UPTIME_STR}"
    kv "Load avg (1/5/15m):" "${LOAD}  (${CORES} cores)"
    if (( $(echo "$LOAD1 > $CORES" | bc -l 2>/dev/null || echo 0) )); then
        warn "Load average exceeds core count — system is overloaded"
    else
        ok "Load is within normal range"
    fi

    section "TEMPERATURE"
    if command -v vcgencmd &>/dev/null; then
        T_RAW=$(vcgencmd measure_temp 2>/dev/null)
        T_VAL=$(echo "${T_RAW}" | grep -oP '\d+\.\d+')
        kv "SoC Temperature:" "${T_RAW}"
        if   (( $(echo "$T_VAL > 80" | bc -l 2>/dev/null || echo 0) )); then err  "CRITICAL — above 80C"
        elif (( $(echo "$T_VAL > 70" | bc -l 2>/dev/null || echo 0) )); then warn "Elevated — above 70C"
        else ok "Temperature normal"; fi
    else info "(vcgencmd not available)"; fi

    section "CPU THROTTLE STATUS"
    if command -v vcgencmd &>/dev/null; then
        THROTTLE_HEX=$(vcgencmd get_throttled 2>/dev/null | grep -oP '0x[0-9a-fA-F]+' || echo "0x0")
        T=$((THROTTLE_HEX))
        kv "Raw value:" "${THROTTLE_HEX}"
        ISSUES=0
        [[ $((T & 0x1))     -ne 0 ]] && { err  "Currently under-voltage";             ISSUES=1; }
        [[ $((T & 0x2))     -ne 0 ]] && { err  "Currently ARM freq capped";            ISSUES=1; }
        [[ $((T & 0x4))     -ne 0 ]] && { err  "Currently throttled";                  ISSUES=1; }
        [[ $((T & 0x8))     -ne 0 ]] && { warn "Soft temp limit active";               ISSUES=1; }
        [[ $((T & 0x10000)) -ne 0 ]] && { warn "Under-voltage occurred since boot";    ISSUES=1; }
        [[ $((T & 0x20000)) -ne 0 ]] && { warn "Freq cap occurred since boot";         ISSUES=1; }
        [[ $((T & 0x40000)) -ne 0 ]] && { warn "Throttling occurred since boot";       ISSUES=1; }
        [[ $((T & 0x80000)) -ne 0 ]] && { warn "Soft temp limit occurred since boot";  ISSUES=1; }
        [[ $ISSUES -eq 0 ]] && ok "No throttling or under-voltage events"
    else info "(vcgencmd not available)"; fi

    section "MEMORY"
    MEM_TOTAL=$(free -h | awk '/^Mem:/{print $2}')
    MEM_USED=$(free -h  | awk '/^Mem:/{print $3}')
    MEM_FREE=$(free -h  | awk '/^Mem:/{print $4}')
    MEM_AVAIL=$(free -h | awk '/^Mem:/{print $7}')
    MEM_PCT=$(free | awk '/^Mem:/{printf "%.0f", $3/$2*100}')
    SWAP_USED=$(free -h  | awk '/^Swap:/{print $3}')
    SWAP_TOTAL=$(free -h | awk '/^Swap:/{print $2}')
    kv "Total:"     "${MEM_TOTAL}"
    kv "Used:"      "${MEM_USED}  (${MEM_PCT}%)"
    kv "Free:"      "${MEM_FREE}"
    kv "Available:" "${MEM_AVAIL}"
    kv "Swap used:" "${SWAP_USED} / ${SWAP_TOTAL}"
    if   [[ "${MEM_PCT}" -ge 90 ]]; then err  "Memory usage critical (${MEM_PCT}%)"
    elif [[ "${MEM_PCT}" -ge 75 ]]; then warn "Memory usage elevated (${MEM_PCT}%)"
    else                                 ok   "Memory usage normal (${MEM_PCT}%)"; fi

    section "DISK USAGE"
    df -h --output=target,size,used,avail,pcent 2>/dev/null \
        | grep -v "^tmpfs\|^devtmpfs\|^udev\|^Filesystem" \
        | while IFS= read -r line; do
            MOUNT=$(echo "${line}" | awk '{print $1}')
            SIZE=$(echo  "${line}" | awk '{print $2}')
            USED=$(echo  "${line}" | awk '{print $3}')
            AVAIL=$(echo "${line}" | awk '{print $4}')
            PCT=$(echo   "${line}" | awk '{print $5}')
            PCT_NUM="${PCT/\%/}"
            printf "  ${BOLD}%-20s${RESET} %s used of %s  (%s free)  %s\n" \
                "${MOUNT}" "${USED}" "${SIZE}" "${AVAIL}" "${PCT}"
            if   [[ "${PCT_NUM}" -ge 90 ]]; then echo -e "  ${RED}        [!!] Disk almost full${RESET}"
            elif [[ "${PCT_NUM}" -ge 80 ]]; then echo -e "  ${YELLOW}        [!]  Disk usage high${RESET}"; fi
          done
    echo ""
    FS_FLAGS=$(grep " ro," /proc/mounts 2>/dev/null | grep -v "tmpfs\|proc\|sys\|devpts\|run" || true)
    if [[ -n "${FS_FLAGS}" ]]; then
        err "Filesystem remounted READ-ONLY — possible SD card failure:"
        echo "${FS_FLAGS}" | while IFS= read -r line; do info "${line}"; done
    else ok "No filesystems remounted read-only"; fi
    MMC_ERRORS=$(dmesg 2>/dev/null | grep -c -iE "mmcblk.*error|i/o error.*mmcblk" || true)
    if [[ "${MMC_ERRORS}" -gt 0 ]]; then
        err "${MMC_ERRORS} MMC/SD I/O error(s) in dmesg — run SD Card Test for details"
    else ok "No MMC I/O errors in dmesg"; fi

    section "CPU USAGE"
    CPU_IDLE=$(top -bn1 | grep "Cpu(s)" | awk '{print $8}' | tr -d '%id,' 2>/dev/null \
               || top -bn1 | grep "%Cpu" | awk '{print $8}' | tr -d '%,' 2>/dev/null \
               || echo "N/A")
    if [[ "${CPU_IDLE}" != "N/A" ]]; then
        CPU_USED=$(echo "100 - ${CPU_IDLE}" | bc -l 2>/dev/null | xargs printf "%.1f" || echo "N/A")
        kv "CPU in use:" "${CPU_USED}%"
    fi
    echo ""
    echo -e "  ${BOLD}Top 8 processes by CPU:${RESET}"
    ps aux --sort=-%cpu | awk 'NR>1 && NR<=9 {printf "  %-10s  %5s%%  %s\n", $1, $3, $11}' | head -8

    section "TOP MEMORY CONSUMERS"
    echo -e "  ${BOLD}Top 8 processes by memory:${RESET}"
    ps aux --sort=-%mem | awk 'NR>1 && NR<=9 {printf "  %-10s  %5s%%  %s\n", $1, $4, $11}' | head -8

    section "SERIAL & USB DEVICES"
    SERIAL_DEVS=$(ls /dev/ttyUSB* /dev/ttyACM* 2>/dev/null || true)
    if [[ -n "${SERIAL_DEVS}" ]]; then
        ok "Serial device(s) detected:"
        for DEV in ${SERIAL_DEVS}; do
            DEVNAME=$(basename "${DEV}")
            SYSPATH=$(find /sys/bus/usb-serial/devices/ -name "${DEVNAME}" 2>/dev/null | head -1 || true)
            MANUF="N/A"; PROD="N/A"
            if [[ -n "${SYSPATH}" ]]; then
                MANUF=$(cat "$(realpath "${SYSPATH}/../../../manufacturer" 2>/dev/null)" 2>/dev/null || echo "N/A")
                PROD=$(cat  "$(realpath "${SYSPATH}/../../../product"      2>/dev/null)" 2>/dev/null || echo "N/A")
            fi
            kv "  ${DEV}:" "${MANUF} — ${PROD}"
        done
    else info "No /dev/ttyUSB* or /dev/ttyACM* devices found"; fi
    echo ""
    echo -e "  ${BOLD}USB devices:${RESET}"
    lsusb 2>/dev/null | while IFS= read -r line; do echo "    ${line}"; done \
        || info "(lsusb unavailable)"

    section "FAILED SERVICES"
    FAILED=$(systemctl --failed --no-pager 2>/dev/null | grep "●" || true)
    if [[ -n "${FAILED}" ]]; then
        err "Failed systemd units:"
        echo "${FAILED}" | while IFS= read -r line; do echo "    ${line}"; done
    else ok "No failed systemd units"; fi

    press_enter
}

# ══════════════════════════════════════════════════════════════════════════════
#  OPTION 3 — SD CARD HEALTH TEST  [terminal output only, no file saved]
# ══════════════════════════════════════════════════════════════════════════════
run_sd_card_test() {
    print_banner
    echo -e "  ${BOLD}SD Card Health Test${RESET}"
    echo -e "  ${DIM}All tests are non-destructive unless you opt into the bad block scan.${RESET}"
    echo -e "  ${DIM}Live readout only — no file is saved.${RESET}"
    echo ""

    section "DEVICE IDENTIFICATION"
    MMC_DEV=""
    for d in /dev/mmcblk0 /dev/mmcblk1; do
        if [[ -b "${d}" ]]; then MMC_DEV="${d}"; break; fi
    done
    if [[ -z "${MMC_DEV}" ]]; then
        err "No MMC/SD block device found at /dev/mmcblk0 or /dev/mmcblk1"
        press_enter; return
    fi
    ok "SD card device: ${MMC_DEV}"
    DEV_BASE=$(basename "${MMC_DEV}")
    kv "Size:"         "$(lsblk -dno SIZE "${MMC_DEV}" 2>/dev/null || echo N/A)"
    kv "Name/Model:"   "$(cat /sys/block/${DEV_BASE}/device/name   2>/dev/null || echo N/A)"
    kv "Manufacturer:" "$(cat /sys/block/${DEV_BASE}/device/manfid 2>/dev/null || echo N/A)"
    kv "OEM ID:"       "$(cat /sys/block/${DEV_BASE}/device/oemid  2>/dev/null || echo N/A)"
    kv "Serial:"       "$(cat /sys/block/${DEV_BASE}/device/serial 2>/dev/null || echo N/A)"
    kv "Firmware rev:" "$(cat /sys/block/${DEV_BASE}/device/fwrev  2>/dev/null || echo N/A)"
    kv "Mfg date:"     "$(cat /sys/block/${DEV_BASE}/device/date   2>/dev/null || echo N/A)"
    echo ""
    echo -e "  ${BOLD}Partition layout:${RESET}"
    lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT "${MMC_DEV}" 2>/dev/null \
        | while IFS= read -r line; do echo "    ${line}"; done

    section "FILESYSTEM STATUS"
    RO_MOUNTS=$(grep " ro," /proc/mounts 2>/dev/null | grep -v "tmpfs\|proc\|sys\|devpts\|run" || true)
    if [[ -n "${RO_MOUNTS}" ]]; then
        err "One or more filesystems are mounted READ-ONLY:"
        echo "${RO_MOUNTS}" | while IFS= read -r line; do info "${line}"; done
        warn "This strongly indicates past filesystem corruption — consider replacing the SD card."
    else ok "All filesystems are mounted read-write"; fi

    section "KERNEL I/O ERROR HISTORY (dmesg)"
    MMC_ERRORS=$(dmesg 2>/dev/null \
        | grep -iE "mmcblk|mmc[0-9]|i/o error|blk_update_request|end_request|bad sector|filesystem error|ext4-fs error" \
        || true)
    if [[ -n "${MMC_ERRORS}" ]]; then
        err "SD/MMC related kernel messages found:"
        echo "${MMC_ERRORS}" | tail -30 | while IFS= read -r line; do info "${line}"; done
    else ok "No SD/MMC error messages in kernel log"; fi

    section "JOURNAL FILESYSTEM / I/O ERRORS"
    JOURNAL_ERRS=$(journalctl -p err --no-pager -n 100 2>/dev/null \
        | grep -iE "mmcblk|mmc[0-9]|i/o error|ext4|filesystem|bad block|corruption" || true)
    if [[ -n "${JOURNAL_ERRS}" ]]; then
        err "Filesystem/IO errors in journal:"
        echo "${JOURNAL_ERRS}" | while IFS= read -r line; do info "${line}"; done
    else ok "No filesystem/IO errors in recent journal"; fi

    section "SMART HEALTH CHECK"
    if command -v smartctl &>/dev/null; then
        echo -e "  ${DIM}Running smartctl...${RESET}"
        smartctl -H "${MMC_DEV}" 2>&1 | while IFS= read -r line; do echo "  ${line}"; done || true
        echo ""
        echo -e "  ${BOLD}SMART attributes:${RESET}"
        smartctl -A "${MMC_DEV}" 2>&1 | while IFS= read -r line; do echo "    ${line}"; done || true
    else
        warn "smartctl not installed — install with: sudo apt install smartmontools"
        info "Note: Many SD cards do not support SMART natively; the tests below are more reliable."
    fi

    section "MMC WEAR LEVELING & PRE-EOL STATUS (mmc-utils)"
    if command -v mmc &>/dev/null; then
        DEV_NUM=$(echo "${MMC_DEV}" | grep -oP '\d+$' || echo "0")
        mmc extcsd read "/dev/mmcblk${DEV_NUM}" 2>/dev/null \
            | grep -iE "(life time|pre-eol|device life|erase count|wear)" \
            | while IFS= read -r line; do
                kv "  $(echo "${line}" | cut -d: -f1):" "$(echo "${line}" | cut -d: -f2-)"
              done \
            || info "(Extended CSD data unavailable or not supported on this card)"
    else
        warn "mmc-utils not installed — install with: sudo apt install mmc-utils"
        info "mmc-utils reads wear-leveling counters and pre-EOL indicators from eMMC/SD cards."
    fi

    section "SEQUENTIAL READ SPEED"
    echo -e "  ${DIM}Flushing cache and reading 64MB from raw device...${RESET}"
    sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
    DD_R_OUT=$(dd if="${MMC_DEV}" of=/dev/null bs=4k count=16384 2>&1 | tail -1)
    READ_SPEED=$(echo "${DD_R_OUT}" | grep -oP '\d+\.?\d* [MKG]B/s' || echo "N/A")
    kv "Read speed:" "${READ_SPEED}"
    info "Raw: ${DD_R_OUT}"
    if echo "${READ_SPEED}" | grep -q "KB/s"; then
        err "Read speed critically low (KB/s range) — card may be failing or heavily worn"
    elif echo "${READ_SPEED}" | grep -q "MB/s"; then
        R_NUM=$(echo "${READ_SPEED}" | grep -oP '^\d+\.?\d*')
        if   (( $(echo "$R_NUM < 5"  | bc -l 2>/dev/null || echo 0) )); then err  "Read speed below 5 MB/s — degraded card"
        elif (( $(echo "$R_NUM < 15" | bc -l 2>/dev/null || echo 0) )); then warn "Read speed below 15 MB/s — slower than expected"
        else ok "Read speed acceptable: ${READ_SPEED}"; fi
    fi

    section "SEQUENTIAL WRITE SPEED"
    echo -e "  ${DIM}Writing 32MB to /tmp...${RESET}"
    TMP_W="/tmp/diag_sd_write_$$"
    DD_W_OUT=$(dd if=/dev/zero of="${TMP_W}" bs=4k count=8192 conv=fsync 2>&1 | tail -1)
    WRITE_SPEED=$(echo "${DD_W_OUT}" | grep -oP '\d+\.?\d* [MKG]B/s' || echo "N/A")
    rm -f "${TMP_W}"
    kv "Write speed:" "${WRITE_SPEED}"
    info "Raw: ${DD_W_OUT}"
    if echo "${WRITE_SPEED}" | grep -q "KB/s"; then
        err "Write speed critically low — card may be failing"
    elif echo "${WRITE_SPEED}" | grep -q "MB/s"; then
        W_NUM=$(echo "${WRITE_SPEED}" | grep -oP '^\d+\.?\d*')
        if   (( $(echo "$W_NUM < 2" | bc -l 2>/dev/null || echo 0) )); then err  "Write speed below 2 MB/s — degraded card"
        elif (( $(echo "$W_NUM < 6" | bc -l 2>/dev/null || echo 0) )); then warn "Write speed below 6 MB/s — below normal"
        else ok "Write speed acceptable: ${WRITE_SPEED}"; fi
    fi

    section "BAD BLOCK SCAN (optional, non-destructive)"
    echo -e "  ${YELLOW}Scans the entire card for unreadable blocks. Safe but slow (10-30 min).${RESET}"
    echo ""
    echo -ne "  Run bad block scan now? [y/N] "; read -r RUN_BB
    if [[ "${RUN_BB,,}" == "y" ]]; then
        BB_OUT="/tmp/badblocks_out_$$"
        echo -e "  ${DIM}Running: badblocks -sv -o ${BB_OUT} ${MMC_DEV}${RESET}"
        badblocks -sv -o "${BB_OUT}" "${MMC_DEV}" 2>&1 || true
        BB_COUNT=$(wc -l < "${BB_OUT}" 2>/dev/null || echo 0)
        if [[ "${BB_COUNT}" -gt 0 ]]; then
            err "${BB_COUNT} bad block(s) found:"
            cat "${BB_OUT}" | while IFS= read -r line; do info "  Block: ${line}"; done
        else ok "No bad blocks found"; fi
        rm -f "${BB_OUT}"
    else info "Skipped"; fi

    section "SD CARD HEALTH SUMMARY"
    RO_CHECK=$(grep " ro," /proc/mounts 2>/dev/null | grep -v "tmpfs\|proc\|sys\|devpts\|run" || true)
    MMC_ERR_COUNT=$(dmesg 2>/dev/null | grep -c -iE "mmcblk.*error|i/o error.*mmcblk" || true)
    [[ -n "${RO_CHECK}" ]]         && err  "Filesystem remounted read-only  -> HIGH confidence: replace card" \
                                   || ok   "Filesystem mounted read-write"
    [[ "${MMC_ERR_COUNT}" -gt 0 ]] && err  "${MMC_ERR_COUNT} MMC I/O error(s) in kernel log  -> HIGH confidence: replace card" \
                                   || ok   "No MMC I/O errors in kernel log"
    kv "Read speed:"  "${READ_SPEED}"
    kv "Write speed:" "${WRITE_SPEED}"

    press_enter
}

# ══════════════════════════════════════════════════════════════════════════════
#  OPTION 4 — LOG COLLECTION ONLY  [produces .tar.gz]
# ══════════════════════════════════════════════════════════════════════════════
run_log_collection() {
    ARCHIVE_NAME="${SCRIPT_DIR}/radianse_logs_${HOSTNAME_LABEL}_${TIMESTAMP}.tar.gz"
    WORK_DIR="${SCRIPT_DIR}/radianse_logs_${HOSTNAME_LABEL}_${TIMESTAMP}"
    mkdir -p "${WORK_DIR}"

    print_banner
    echo -e "  ${BOLD}Log Collection${RESET}"
    echo -e "  ${DIM}Compressing configured log directories into a .tar.gz archive.${RESET}"
    echo -e "  ${DIM}Output: ${ARCHIVE_NAME}${RESET}"
    echo ""

    section "COLLECTING LOGS"

    TOTAL_FILES=0
    MISSING_DIRS=()

    for DIR in "${LOG_COLLECTION_DIRS[@]}"; do
        if [[ -d "${DIR}" ]]; then
            # Preserve the source path structure inside the archive
            DEST="${WORK_DIR}/$(echo "${DIR}" | sed 's|^/||; s|/|_|g')"
            mkdir -p "${DEST}"
            cp -r "${DIR}/." "${DEST}/" 2>/dev/null || true
            COUNT=$(find "${DEST}" -type f | wc -l)
            ok "$(printf '%-50s' "${DIR}")  ${COUNT} file(s)"
            TOTAL_FILES=$((TOTAL_FILES + COUNT))
        else
            warn "Not found (skipped): ${DIR}"
            MISSING_DIRS+=("${DIR}")
        fi
    done

    # Also grab the system journal
    echo ""
    echo -e "  ${DIM}Exporting system journal (last 2000 lines)...${RESET}"
    journalctl --no-pager -n 2000 > "${WORK_DIR}/journal_full.txt" 2>/dev/null \
        && ok "journal_full.txt" \
        || warn "Journal export unavailable"

    section "SUMMARY"
    kv "Total log files copied:" "${TOTAL_FILES}"
    kv "Archive:" "${ARCHIVE_NAME}"
    if [[ ${#MISSING_DIRS[@]} -gt 0 ]]; then
        echo ""
        warn "The following directories were not found and were skipped:"
        for D in "${MISSING_DIRS[@]}"; do info "  ${D}"; done
        echo ""
        info "To add or remove directories, edit the LOG_COLLECTION_DIRS array at the top of the script."
    fi

    echo ""
    echo -e "  ${DIM}Packaging archive...${RESET}"
    tar -czf "${ARCHIVE_NAME}" -C "${SCRIPT_DIR}" "$(basename "${WORK_DIR}")"
    rm -rf "${WORK_DIR}"

    echo -e "  ${GREEN}${BOLD}Done! Archive saved:${RESET}"
    echo -e "    ${ARCHIVE_NAME}"
    echo ""
    echo -e "  ${BOLD}Archive contents:${RESET}"
    tar -tzf "${ARCHIVE_NAME}" | while IFS= read -r line; do echo "    ${line}"; done

    press_enter
}

# ══════════════════════════════════════════════════════════════════════════════
#  MAIN MENU
# ══════════════════════════════════════════════════════════════════════════════
main_menu() {
    while true; do
        print_banner
        echo -e "  ${BOLD}What would you like to do?${RESET}"
        echo ""
        echo -e "  ${CYAN}[1]${RESET}  Full System Diagnostic                  ${GREEN}saves .tar.gz${RESET}"
        echo -e "       ${DIM}Benchmarks, all service checks, logs — full archive${RESET}"
        echo ""
        echo -e "  ${CYAN}[2]${RESET}  Quick Snapshot                          ${DIM}terminal only${RESET}"
        echo -e "       ${DIM}Live readout — CPU, memory, disk, processes, serial devices${RESET}"
        echo ""
        echo -e "  ${CYAN}[3]${RESET}  SD Card Health Test                     ${DIM}terminal only${RESET}"
        echo -e "       ${DIM}Speed, kernel errors, wear data, optional bad block scan${RESET}"
        echo ""
        echo -e "  ${CYAN}[4]${RESET}  Collect & Archive Logs                  ${GREEN}saves .tar.gz${RESET}"
        echo -e "       ${DIM}Compresses configured log directories into a standalone archive${RESET}"
        echo ""
        echo -e "  ${CYAN}[Q]${RESET}  Quit"
        echo ""
        echo -ne "  ${BOLD}Select option: ${RESET}"
        read -r CHOICE
        case "${CHOICE,,}" in
            1) run_full_diagnostic  ;;
            2) run_brief_snapshot   ;;
            3) run_sd_card_test     ;;
            4) run_log_collection   ;;
            q|quit|exit) echo ""; echo -e "  ${DIM}Goodbye.${RESET}"; echo ""; exit 0 ;;
            *) echo -e "\n  ${YELLOW}Invalid option — please enter 1, 2, 3, 4, or Q.${RESET}"; sleep 1 ;;
        esac
    done
}

main_menu