#!/usr/bin/env bash
# export.sh — export all formats supported by Structurizr
#
# Export runs a temporary container with the same image and volume,
# passing `export` instead of `local` as the command.
# This is necessary because the vNext image uses a shell wrapper entrypoint
# (/usr/local/structurizr.sh) and the structurizr binary is not in PATH.
#
# Works with Docker and Podman (including rootless Podman on openSUSE).
# Override the runtime with:
#   CONTAINER_RUNTIME=podman ./export.sh
#   CONTAINER_RUNTIME=docker ./export.sh
#
# Usage:
#   ./export.sh                 # all formats
#   ./export.sh png             # PNG only
#   ./export.sh svg             # SVG only
#   ./export.sh text            # text formats (plantuml, mermaid, dot, ilograph, json)
#   ./export.sh static          # navigable static site

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
WORKSPACE_DIR="${PROJECT_ROOT}/workspace"
OUTPUT_BASE="${PROJECT_ROOT}/exported"
CONTAINER="structurizr-local"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[export]${NC} $*"; }
warn() { echo -e "${YELLOW}[warn]${NC} $*"; }
fail() { echo -e "${RED}[error]${NC} $*" >&2; exit 1; }

# ─── Runtime detection ────────────────────────────────────────────────────────
detect_runtime() {
    if [[ -n "${CONTAINER_RUNTIME:-}" ]]; then
        echo "${CONTAINER_RUNTIME}"; return
    fi
    if command -v docker &>/dev/null; then echo "docker"
    elif command -v podman &>/dev/null; then echo "podman"
    else fail "Neither docker nor podman found in PATH."
    fi
}

RUNTIME="$(detect_runtime)"
log "Runtime: ${RUNTIME}"

# ─── Derive image from the running container ──────────────────────────────────
get_image() {
    ${RUNTIME} inspect "${CONTAINER}" --format '{{.Config.Image}}' 2>/dev/null \
        || fail "Container '${CONTAINER}' not found. Start it with: make up"
}

# ─── Run a temporary export container ────────────────────────────────────────
run_export() {
    local format="$1"
    local output_subdir="$2"
    local image
    image="$(get_image)"
    local host_out="${OUTPUT_BASE}/${output_subdir}"
    mkdir -p "${host_out}"

    log "Exporting format: ${format} -> exported/${output_subdir}/"
    ${RUNTIME} run --rm \
        -v "${WORKSPACE_DIR}:/usr/local/structurizr:z" \
        -v "${host_out}:/usr/local/exported:z" \
        "${image}" \
        export \
            -format "${format}" \
            -workspace /usr/local/structurizr/workspace.dsl \
            -output /usr/local/exported/ \
        || warn "Export ${format} failed (may not be supported for this workspace)"
}

# ─── PNG or SVG (require Playwright in the image) ────────────────────────────
export_raster() {
    local fmt="$1"
    log "=== Raster export (${fmt}) via Playwright ==="
    warn "First run downloads Chromium (~300MB) — may take a few minutes."
    run_export "${fmt}" "${fmt}"
}

# ─── Text formats ─────────────────────────────────────────────────────────────
export_text_formats() {
    log "=== Text format export ==="
    run_export "plantuml"            "plantuml"
    run_export "plantuml/c4plantuml" "plantuml-c4"
    run_export "mermaid"             "mermaid"
    run_export "dot"                 "dot"
    run_export "ilograph"            "ilograph"
    run_export "json"                "json"
}

# ─── Static site ──────────────────────────────────────────────────────────────
export_static() {
    log "=== Static site export ==="
    warn "The static site is a trimmed version of the UI (diagram navigation only)."
    run_export "static" "static"
}

# ─── Summary ─────────────────────────────────────────────────────────────────
summary() {
    local count
    count=$(find "${OUTPUT_BASE}" -type f 2>/dev/null | wc -l | tr -d ' ')
    log "Exported ${count} file(s) to ./exported/"
    find "${OUTPUT_BASE}" -type f 2>/dev/null | sort | sed "s|${PROJECT_ROOT}/||" | while read -r f; do
        echo "  ${f}"
    done
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
    local target="${1:-all}"

    case "${target}" in
        png)      export_raster png ;;
        svg)      export_raster svg ;;
        text)     export_text_formats ;;
        static)   export_static ;;
        plantuml) run_export "plantuml" "plantuml" ;;
        mermaid)  run_export "mermaid"  "mermaid"  ;;
        dot)      run_export "dot"      "dot"      ;;
        ilograph) run_export "ilograph" "ilograph" ;;
        json)     run_export "json"     "json"     ;;
        all)
            export_raster png
            export_raster svg
            export_text_formats
            export_static ;;
        *)
            fail "Unknown target: ${target}. Use: all | png | svg | text | static | plantuml | mermaid | dot | ilograph | json"
            ;;
    esac

    summary
    log "Done."
}

main "$@"
