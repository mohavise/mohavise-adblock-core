# Mohavise Adblock Core

Parent repository for the Mohavise adblock pipeline.

```text
Upstream blocklists
        ↓
mohavise-adblock-core
        ↓
MikroTik / Pi-hole / FortiGate child repositories
```

The core repository downloads upstream lists, normalizes entries, applies the custom blocklist and allowlist, validates the final categories, and publishes canonical domain files.

## Outputs

| File | Purpose |
| --- | --- |
| `core-adblock-domains.txt` | Ads and trackers |
| `core-adult-domains.txt` | Adult and NSFW domains |
| `core-domains.txt` | Exact combined union of both categories |

Raw endpoints:

```text
https://raw.githubusercontent.com/mohavise/mohavise-adblock-core/main/core-adblock-domains.txt
https://raw.githubusercontent.com/mohavise/mohavise-adblock-core/main/core-adult-domains.txt
https://raw.githubusercontent.com/mohavise/mohavise-adblock-core/main/core-domains.txt
```

## Configuration

| File | Purpose |
| --- | --- |
| `config/sources-adblock.txt` | Ad and tracker upstream sources |
| `config/sources-adult.txt` | Adult and NSFW upstream sources |
| `config/sources.txt` | Compatibility fallback source file |
| `config/allowlist-core.txt` | Domains and subdomains that must not be blocked |
| `config/blocklist-custom.txt` | Custom domains added to the adblock category |

Only HTTPS upstream source URLs are accepted.

## Build

```bash
./scripts/build-core.sh
```

## Validation Pipeline

Before any output is replaced, the builder performs:

```text
Download every configured upstream source
→ require complete source success
→ normalize supported hosts, DNS and adblock formats
→ lowercase and deduplicate domains
→ reject malformed domains and IP addresses
→ apply allowlist to domains and all subdomains
→ validate sorted and duplicate-free category outputs
→ verify combined output is the exact category union
→ verify allowlisted domains are absent
→ enforce minimum category counts
→ reject a count reduction greater than 20%
→ publish outputs
```

The maximum allowed reduction can be changed for a manual build:

```bash
MAX_DROP_PERCENT=10 ./scripts/build-core.sh
```

Partial upstream builds are rejected by default. For controlled troubleshooting only:

```bash
REQUIRE_ALL_SOURCES=no ./scripts/build-core.sh
```

## Category Logic

```text
adblock sources + custom blocklist - allowlist = core-adblock-domains.txt
adult sources - allowlist                    = core-adult-domains.txt
adblock union adult                          = core-domains.txt
```

An allowlist entry removes both the exact domain and its subdomains from every output.

## Daily Timing

| Process | Time |
| --- | --- |
| Core GitHub Actions build | `23:30 UTC` |
| Child repository builds | `00:00 UTC` |

The core workflow uses concurrency protection, a 20-minute timeout, and rebases before pushing. It does not commit when generated outputs are unchanged.

## Downstream Repositories

```text
mohavise-mikrotik-adblock
mohavise-pihole-adlist
mohavise-fortigate-adblock
```

Child repositories should treat these core outputs as validated source data while still applying platform-specific validation before publishing their own files.

## Cleanup Policy

Before removing repository files, read `CLEANUP_POLICY.md`. Generated outputs, compatibility files, configuration files, workflows, and scripts are intentional parts of the pipeline.
