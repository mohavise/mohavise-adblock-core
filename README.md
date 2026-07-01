# Mohavise Adblock Core

This is the master adblock source repository.

It downloads upstream blocklists, applies the allowlist, removes duplicates, and publishes one clean canonical domain list for other repos to consume.

## Daily Timing

GitHub Actions runs at `23:30 UTC`, which is `03:00 Asia/Tehran`.

## Outputs

| File | Purpose |
| --- | --- |
| `core-domains.txt` | Canonical clean domain list, one domain per line |
| `core-hosts.txt` | Canonical hosts-format list |

## Config

| File | Purpose |
| --- | --- |
| `config/sources.txt` | Upstream blocklist URLs |
| `config/allowlist-core.txt` | Domains that must not be blocked |
| `config/blocklist-custom.txt` | Your own blocked domains |

## Downstream Repos

These repos should use `core-domains.txt` as their source:

```text
mohavise-mikrotik-adblock
mohavise-pihole-adlist
mohavise-fortigate-adblock
```

Core raw URL:

```text
https://raw.githubusercontent.com/mohavise/mohavise-adblock-core/main/core-domains.txt
```

## Logic

```text
upstream sources + custom blocklist - allowlist = core-domains.txt
```

