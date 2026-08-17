#!/usr/bin/env bash
# sync-report.sh — diff and sync files between data_logger and strollopia-pwa
#
# Usage:
#   ./sync-report.sh                      # full sync report
#   ./sync-report.sh --diff <file>        # side-by-side diff for one file
#   ./sync-report.sh --copy dl2pwa <file> # copy data_logger → strollopia-pwa
#   ./sync-report.sh --copy pwa2dl <file> # copy strollopia-pwa → data_logger

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DL="$SCRIPT_DIR/data_logger"
PWA="$SCRIPT_DIR/strollopia-pwa"

# Colour codes
RED='\033[0;31m'; YELLOW='\033[0;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

# Files that are intentionally different between the two repos
DIVERGED=(
  "app/page.js"
  "components/AppShell.js"
  "lib/auth.js"
  "app/providers.js"
  "app/builder/route/page.js"
  "app/builder/route/build/page.js"
)

is_diverged() {
  local f="$1"
  for d in "${DIVERGED[@]}"; do
    [[ "$f" == "$d" ]] && return 0
  done
  return 1
}

# ── --diff ──────────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--diff" ]]; then
  file="${2:-}"
  [[ -z "$file" ]] && { echo "Usage: $0 --diff <relative/path>"; exit 1; }
  a="$DL/$file"; b="$PWA/$file"
  [[ ! -f "$a" ]] && { echo -e "${RED}Not in data_logger: $file${RESET}"; exit 1; }
  [[ ! -f "$b" ]] && { echo -e "${RED}Not in strollopia-pwa: $file${RESET}"; exit 1; }
  echo -e "${BOLD}diff  data_logger/$file  ←→  strollopia-pwa/$file${RESET}"
  diff --color=always -u "$a" "$b" || true
  exit 0
fi

# ── --copy ───────────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--copy" ]]; then
  direction="${2:-}"; file="${3:-}"
  [[ -z "$direction" || -z "$file" ]] && {
    echo "Usage: $0 --copy dl2pwa|pwa2dl <relative/path>"; exit 1
  }
  if [[ "$direction" == "dl2pwa" ]]; then
    src="$DL/$file"; dst="$PWA/$file"
    label="data_logger → strollopia-pwa"
  elif [[ "$direction" == "pwa2dl" ]]; then
    src="$PWA/$file"; dst="$DL/$file"
    label="strollopia-pwa → data_logger"
  else
    echo "Unknown direction '$direction'. Use dl2pwa or pwa2dl."; exit 1
  fi
  [[ ! -f "$src" ]] && { echo -e "${RED}Source not found: $src${RESET}"; exit 1; }
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
  echo -e "${GREEN}Copied ($label): $file${RESET}"
  exit 0
fi

# ── Full sync report ─────────────────────────────────────────────────────────
echo -e "\n${BOLD}${CYAN}=== Strollopia Sync Report ===${RESET}"
echo -e "data_logger  →  $DL"
echo -e "strollopia-pwa  →  $PWA\n"

identical=0; near_identical=0; diverged_count=0; pwa_only_count=0; dl_only_count=0

# Collect all relative paths from data_logger (excluding .next, node_modules, .git)
mapfile -d '' DL_FILES < <(
  find "$DL" -type f \
    ! -path "*/.next/*" ! -path "*/node_modules/*" ! -path "*/.git/*" \
    -printf "%P\0" | sort -z
)

# Collect relative paths from strollopia-pwa
mapfile -d '' PWA_FILES < <(
  find "$PWA" -type f \
    ! -path "*/.next/*" ! -path "*/node_modules/*" ! -path "*/.git/*" \
    -printf "%P\0" | sort -z
)

# Build sets for quick lookup
declare -A DL_SET PWA_SET
for f in "${DL_FILES[@]}"; do DL_SET["$f"]=1; done
for f in "${PWA_FILES[@]}"; do PWA_SET["$f"]=1; done

echo -e "${BOLD}── Files in data_logger ──────────────────────────────────${RESET}"

for f in "${DL_FILES[@]}"; do
  if [[ -z "${PWA_SET[$f]+x}" ]]; then
    echo -e "  ${RED}DL only   ${RESET}  $f"
    (( dl_only_count++ )) || true
    continue
  fi

  a="$DL/$f"; b="$PWA/$f"

  if diff -q "$a" "$b" > /dev/null 2>&1; then
    (( identical++ )) || true
    continue
  fi

  if is_diverged "$f"; then
    echo -e "  ${YELLOW}diverged  ${RESET}  $f  ${YELLOW}(intentional)${RESET}"
    (( diverged_count++ )) || true
  else
    lines=$(diff "$a" "$b" | grep -c '^[<>]' || true)
    echo -e "  ${RED}differs   ${RESET}  $f  ${RED}($lines changed lines)${RESET}"
    (( near_identical++ )) || true
  fi
done

echo -e "\n${BOLD}── Files only in strollopia-pwa ──────────────────────────${RESET}"

for f in "${PWA_FILES[@]}"; do
  if [[ -z "${DL_SET[$f]+x}" ]]; then
    echo -e "  ${CYAN}PWA only  ${RESET}  $f"
    (( pwa_only_count++ )) || true
  fi
done

echo -e "\n${BOLD}── Summary ───────────────────────────────────────────────${RESET}"
echo -e "  ${GREEN}Identical      ${RESET} $identical"
echo -e "  ${RED}Unsynced diffs ${RESET} $near_identical  ← run './sync-report.sh --diff <file>' to inspect"
echo -e "  ${YELLOW}Intentionally diverged ${RESET} $diverged_count"
echo -e "  ${CYAN}PWA-only files ${RESET} $pwa_only_count"
echo -e "  ${RED}DL-only files  ${RESET} $dl_only_count"
echo ""

if (( near_identical > 0 )); then
  echo -e "${BOLD}Tip:${RESET} sync a file with:"
  echo -e "  ./sync-report.sh --copy dl2pwa <file>   # push data_logger version to pwa"
  echo -e "  ./sync-report.sh --copy pwa2dl <file>   # pull pwa version to data_logger"
fi
