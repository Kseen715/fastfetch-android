#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${OUT_DIR:-./out}"
REMOTE="/data/local/tmp/fastfetch"

run_on_device() {
    local serial="$1"
    local binary="$2"
    local label="$3"

    echo ""
    echo "=== ${label} (${serial}) ==="
    adb -s "${serial}" push "${binary}" "${REMOTE}"
    adb -s "${serial}" shell "chmod +x ${REMOTE}"
    echo "--- version ---"
    adb -s "${serial}" shell "${REMOTE} --version"
    echo "--- full run ---"
    adb -s "${serial}" shell "${REMOTE} --pipe"
}

run_on_device "7BQDU17110010631" "${OUT_DIR}/fastfetch-aarch64" "Honor 6X (arm64)"
run_on_device "EAOKBC381276"     "${OUT_DIR}/fastfetch-x86"     "ASUS Fonepad 8 (x86)"
