#!/bin/bash
# ============================================================
# build.sh - Build Script cho OpenWrt Custom Newifi D2
# Usage: ./build.sh [full|quick|clean|menuconfig]
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENWRT_DIR="${SCRIPT_DIR}"
CONFIG_FILE="${OPENWRT_DIR}/.config.newifi-d2"
NPROC=$(nproc)
LOG_FILE="${OPENWRT_DIR}/build.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${GREEN}[BUILD]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ============================================================
# Kiểm tra Dependencies
# ============================================================
check_deps() {
    log "Kiểm tra build dependencies..."
    local missing=()
    
    for cmd in git make gcc g++ patch wget unzip python3 rsync file; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        error "Thiếu các packages: ${missing[*]}
Cài đặt bằng:
  sudo apt update && sudo apt install -y build-essential clang flex bison g++ gawk \\
  gcc-multilib g++-multilib gettext git libncurses5-dev libssl-dev python3-distutils \\
  python3-setuptools rsync unzip zlib1g-dev file wget"
    fi
    
    log "✓ Dependencies OK"
}

# ============================================================
# Update Feeds
# ============================================================
update_feeds() {
    log "Cập nhật feeds..."
    "${OPENWRT_DIR}/scripts/feeds" update -a 2>&1 | tail -5
    "${OPENWRT_DIR}/scripts/feeds" install -a 2>&1 | tail -5
    log "✓ Feeds updated"
}

# ============================================================
# Áp dụng Config
# ============================================================
apply_config() {
    log "Áp dụng .config.newifi-d2..."
    
    if [ ! -f "$CONFIG_FILE" ]; then
        error "Không tìm thấy $CONFIG_FILE"
    fi
    
    cp "$CONFIG_FILE" "${OPENWRT_DIR}/.config"
    
    # Expand config với các default values
    make defconfig 2>&1 | tail -3
    
    log "✓ Config applied"
    
    # Hiển thị thông tin
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  Target : $(grep 'CONFIG_TARGET_BOARD' .config 2>/dev/null | cut -d'"' -f2)${NC}"
    echo -e "${CYAN}  Device : D-Team Newifi D2${NC}"
    echo -e "${CYAN}  WiFi   : wpad-mbedtls + usteer (band steering)${NC}"
    echo -e "${CYAN}  Offload: Hardware Flow Offloading${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# ============================================================
# Build
# ============================================================
do_build() {
    local jobs="${1:-$NPROC}"
    
    log "Bắt đầu build với ${jobs} jobs..."
    log "Log file: ${LOG_FILE}"
    
    local start_time=$(date +%s)
    
    if make -j"${jobs}" 2>&1 | tee "${LOG_FILE}"; then
        local end_time=$(date +%s)
        local duration=$(( end_time - start_time ))
        local minutes=$(( duration / 60 ))
        local seconds=$(( duration % 60 ))
        
        log "✓ Build thành công! (${minutes}m ${seconds}s)"
        
        # Hiển thị firmware output
        echo ""
        echo -e "${GREEN}━━━━━━━━━ FIRMWARE FILES ━━━━━━━━━${NC}"
        local output_dir="bin/targets/ramips/mt7621"
        if [ -d "$output_dir" ]; then
            ls -lh "${output_dir}"/*newifi* 2>/dev/null || warn "Không tìm thấy firmware file"
            echo ""
            log "Firmware: ${output_dir}/"
            
            # Show file sizes
            local sysupgrade=$(find "$output_dir" -name "*sysupgrade*" -name "*newifi*" 2>/dev/null | head -1)
            if [ -n "$sysupgrade" ]; then
                local size=$(du -h "$sysupgrade" | cut -f1)
                echo -e "${GREEN}  → Sysupgrade: ${sysupgrade} (${size})${NC}"
            fi
        fi
    else
        error "Build thất bại! Kiểm tra log: ${LOG_FILE}
Thử build lại với: make -j1 V=s"
    fi
}

# ============================================================
# Main
# ============================================================
main() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════╗"
    echo "║    OpenWrt Custom Build - Newifi D2 (MT7621)    ║"
    echo "║    WiFi Stability Fix + Security Updates        ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    local action="${1:-full}"
    
    case "$action" in
        full)
            check_deps
            update_feeds
            apply_config
            do_build "$NPROC"
            ;;
        quick)
            # Build lại mà không update feeds
            apply_config
            do_build "$NPROC"
            ;;
        clean)
            log "Cleaning build..."
            make clean
            log "✓ Clean done"
            ;;
        dirclean)
            log "Deep cleaning (toolchain + build)..."
            make dirclean
            log "✓ Dirclean done"
            ;;
        menuconfig)
            apply_config
            make menuconfig
            # Lưu lại config sau khi chỉnh sửa
            cp "${OPENWRT_DIR}/.config" "$CONFIG_FILE"
            log "✓ Config saved to .config.newifi-d2"
            ;;
        download)
            apply_config
            log "Downloading sources..."
            make download -j"$NPROC"
            log "✓ Download done"
            ;;
        *)
            echo "Usage: $0 [full|quick|clean|dirclean|menuconfig|download]"
            echo ""
            echo "  full       - Full build (check deps + feeds + build)"
            echo "  quick      - Quick rebuild (skip feeds update)"
            echo "  clean      - Clean build files"
            echo "  dirclean   - Deep clean (includes toolchain)"
            echo "  menuconfig - Open menu config UI"
            echo "  download   - Download source packages only"
            exit 1
            ;;
    esac
}

main "$@"
