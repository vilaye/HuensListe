<#
  Huens Liste updater
  Downloads the latest release of Huens Liste from GitHub and installs it into
  World of Warcraft\_forever_\Interface\AddOns\HuensListe.
  Your KOS list is stored in the WTF folder and is not touched.

  Usage: double-click Update-HuensListe.bat
         or: powershell -ExecutionPolicy Bypass -File Update-HuensListe.ps1 [-AddOnsPath "D:\Games\World of Warcraft\_forever_\Interface\AddOns"]
#>
param(
    [string]$AddOnsPath,
    [switch]$Elevated
)

$ErrorActionPreference = "Stop"
$Repo      = "vilaye/HuensListe"
$AddonName = "HuensListe"

# GitHub needs TLS 1.2 (older Windows PowerShell defaults to TLS 1.0)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Find-AddOnsFolder {
    $candidates = @()

    # Battle.net install path from the registry
    foreach ($key in @(
        "HKLM:\SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft",
        "HKLM:\SOFTWARE\Blizzard Entertainment\World of Warcraft")) {
        try {
            $p = (Get-ItemProperty -Path $key -ErrorAction Stop).InstallPath
            if ($p) {
                # InstallPath usually points at a game-type folder like ...\_retail_\
                $root = Split-Path ($p.TrimEnd('\')) -Parent
                $candidates += (Join-Path $root "_forever_\Interface\AddOns")
            }
        } catch { }
    }

    $candidates += "C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns"
    $candidates += "C:\Program Files\World of Warcraft\_forever_\Interface\AddOns"
    foreach ($drive in (Get-PSDrive -PSProvider FileSystem).Root) {
        $candidates += (Join-Path $drive "World of Warcraft\_forever_\Interface\AddOns")
        $candidates += (Join-Path $drive "Games\World of Warcraft\_forever_\Interface\AddOns")
    }

    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }
    return $null
}

function Test-Writable([string]$dir) {
    try {
        $probe = Join-Path $dir (".hl_write_test_" + [guid]::NewGuid().ToString("N"))
        New-Item -ItemType File -Path $probe -Force | Out-Null
        Remove-Item $probe -Force
        return $true
    } catch { return $false }
}

Write-Host ""
Write-Host "=== Huens Liste updater ===" -ForegroundColor Red
Write-Host ""

# 1. Find the AddOns folder
if (-not $AddOnsPath) { $AddOnsPath = Find-AddOnsFolder }
if (-not $AddOnsPath -or -not (Test-Path $AddOnsPath)) {
    Write-Host "Could not find your WoW Forever AddOns folder automatically."
    $AddOnsPath = Read-Host "Paste the path (e.g. C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns)"
    $AddOnsPath = $AddOnsPath.Trim('"', ' ')
    if (-not (Test-Path $AddOnsPath)) { throw "Folder not found: $AddOnsPath" }
}
Write-Host "AddOns folder: $AddOnsPath"

# 2. Program Files usually needs admin rights: restart elevated if we can't write
if (-not (Test-Writable $AddOnsPath)) {
    Write-Host "No write access - restarting as administrator..." -ForegroundColor Yellow
    $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -AddOnsPath `"$AddOnsPath`" -Elevated"
    Start-Process powershell -Verb RunAs -ArgumentList $argList
    exit
}

# 3. Find the download: latest GitHub release zip, or the main branch if there is no release yet
$headers = @{ "User-Agent" = "HuensListe-Updater"; "Accept" = "application/vnd.github+json" }
$downloadUrl = $null
$versionLabel = $null
try {
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -Headers $headers
    $asset = $release.assets | Where-Object { $_.name -like "*.zip" } | Select-Object -First 1
    if ($asset) {
        $downloadUrl  = $asset.browser_download_url
        $versionLabel = $release.tag_name
    }
} catch { }
if (-not $downloadUrl) {
    $downloadUrl  = "https://github.com/$Repo/archive/refs/heads/main.zip"
    $versionLabel = "main (no release yet)"
}
Write-Host "Downloading $versionLabel ..."

# 4. Download and unpack into a temp folder
$tmp = Join-Path $env:TEMP ("HuensListe_" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    $zip = Join-Path $tmp "addon.zip"
    Invoke-WebRequest -Uri $downloadUrl -OutFile $zip -Headers @{ "User-Agent" = "HuensListe-Updater" } -UseBasicParsing
    $extract = Join-Path $tmp "x"
    Expand-Archive -Path $zip -DestinationPath $extract -Force

    # The folder that contains HuensListe.toc is the addon
    $toc = Get-ChildItem -Path $extract -Recurse -Filter "$AddonName.toc" | Select-Object -First 1
    if (-not $toc) { throw "The download does not contain $AddonName.toc" }
    $source = $toc.Directory.FullName

    # 5. Replace the installed copy
    $target = Join-Path $AddOnsPath $AddonName
    if (Test-Path $target) { Remove-Item $target -Recurse -Force }
    New-Item -ItemType Directory -Path $target | Out-Null
    Get-ChildItem -Path $source -Force |
        Where-Object { $_.Name -notin @(".github", ".git", ".gitignore", ".pkgmeta", "tools") } |
        Copy-Item -Destination $target -Recurse -Force

    $version = (Select-String -Path (Join-Path $target "$AddonName.toc") -Pattern "^## Version:\s*(.+)$").Matches.Groups[1].Value
    Write-Host ""
    Write-Host "Installed Huens Liste $version" -ForegroundColor Green
    Write-Host "Type /reload in game (or restart WoW) to load it."
}
finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    if ($Elevated) { Read-Host "Press Enter to close" | Out-Null }
}
