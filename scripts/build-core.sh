#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"

SOURCES_FILE="${SOURCES_FILE:-$REPO_DIR/config/sources.txt}"
ALLOWLIST_FILE="${ALLOWLIST_FILE:-$REPO_DIR/config/allowlist-core.txt}"
CUSTOM_BLOCKLIST_FILE="${CUSTOM_BLOCKLIST_FILE:-$REPO_DIR/config/blocklist-custom.txt}"
DOMAIN_OUTPUT_FILE="${DOMAIN_OUTPUT_FILE:-$REPO_DIR/core-domains.txt}"
MIN_DOMAIN_COUNT="${MIN_DOMAIN_COUNT:-10000}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

normalize_domains() {
    awk '
        BEGIN { IGNORECASE = 1 }
        {
            line = tolower($0)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
            if (line == "" || line ~ /^#/) next
            sub(/^\|\|/, "", line)
            sub(/\^$/, "", line)
            sub(/^0\.0\.0\.0[[:space:]]+/, "", line)
            sub(/^127\.0\.0\.1[[:space:]]+/, "", line)
            sub(/^address=\//, "", line)
            sub(/\/.*$/, "", line)
            if (line ~ /^[a-z0-9][a-z0-9.-]*\.[a-z]{2,}$/) print line
        }
    '
}

source_count=0
success_count=0
while IFS= read -r source_url || [[ -n "$source_url" ]]; do
    source_url="${source_url#"${source_url%%[![:space:]]*}"}"
    source_url="${source_url%"${source_url##*[![:space:]]}"}"
    [[ -z "$source_url" || "$source_url" == \#* ]] && continue

    source_count=$((source_count + 1))
    if curl -fsSL "$source_url" | normalize_domains >> "$TMP_DIR/blocks.raw"; then
        success_count=$((success_count + 1))
    else
        echo "Warning: failed to download $source_url" >&2
    fi
done < "$SOURCES_FILE"

if (( source_count == 0 )); then
    echo "No source URLs found in $SOURCES_FILE" >&2
    exit 1
fi

if (( success_count == 0 )); then
    echo "All source downloads failed; refusing to overwrite $DOMAIN_OUTPUT_FILE" >&2
    exit 1
fi

normalize_domains < "$CUSTOM_BLOCKLIST_FILE" >> "$TMP_DIR/blocks.raw"
normalize_domains < "$ALLOWLIST_FILE" | sort -u > "$TMP_DIR/allow.txt"
sort -u "$TMP_DIR/blocks.raw" > "$TMP_DIR/blocks.txt"

awk '
    NR == FNR {
        allow[$0] = 1
        next
    }
    {
        domain = $0
        blocked = 0
        for (allowed in allow) {
            suffix = "." allowed
            if (domain == allowed || substr(domain, length(domain) - length(suffix) + 1) == suffix) {
                blocked = 1
                break
            }
        }
        if (!blocked) print domain
    }
' "$TMP_DIR/allow.txt" "$TMP_DIR/blocks.txt" > "$TMP_DIR/final.txt"

domain_count="$(wc -l < "$TMP_DIR/final.txt" | tr -d ' ')"
if (( domain_count < MIN_DOMAIN_COUNT )); then
    echo "Final domain count $domain_count is below minimum $MIN_DOMAIN_COUNT; refusing to overwrite $DOMAIN_OUTPUT_FILE" >&2
    exit 1
fi

cp "$TMP_DIR/final.txt" "$DOMAIN_OUTPUT_FILE"
echo "Generated $DOMAIN_OUTPUT_FILE with $domain_count blocked domains."
