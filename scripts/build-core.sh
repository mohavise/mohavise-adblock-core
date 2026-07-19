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
MAX_DROP_PERCENT="${MAX_DROP_PERCENT:-20}"
REQUIRE_ALL_SOURCES="${REQUIRE_ALL_SOURCES:-yes}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

require_file() {
    local file="$1"
    local label="$2"

    if [[ ! -f "$file" ]]; then
        echo "$label file not found: $file" >&2
        exit 1
    fi
}

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
            if (tld !~ /^[a-z]+$/ && tld !~ /^xn--[a-z0-9-]+$/) return 0

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
            sub(/\/.*/, "", line)
            sub(/[[:space:]].*$/, "", line)
            sub(/\.$/, "", line)

            if (is_valid_domain(line)) print line
        }
    '
}

download_source() {
    local source_url="$1"

    if [[ "$source_url" != https://* ]]; then
        echo "Refusing non-HTTPS source: $source_url" >&2
        return 1
    fi

    curl \
        --fail \
        --silent \
        --show-error \
        --location \
        --retry 5 \
        --retry-all-errors \
        --retry-delay 10 \
        --connect-timeout 20 \
        --max-time 180 \
        --user-agent "mohavise-adblock-core/1.0" \
        "$source_url"
}

build_category_raw() {
    local sources_file="$1"
    local output_raw_file="$2"
    local category_name="$3"
    local source_count=0
    local success_count=0
    local source_url
    local source_tmp

    : > "$output_raw_file"

    while IFS= read -r source_url || [[ -n "$source_url" ]]; do
        source_url="${source_url#"${source_url%%[![:space:]]*}"}"
        source_url="${source_url%"${source_url##*[![:space:]]}"}"
        [[ -z "$source_url" || "$source_url" == \#* ]] && continue

        source_count=$((source_count + 1))
        source_tmp="$TMP_DIR/${category_name}-source-${source_count}.txt"

        if download_source "$source_url" > "$source_tmp"; then
            normalize_domains < "$source_tmp" >> "$output_raw_file"
            success_count=$((success_count + 1))
        else
            echo "Failed to download $category_name source: $source_url" >&2
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

    if [[ "$REQUIRE_ALL_SOURCES" == "yes" ]] && (( success_count != source_count )); then
        echo "$category_name source completeness check failed: $success_count of $source_count sources succeeded" >&2
        exit 1
    fi

    echo "$category_name sources: $success_count of $source_count succeeded."
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
                if (domain == allowed || (length(domain) > length(suffix) && substr(domain, length(domain) - length(suffix) + 1) == suffix)) {
                    blocked = 1
                    break
                }
            }
            if (!blocked) print domain
        }
    ' "$TMP_DIR/allow.txt" "$input_file" > "$output_file"
}

validate_domain_file() {
    local file="$1"
    local label="$2"

    python3 - "$file" "$label" <<'PY'
import ipaddress
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
label = sys.argv[2]
label_re = re.compile(r"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$")
previous = None
seen = set()
errors = []

for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
    domain = raw.strip()
    if not domain or domain != raw:
        errors.append(f"line {number}: empty or surrounding whitespace")
        continue
    if domain != domain.lower():
        errors.append(f"line {number}: uppercase characters")
    if len(domain) > 253 or ".." in domain or domain.startswith(".") or domain.endswith("."):
        errors.append(f"line {number}: invalid domain structure: {domain}")
        continue
    try:
        ipaddress.ip_address(domain)
        errors.append(f"line {number}: IP address is not a domain: {domain}")
        continue
    except ValueError:
        pass
    parts = domain.split(".")
    if len(parts) < 2 or any(len(part) > 63 or not label_re.fullmatch(part) for part in parts):
        errors.append(f"line {number}: invalid label: {domain}")
        continue
    tld = parts[-1]
    if not (re.fullmatch(r"[a-z]{2,63}", tld) or re.fullmatch(r"xn--[a-z0-9-]{2,59}", tld)):
        errors.append(f"line {number}: invalid TLD: {domain}")
    if domain in seen:
        errors.append(f"line {number}: duplicate domain: {domain}")
    if previous is not None and domain < previous:
        errors.append(f"line {number}: file is not sorted")
    seen.add(domain)
    previous = domain

if errors:
    print(f"{label} validation failed:", file=sys.stderr)
    for error in errors[:20]:
        print(f"  {error}", file=sys.stderr)
    if len(errors) > 20:
        print(f"  ... and {len(errors) - 20} more", file=sys.stderr)
    sys.exit(1)
PY
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

validate_drop() {
    local new_file="$1"
    local old_file="$2"
    local label="$3"
    local new_count old_count minimum_allowed

    [[ -f "$old_file" ]] || return 0

    new_count="$(wc -l < "$new_file" | tr -d ' ')"
    old_count="$(grep -cve '^[[:space:]]*$' "$old_file" || true)"
    (( old_count > 0 )) || return 0

    minimum_allowed=$(( old_count * (100 - MAX_DROP_PERCENT) / 100 ))
    if (( new_count < minimum_allowed )); then
        echo "$label count dropped from $old_count to $new_count, more than ${MAX_DROP_PERCENT}%; refusing to publish" >&2
        exit 1
    fi
}

validate_exact_union() {
    local adblock_file="$1"
    local adult_file="$2"
    local combined_file="$3"

    sort -u "$adblock_file" "$adult_file" > "$TMP_DIR/expected-combined.txt"
    if ! cmp -s "$TMP_DIR/expected-combined.txt" "$combined_file"; then
        echo "Combined list is not the exact union of adblock and adult lists" >&2
        exit 1
    fi
}

validate_allowlist_absent() {
    local output_file="$1"
    local label="$2"

    if awk '
        NR == FNR { allow[$0] = 1; next }
        {
            for (allowed in allow) {
                suffix = "." allowed
                if ($0 == allowed || (length($0) > length(suffix) && substr($0, length($0) - length(suffix) + 1) == suffix)) {
                    print $0
                    exit 1
                }
            }
        }
    ' "$TMP_DIR/allow.txt" "$output_file"; then
        return 0
    fi

    echo "$label still contains an allowlisted domain or subdomain" >&2
    exit 1
}

require_file "$ALLOWLIST_FILE" "Allowlist"
require_file "$CUSTOM_BLOCKLIST_FILE" "Custom blocklist"

if [[ -f "$ADBLOCK_SOURCES_FILE" ]]; then
    build_category_raw "$ADBLOCK_SOURCES_FILE" "$TMP_DIR/adblock.raw" "adblock"
else
    require_file "$SOURCES_FILE" "Compatibility sources"
    echo "Warning: $ADBLOCK_SOURCES_FILE not found; using $SOURCES_FILE" >&2
    build_category_raw "$SOURCES_FILE" "$TMP_DIR/adblock.raw" "adblock"
fi

require_file "$ADULT_SOURCES_FILE" "Adult sources"
build_category_raw "$ADULT_SOURCES_FILE" "$TMP_DIR/adult.raw" "adult"

normalize_domains < "$CUSTOM_BLOCKLIST_FILE" >> "$TMP_DIR/adblock.raw"
normalize_domains < "$ALLOWLIST_FILE" | sort -u > "$TMP_DIR/allow.txt"

sort -u "$TMP_DIR/adblock.raw" > "$TMP_DIR/adblock.blocks.txt"
sort -u "$TMP_DIR/adult.raw" > "$TMP_DIR/adult.blocks.txt"
sort -u "$TMP_DIR/adblock.blocks.txt" "$TMP_DIR/adult.blocks.txt" > "$TMP_DIR/combined.blocks.txt"

apply_allowlist "$TMP_DIR/adblock.blocks.txt" "$TMP_DIR/adblock.final.txt"
apply_allowlist "$TMP_DIR/adult.blocks.txt" "$TMP_DIR/adult.final.txt"
apply_allowlist "$TMP_DIR/combined.blocks.txt" "$TMP_DIR/combined.final.txt"

validate_domain_file "$TMP_DIR/adblock.final.txt" "Adblock output"
validate_domain_file "$TMP_DIR/adult.final.txt" "Adult output"
validate_domain_file "$TMP_DIR/combined.final.txt" "Combined output"
validate_exact_union "$TMP_DIR/adblock.final.txt" "$TMP_DIR/adult.final.txt" "$TMP_DIR/combined.final.txt"
validate_allowlist_absent "$TMP_DIR/adblock.final.txt" "Adblock output"
validate_allowlist_absent "$TMP_DIR/adult.final.txt" "Adult output"
validate_allowlist_absent "$TMP_DIR/combined.final.txt" "Combined output"

adblock_count="$(validate_min_count "$TMP_DIR/adblock.final.txt" "$MIN_ADBLOCK_DOMAIN_COUNT" "Adblock")"
adult_count="$(validate_min_count "$TMP_DIR/adult.final.txt" "$MIN_ADULT_DOMAIN_COUNT" "Adult")"
combined_count="$(validate_min_count "$TMP_DIR/combined.final.txt" "$MIN_DOMAIN_COUNT" "Combined")"

validate_drop "$TMP_DIR/adblock.final.txt" "$ADBLOCK_OUTPUT_FILE" "Adblock"
validate_drop "$TMP_DIR/adult.final.txt" "$ADULT_OUTPUT_FILE" "Adult"
validate_drop "$TMP_DIR/combined.final.txt" "$DOMAIN_OUTPUT_FILE" "Combined"

cp "$TMP_DIR/adblock.final.txt" "$TMP_DIR/core-adblock-domains.txt"
cp "$TMP_DIR/adult.final.txt" "$TMP_DIR/core-adult-domains.txt"
cp "$TMP_DIR/combined.final.txt" "$TMP_DIR/core-domains.txt"

mv "$TMP_DIR/core-adblock-domains.txt" "$ADBLOCK_OUTPUT_FILE"
mv "$TMP_DIR/core-adult-domains.txt" "$ADULT_OUTPUT_FILE"
mv "$TMP_DIR/core-domains.txt" "$DOMAIN_OUTPUT_FILE"

echo "Generated $ADBLOCK_OUTPUT_FILE with $adblock_count blocked domains."
echo "Generated $ADULT_OUTPUT_FILE with $adult_count blocked domains."
echo "Generated $DOMAIN_OUTPUT_FILE with $combined_count blocked domains."
