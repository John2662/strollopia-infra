#!/usr/bin/env bash
# Pull latest code in all strollopia git repos

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for repo in "$DIR" "$DIR"/*/; do
    [ -d "$repo/.git" ] || continue
    name=$(basename "$repo")

    # Skip if there are uncommitted changes
    if ! git -C "$repo" diff --quiet 2>/dev/null || ! git -C "$repo" diff --cached --quiet 2>/dev/null; then
        echo -e "${YELLOW}⚠ $name — skipped (uncommitted changes)${NC}"
        continue
    fi

    branch=$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null)
    result=$(git -C "$repo" pull --ff-only 2>&1)

    if echo "$result" | grep -q "Already up to date"; then
        echo -e "${GREEN}✓ $name ($branch) — already up to date${NC}"
    elif echo "$result" | grep -q "error\|fatal"; then
        echo -e "${RED}✗ $name ($branch) — error: $result${NC}"
    else
        echo -e "${GREEN}↓ $name ($branch) — updated${NC}"
    fi
done
