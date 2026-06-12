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

run_on_device "7BQDU17110010631" "${OUT_DIR}/fastfetch-armv8"       "Honor 6X (arm64-v8a, A7.0)"
run_on_device "EAOKBC381276"     "${OUT_DIR}/fastfetch-x86"         "ASUS Fonepad 8 (x86, A5.0)"
run_on_device "DU2JLA141F024744" "${OUT_DIR}/fastfetch-armv7"       "Huawei Honor 3 (armeabi-v7a, A4.2.2)"
run_on_device "F83DFFFFA4EB"     "${OUT_DIR}/fastfetch-armv7-nopie" "Huawei U8815 (armeabi-v7a noPIE, A4.0.3)"
