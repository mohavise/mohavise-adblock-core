param(
    [string]$SourcesFile = "..\config\sources.txt",
    [string]$AllowlistFile = "..\config\allowlist-core.txt",
    [string]$CustomBlocklistFile = "..\config\blocklist-custom.txt",
    [string]$DomainOutputFile = "..\core-domains.txt",
    [string]$HostOutputFile = "..\core-hosts.txt"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Read-DomainFile {
    param([string]$Path)

    if (!(Test-Path -LiteralPath $Path)) {
        return @()
    }

    Get-Content -LiteralPath $Path | ForEach-Object {
        $line = $_.Trim().ToLowerInvariant()
        if ($line -ne "" -and !$line.StartsWith("#")) {
            $line = $line -replace "^\|\|", ""
            $line = $line -replace "\^$", ""
            $line = $line -replace "^0\.0\.0\.0\s+", ""
            $line = $line -replace "^127\.0\.0\.1\s+", ""
            $line = $line -replace "^address=/", ""
            $line = $line -replace "/.*$", ""

            if ($line -match "^[a-z0-9][a-z0-9.-]*\.[a-z]{2,}$") {
                $line
            }
        }
    }
}

function Read-SourceFile {
    param([string]$Path)

    if (!(Test-Path -LiteralPath $Path)) {
        return @()
    }

    Get-Content -LiteralPath $Path | ForEach-Object {
        $line = $_.Trim()
        if ($line -ne "" -and !$line.StartsWith("#")) {
            $line
        }
    }
}

function Test-Allowlisted {
    param(
        [string]$Domain,
        [string[]]$AllowedDomains
    )

    foreach ($allowed in $AllowedDomains) {
        if ($Domain -eq $allowed -or $Domain.EndsWith(".$allowed")) {
            return $true
        }
    }

    return $false
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptRoot

$sources = Read-SourceFile $SourcesFile
$allow = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
Read-DomainFile $AllowlistFile | ForEach-Object { [void]$allow.Add($_) }
$allowedDomains = @($allow)

$blocks = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

foreach ($source in $sources) {
    try {
        $content = Invoke-WebRequest -Uri $source -UseBasicParsing
        $temp = New-TemporaryFile
        Set-Content -LiteralPath $temp -Value $content.Content -Encoding UTF8
        Read-DomainFile $temp | ForEach-Object { [void]$blocks.Add($_) }
        Remove-Item -LiteralPath $temp -Force
    }
    catch {
        Write-Warning "Failed to download $source"
        Write-Warning $_.Exception.Message
    }
}

Read-DomainFile $CustomBlocklistFile | ForEach-Object { [void]$blocks.Add($_) }

$final = $blocks |
    Where-Object { -not (Test-Allowlisted -Domain $_ -AllowedDomains $allowedDomains) } |
    Sort-Object

Set-Content -LiteralPath $DomainOutputFile -Value $final -Encoding ASCII
Set-Content -LiteralPath $HostOutputFile -Value ($final | ForEach-Object { "0.0.0.0 $_" }) -Encoding ASCII

Write-Host "Generated $DomainOutputFile and $HostOutputFile with $($final.Count) blocked domains."

