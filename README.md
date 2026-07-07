# Mohavise Adblock Core

Parent repository for the Mohavise adblock system.

It builds one clean domain list for the child repositories.

## Timing

Core workflow: `23:30 UTC`.
Child workflows: `00:00 UTC`.

## Output

```text
core-adblock-domains.txt
```

Raw URL:

```text
https://raw.githubusercontent.com/mohavise/mohavise-adblock-core/main/core-adblock-domains.txt
```

## Config

```text
config/sources-adblock.txt
config/allowlist-core.txt
config/blocklist-custom.txt
```

## Build

```bash
./scripts/build-core.sh
```

## Child repos

```text
mohavise-mikrotik-adblock
mohavise-pihole-adlist
mohavise-fortigate-adblock
```
