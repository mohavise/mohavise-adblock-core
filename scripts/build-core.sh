#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"

ADBLOCK_SOURCES_FILE="${ADBLOCK_SOURCES_FILE:-$REPO_DIR/config/sources-adblock.txt}"
ADULT_SOURCES_FILE="${ADULT_SOURCES_FILE:-$REPO_DIR/config/sources-adult.txt}"
SOURCES_FILE="${SOURCES_FILE:-$REPO_DIR/config/sources.txt}"
ALLOWLIST_FILE="${ALLOWLIST_FILE:-$REPO_DIR/config/allowlist-core.txt}"
CUSTOM_BLOCKLIST_FILE="${CUSTOM_BLOCKLIST_FILE:-$REPO_DIR/config/blocklist-custom.txt}"
ADBLOCK_OUTPUT_FILE="${ADBLOCK_OUTPUT_FILE:-$REPO_DIR/core-adblock-domains.txt}"
ADULT_OUTPUT_FILE="${ADULT_OUTPUT_FILE:-$REPO_DIR/core-adult-domains.txt}"
DOMAIN_OUTPUT_FILE="${DOMAIN_OUTPUT_FILE:-$REPO_DIR/core-domains.txt}"
MIN_DOMAIN_COUNT="${MIN_DOMAIN_COUNT:-10000}"
MIN_ADBLOCK_DOMAIN_COUNT="${MIN_ADBLOCK_DOMAIN_COUNT:-10000}"
MIN_ADULT_DOMAIN_COUNT="${MIN_ADULT_DOMAIN_COUNT:-1000}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

normalize_domains() {
    awk '
        BEGIN { IGNORECASE = 1 }

        function is_valid_domain(domain, labels, label_count, i, label, tld) {
            if (domain == "") return 0
            if (length(domain) > 253) return 0
            if (domain ~ /[[:space:]]/) return 0
            if (domain ~ /\.\./) return 0
            if (domain ~ /^\./ || domain ~ /\.$/) return 0
            if (domain ~ /^[0-9]+(\.[0-9]+){3}$/) return 0
            if (domain !~ /^[a-z0-9.-]+$/) return 0

            label_count = split(domain, labels, ".")
            if (label_count < 2) return 0

            for (i = 1; i <= label_count; i++) {
                label = labels[i]
                if (label == "") return 0
                if (length(label) > 63) return 0
                if (label ~ /^-/ || label ~ /-$/) return 0
                if (label !~ /^[a-z0-9-]+$/) return 0
            }

            tld = labels[label_count]
            if (length(tld) < 2 || length(tld) > 63) return 0
            if (tld !~ /^[a-z]+$/) return 0

            return 1
        }

        {
            line = tolower($0)
            gsub(/\r/, "", line)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)

            if (line == "") next
            if (line ~ /^#/) next
            if (line ~ /^!/) next
            if (line ~ /^@@/) next
            if (line ~ /^\[/) next
            if (line ~ /^\//) next

            sub(/^0\.0\.0\.0[[:space:]]+/, "", line)
            sub(/^127\.0\.0\.1[[:space:]]+/, "", line)
            sub(/^::[[:space:]]+/, "", line)
            sub(/^address=\//, "", line)
            sub(/^server=\//, "", line)
            sub(/^local=\//, "", line)
            sub(/^\|\|/, "", line)
            sub(/^\*\./, "", line)

            sub(/[\^$].*$/, "", line)
            sub(/\/.*$/, "", line)
            sub(/[[:space:]].*$/, "", line)
            sub(/\.$/, "", line)

            if (is_valid_domain(line)) print line
        }
    '
}

download_source() {
    source_url="$1"

    curl \
        --fail \
        --silent \
        --show-error \
        --location \
        --retry 5 \
        --retry-all-errors \
        --retry-delay 10 \
        --connect-timeout 20 \
        --max-time 120 \
        --user-agent "mohavise-adblock-core/1.0" \
        "$source_url"
}

build_category_raw() {
    local sources_file="$1"
    local output_raw_file="$2"
    local category_name="$3"
    local source_count=0
    local success_count=0

    : > "$output_raw_file"

    while IFS= read -r source_url || [[ -n "$source_url" ]]; do
        source_url="${source_url#"${source_url%%[![:space:]]*}"}"
        source_url="${source_url%"${source_url##*[![:space:]]}"}"
        [[ -z "$source_url" || "$source_url" == \#* ]] && continue

        source_count=$((source_count + 1))
        if download_source "$source_url" | normalize_domains >> "$output_raw_file"; then
            success_count=$((success_count + 1))
        else
            echo "Warning: failed to download $category_name source: $source_url" >&2
        fi
    done < "$sources_file"

    if (( source_count == 0 )); then
        echo "No $category_name source URLs found in $sources_file" >&2
        exit 1
    fi

    if (( success_count == 0 )); then
        echo "All $category_name source downloads failed" >&2
        exit 1
    fi
}

apply_allowlist() {
    local input_file="$1"
    local output_file="$2"

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
    ' "$TMP_DIR/allow.txt" "$input_file" > "$output_file"
}

validate_min_count() {
    local file="$1"
    local minimum="$2"
    local label="$3"
    local count

    count="$(wc -l < "$file" | tr -d ' ')"
    if (( count < minimum )); then
        echo "$label domain count $count is below minimum $minimum; refusing to overwrite outputs" >&2
        exit 1
    fi

    echo "$count"
}

if [[ -f "$ADBLOCK_SOURCES_FILE" ]]; then
    build_category_raw "$ADBLOCK_SOURCES_FILE" "$TMP_DIR/adblock.raw" "adblock"
else
    echo "Warning: $ADBLOCK_SOURCES_FILE not found; using compatibility sources file $SOURCES_FILE" >&2
    build_category_raw "$SOURCES_FILE" "$TMP_DIR/adblock.raw" "adblock"
fi

if [[ -f "$ADULT_SOURCES_FILE" ]]; then
    build_category_raw "$ADULT_SOURCES_FILE" "$TMP_DIR/adult.raw" "adult"
else
    echo "Warning: $ADULT_SOURCES_FILE not found; creating empty adult category" >&2
    : > "$TMP_DIR/adult.raw"
fi

normalize_domains < "$CUSTOM_BLOCKLIST_FILE" >> "$TMP_DIR/adblock.raw"
normalize_domains < "$ALLOWLIST_FILE" | sort -u > "$TMP_DIR/allow.txt"

sort -u "$TMP_DIR/adblock.raw" > "$TMP_DIR/adblock.blocks.txt"
sort -u "$TMP_DIR/adult.raw" > "$TMP_DIR/adult.blocks.txt"
cat "$TMP_DIR/adblock.blocks.txt" "$TMP_DIR/adult.blocks.txt" | sort -u > "$TMP_DIR/combined.blocks.txt"

apply_allowlist "$TMP_DIR/adblock.blocks.txt" "$TMP_DIR/adblock.final.txt"
apply_allowlist "$TMP_DIR/adult.blocks.txt" "$TMP_DIR/adult.final.txt"
apply_allowlist "$TMP_DIR/combined.blocks.txt" "$TMP_DIR/combined.final.txt"

adblock_count="$(validate_min_count "$TMP_DIR/adblock.final.txt" "$MIN_ADBLOCK_DOMAIN_COUNT" "Adblock")"
adult_count="$(validate_min_count "$TMP_DIR/adult.final.txt" "$MIN_ADULT_DOMAIN_COUNT" "Adult")"
combined_count="$(validate_min_count "$TMP_DIR/combined.final.txt" "$MIN_DOMAIN_COUNT" "Combined")"

cp "$TMP_DIR/adblock.final.txt" "$ADBLOCK_OUTPUT_FILE"
cp "$TMP_DIR/adult.final.txt" "$ADULT_OUTPUT_FILE"
cp "$TMP_DIR/combined.final.txt" "$DOMAIN_OUTPUT_FILE"

echo "Generated $ADBLOCK_OUTPUT_FILE with $adblock_count blocked domains."
echo "Generated $ADULT_OUTPUT_FILE with $adult_count blocked domains."
echo "Generated $DOMAIN_OUTPUT_FILE with $combined_count blocked domains."
