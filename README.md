# Mohavise Adblock Core

This is the parent/core repository for the Mohavise adblock system.

It downloads upstream blocklists, normalizes and validates domains, applies the allowlist, removes duplicates, and publishes clean canonical domain lists for child repos to consume.

## Daily Timing

GitHub Actions runs at `23:30 UTC`, which is `03:00 Asia/Tehran`.

Child repos run later at `00:00 UTC`, which is `03:30 Asia/Tehran`.

## Outputs

| File | Purpose |
| --- | --- |
| `core-adblock-domains.txt` | Valid ad/tracker blocking domains only |
| `core-adult-domains.txt` | Valid adult/NSFW blocking domains only |
| `core-domains.txt` | Combined valid canonical list used by child repos |

Default downstream repos should use `core-domains.txt` unless they need category-specific output.

## Config

| File | Purpose |
| --- | --- |
| `config/sources-adblock.txt` | Upstream ad/tracker source URLs |
| `config/sources-adult.txt` | Upstream adult/NSFW source URLs |
| `config/sources.txt` | Compatibility combined source list |
| `config/allowlist-core.txt` | Domains that must not be blocked |
| `config/blocklist-custom.txt` | Your own custom blocked domains |

## Source Strategy

```text
AdGuard DNS Filter  → core-adblock-domains.txt
HaGeZi NSFW         → core-adult-domains.txt
Both together       → core-domains.txt
```

## Build

```bash
./scripts/build-core.sh
```

## Downstream Repos

These repos should use `core-domains.txt` as their default source:

```text
mohavise-mikrotik-adblock
mohavise-pihole-adlist
mohavise-fortigate-adblock
```

Core raw URLs:

```text
https://raw.githubusercontent.com/mohavise/mohavise-adblock-core/main/core-domains.txt
https://raw.githubusercontent.com/mohavise/mohavise-adblock-core/main/core-adblock-domains.txt
https://raw.githubusercontent.com/mohavise/mohavise-adblock-core/main/core-adult-domains.txt
```

## Validation

The build script validates domain lines before publishing outputs.

It rejects invalid or unsafe entries such as comments, exception rules, regex rules, IP-only lines, spaces, double dots, invalid labels, overlong labels, and bad TLDs.

## Update-Ready Approach

```text
Parent/core repo validates and publishes canonical lists.
Category outputs stay separated for future control.
Combined output feeds child repos by default.
Child repos convert the combined list into platform-ready outputs.
Managed outputs are rebuilt by GitHub Actions on schedule.
```

## Future Vision

```text
One clean parent system.
Separate category outputs.
One combined default output.
Multiple child platform outputs.
Same timing strategy.
Safe daily updates.
Easy rollback and future category expansion.
```

## Logic

```text
adblock sources + custom blocklist - allowlist = core-adblock-domains.txt
adult sources - allowlist                     = core-adult-domains.txt
adblock + adult - allowlist                   = core-domains.txt
```

## Cleanup Policy

Before removing any file from this repository, read `CLEANUP_POLICY.md`.

Generated outputs, compatibility files, fallback source files, workflows, and scripts are intentional parts of the process. Do not delete them only because they look duplicated, old, or generated.
