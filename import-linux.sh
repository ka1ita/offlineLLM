#!/usr/bin/env bash
# OfflineLLM — Import Ollama models from .tar archives on Linux (Red Hat / RHEL)
#
# Imports archives created by offlineLLM.ps1 export (Windows) into Ollama.
#
# Usage:
#   ./import-linux.sh [-d archive_dir] [-o ollama_dir] [-f] [-r] [-h]
#
# Examples:
#   ./import-linux.sh -d /mnt/usb/archives
#   ./import-linux.sh -d /mnt/usb/archives -f -r
#   sudo ./import-linux.sh -d /mnt/usb/archives -o /usr/share/ollama/.ollama/models

set -uo pipefail

# ─── Colors ───────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then          # only colorise when writing to a terminal
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    GRAY='\033[0;37m'
    NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; GRAY=''; NC=''
fi

# ─── Output helpers ───────────────────────────────────────────────────────────
step()   { echo -e "  ${GRAY}$*${NC}"; }
ok()     { echo -e "  ${GREEN}[OK]${NC} $*"; }
warn()   { echo -e "  ${YELLOW}[!!]${NC} $*" >&2; }
fail()   { echo -e "  ${RED}[XX]${NC} $*" >&2; }
info()   { echo -e "  --> $*"; }

header() {
    local text="$*"
    local len=${#text}
    echo
    echo -e "  ${CYAN}${text}${NC}"
    printf '  '; printf '%0.s-' $(seq 1 "$len"); echo
}

# ─── Defaults ─────────────────────────────────────────────────────────────────
ARCHIVE_DIR="./archives"
OLLAMA_DIR=""
FORCE=0
RESTART_SERVICE=0

# ─── Usage ────────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF

OfflineLLM — Linux import script for Ollama models

Usage: $(basename "$0") [OPTIONS]

Options:
  -d DIR   Directory containing .tar archives  (default: ./archives)
  -o DIR   Ollama models directory             (default: \$OLLAMA_MODELS or ~/.ollama/models)
  -f       Force overwrite existing blobs and manifests
  -r       Restart Ollama service after import (systemctl restart ollama)
  -h       Show this help

Examples:
  $(basename "$0") -d /mnt/usb/archives
  $(basename "$0") -d /mnt/usb/archives -f -r
  sudo $(basename "$0") -d /mnt/usb/archives -o /usr/share/ollama/.ollama/models

Notes:
  • Archives must be .tar files created by offlineLLM.ps1 on Windows
  • Run as the same user that runs Ollama (usually your login user or 'ollama')
  • On RHEL with SELinux, restorecon is run automatically if available
EOF
}

# ─── Parse arguments ──────────────────────────────────────────────────────────
while getopts ":d:o:frh" opt; do
    case "$opt" in
        d) ARCHIVE_DIR="$OPTARG" ;;
        o) OLLAMA_DIR="$OPTARG" ;;
        f) FORCE=1 ;;
        r) RESTART_SERVICE=1 ;;
        h) usage; exit 0 ;;
        :) fail "Option -${OPTARG} requires an argument."; usage; exit 1 ;;
        *) fail "Unknown option: -${OPTARG}"; usage; exit 1 ;;
    esac
done

# ─── Resolve Ollama models directory ──────────────────────────────────────────
if [[ -z "$OLLAMA_DIR" ]]; then
    if [[ -n "${OLLAMA_MODELS:-}" ]]; then
        OLLAMA_DIR="$OLLAMA_MODELS"
    else
        OLLAMA_DIR="$HOME/.ollama/models"
    fi
fi

# ─── Preflight checks ─────────────────────────────────────────────────────────
preflight_ok=1

if ! command -v ollama &>/dev/null; then
    fail "ollama not found in PATH."
    info "Install: curl -fsSL https://ollama.com/install.sh | sh"
    preflight_ok=0
fi

if ! command -v tar &>/dev/null; then
    fail "tar not found."
    info "Install: sudo dnf install tar"
    preflight_ok=0
fi

[[ "$preflight_ok" -eq 0 ]] && exit 1

# ─── Validate archive directory ───────────────────────────────────────────────
if [[ ! -d "$ARCHIVE_DIR" ]]; then
    fail "Archive directory not found: $ARCHIVE_DIR"
    exit 1
fi

# Collect archives
mapfile -t ARCHIVES < <(find "$ARCHIVE_DIR" -maxdepth 1 -name "*.tar" | sort)

if [[ ${#ARCHIVES[@]} -eq 0 ]]; then
    fail "No .tar archives found in: $ARCHIVE_DIR"
    exit 1
fi

# ─── Main ─────────────────────────────────────────────────────────────────────
header "Import Ollama models from archives"
step "Archive directory  : $ARCHIVE_DIR"
step "Ollama models dir  : $OLLAMA_DIR"
step "Archives found     : ${#ARCHIVES[@]}"

# Ensure target directories exist
mkdir -p "$OLLAMA_DIR/blobs" "$OLLAMA_DIR/manifests"

SUCCESS=0
FAILED=0
tmpdir=""

cleanup() {
    [[ -n "$tmpdir" && -d "$tmpdir" ]] && rm -rf "$tmpdir"
}
trap cleanup EXIT

for archive in "${ARCHIVES[@]}"; do
    echo
    name=$(basename "$archive")
    info "Archive: $name"

    tmpdir=$(mktemp -d)

    # Extract archive
    if ! tar -xf "$archive" -C "$tmpdir"; then
        fail "Failed to extract: $name"
        rm -rf "$tmpdir"; tmpdir=""
        (( FAILED++ )) || true
        continue
    fi

    # ── Import blobs ──────────────────────────────────────────────────────────
    if [[ -d "$tmpdir/blobs" ]]; then
        while IFS= read -r -d '' blob; do
            bname=$(basename "$blob")
            dest="$OLLAMA_DIR/blobs/$bname"
            size_mb=$(( $(stat -c%s "$blob") / 1048576 ))

            if [[ -f "$dest" && "$FORCE" -eq 0 ]]; then
                step "  Blob (skip, exists): $bname"
            else
                cp "$blob" "$dest"
                step "  Blob: $bname  (${size_mb} MB)"
            fi
        done < <(find "$tmpdir/blobs" -type f -print0)
    fi

    # ── Import manifests ──────────────────────────────────────────────────────
    if [[ -d "$tmpdir/manifests" ]]; then
        while IFS= read -r -d '' mf; do
            rel="${mf#"$tmpdir/manifests/"}"
            dest="$OLLAMA_DIR/manifests/$rel"
            mkdir -p "$(dirname "$dest")"
            cp "$mf" "$dest"
            step "  Manifest: $rel"
        done < <(find "$tmpdir/manifests" -type f -print0)
    fi

    rm -rf "$tmpdir"; tmpdir=""
    ok "Imported: $(basename "$archive" .tar)"
    (( SUCCESS++ )) || true
done

# ─── SELinux context restoration (RHEL) ───────────────────────────────────────
if command -v restorecon &>/dev/null; then
    step "Restoring SELinux file contexts..."
    restorecon -r "$OLLAMA_DIR" 2>/dev/null && step "  SELinux contexts restored" \
        || warn "restorecon failed — you may need to run it manually as root"
fi

# ─── Summary ──────────────────────────────────────────────────────────────────
echo
header "Import summary"
ok "Imported : $SUCCESS"
[[ "$FAILED" -gt 0 ]] && fail "Failed   : $FAILED"

echo
info "Verify installed models:"
info "  ollama list"

# ─── Optional service restart ─────────────────────────────────────────────────
if [[ "$RESTART_SERVICE" -eq 1 ]]; then
    echo
    step "Restarting Ollama service..."
    if systemctl restart ollama 2>/dev/null; then
        ok "Ollama service restarted"
    elif sudo systemctl restart ollama 2>/dev/null; then
        ok "Ollama service restarted (via sudo)"
    else
        warn "Could not restart automatically. Run manually:"
        info "  sudo systemctl restart ollama"
    fi
else
    echo
    info "If models don't appear in 'ollama list', restart the service:"
    info "  sudo systemctl restart ollama"
fi

[[ "$FAILED" -gt 0 ]] && exit 1
exit 0
