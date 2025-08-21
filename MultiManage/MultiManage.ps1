# PowerShell script implementing Manual Mod Multi-Manager for Cyberpunk 2077
# This script manages character-specific mod profiles by copying files into
# the game directories and tracking them via manifests so they can be safely
# removed later. It supports WhatIf, backups, logging, and sandbox testing.

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [switch]$Sandbox
)

# region Path initialisation and helpers
# Determine the directory containing this script and set up game/multi-manage paths.
$ScriptRoot   = Split-Path -Parent $MyInvocation.MyCommand.Path
if ($Sandbox) {
    # In sandbox mode, create isolated GameRoot and MultiManage directories under ./Sandbox
    $SandboxRoot = Join-Path $ScriptRoot 'Sandbox'
    $GameRoot = Join-Path $SandboxRoot 'GameRoot'
    $MultiManageRoot = Join-Path $SandboxRoot 'MultiManage'
} else {
    # Normal mode: script sits inside MultiManage, game root is parent folder
    $MultiManageRoot = $ScriptRoot
    $GameRoot = Split-Path -Parent $MultiManageRoot
}

# Ensure key directories exist
$null = New-Item -ItemType Directory -Force -Path (Join-Path $MultiManageRoot 'logs')
$BackupRoot = Join-Path $MultiManageRoot '.backup'
$null = New-Item -ItemType Directory -Force -Path $BackupRoot

# Set up logging infrastructure
$LogFile = Join-Path (Join-Path $MultiManageRoot 'logs') ("MultiManage_{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format 'u'
    $line = "[$timestamp] $Message"
    Add-Content -Path $LogFile -Value $line
    Write-Host $Message
}
# endregion

# region Utility functions
# Compute relative path of a file with respect to a root directory
function Get-RelativePath {
    param([string]$Root, [string]$FullPath)
    $rootPath = (Resolve-Path $Root).Path
    $fullPath = (Resolve-Path $FullPath).Path
    return $fullPath.Substring($rootPath.Length).TrimStart([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
}

# Return SHA256 hash for a file if it exists
function Get-Hash {
    param([string]$Path)
    if (Test-Path $Path) {
        return (Get-FileHash -Path $Path -Algorithm SHA256).Hash
    }
    return $null
}

# Backup a file to the timestamped backup directory before overwrite/delete
function Backup-File {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([string]$FilePath, [string]$Operation, [string]$Timestamp)
    $rel = Get-RelativePath -Root $GameRoot -FullPath $FilePath
    $dest = Join-Path (Join-Path $BackupRoot $Timestamp) $rel
    New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
    if ($PSCmdlet.ShouldProcess($FilePath, "Backup for $Operation")) {
        Copy-Item -Path $FilePath -Destination $dest -Force
    }
    Write-Log "Backed up $rel to $dest before $Operation"
}

# Remove empty directories under given paths
function Prune-EmptyDirs {
    param([string[]]$Roots)
    foreach ($root in $Roots) {
        if (Test-Path $root) {
            Get-ChildItem -Path $root -Recurse -Directory | Sort-Object FullName -Descending | ForEach-Object {
                if (-not (Get-ChildItem -Path $_.FullName -Recurse -File | Where-Object { $true })) {
                    Remove-Item -Path $_.FullName -Force
                }
            }
        }
    }
}

# Read current active profile marker
function Get-ActiveProfile {
    $marker = Join-Path $MultiManageRoot '.active'
    if (Test-Path $marker) { return (Get-Content $marker -ErrorAction SilentlyContinue) }
    return $null
}

# Write active profile marker
function Set-ActiveProfile {
    param([string]$Profile)
    $marker = Join-Path $MultiManageRoot '.active'
    if ($Profile) {
        Set-Content -Path $marker -Value $Profile
    } elseif (Test-Path $marker) {
        Remove-Item -Path $marker -Force
    }
}

# Enumerate available profiles (directories under MultiManage excluding special folders)
function Get-Profiles {
    $profiles = Get-ChildItem -Path $MultiManageRoot -Directory | Where-Object {
        $_.Name -notmatch '^\.' -and $_.Name -ne '_global' -and $_.Name -ne 'logs'
    } | Select-Object -ExpandProperty Name
    return $profiles
}

# Present a numbered list of profiles and return the chosen name
function Select-Profile {
    $profiles = Get-Profiles | Sort-Object
    if (-not $profiles) { Write-Host 'No profiles available'; return $null }
    for ($i = 0; $i -lt $profiles.Count; $i++) {
        Write-Host ("{0}) {1}" -f ($i + 1), $profiles[$i])
    }
    $choice = Read-Host 'Select profile number'
    if ($choice -match '^\d+$') {
        $idx = [int]$choice
        if ($idx -ge 1 -and $idx -le $profiles.Count) { return $profiles[$idx - 1] }
    }
    Write-Host 'Invalid selection'
    return $null
}

# Convert profile name to manifest path
function Get-ManifestPath {
    param([string]$Profile)
    return Join-Path (Join-Path $MultiManageRoot $Profile) '.manifest.json'
}
# endregion

# region Add mods for a profile
function Add-Mods {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [string]$Profile
    )
    $profilePath = Join-Path $MultiManageRoot $Profile
    if (-not (Test-Path $profilePath)) { Write-Log "Profile $Profile not found"; return }
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $manifest = @()
    $files = Get-ChildItem -Path $profilePath -Recurse -File
    foreach ($file in $files) {
        $relative = Get-RelativePath -Root $profilePath -FullPath $file.FullName
        $dest = Join-Path $GameRoot $relative
        $srcHash = Get-Hash $file.FullName
        $destHash = Get-Hash $dest
        if ($destHash -eq $srcHash) {
            Write-Log "Skip $relative (identical)"
            $manifest += [pscustomobject]@{Path=$relative;Hash=$srcHash}
            continue
        }
        if ($destHash -and $destHash -ne $srcHash) {
            Backup-File -FilePath $dest -Operation 'overwrite' -Timestamp $timestamp -WhatIf:$WhatIfPreference
        }
        New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
        if ($PSCmdlet.ShouldProcess($dest, "Copy $relative")) {
            Copy-Item -Path $file.FullName -Destination $dest -Force
        }
        $manifest += [pscustomobject]@{Path=$relative;Hash=$srcHash}
        Write-Log "Installed $relative"
    }
    $manifestPath = Get-ManifestPath -Profile $Profile
    if ($PSCmdlet.ShouldProcess($manifestPath, "Write manifest")) {
        $manifest | ConvertTo-Json | Set-Content -Path $manifestPath
    }
    Set-ActiveProfile -Profile $Profile
    Write-Log "Finished adding mods for $Profile"
}
# endregion

# region Remove mods for a profile
function Remove-Mods {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([string]$Profile)
    $manifestPath = Get-ManifestPath -Profile $Profile
    if (-not (Test-Path $manifestPath)) { Write-Log "Manifest missing for $Profile"; return }
    $manifest = Get-Content -Path $manifestPath | ConvertFrom-Json
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    foreach ($entry in $manifest) {
        $dest = Join-Path $GameRoot $entry.Path
        if (-not (Test-Path $dest)) {
            Write-Log "Missing $($entry.Path), nothing to remove"
            continue
        }
        $currentHash = Get-Hash $dest
        if ($currentHash -ne $entry.Hash) {
            Write-Log "Hash mismatch for $($entry.Path); skipping delete"
            continue
        }
        Backup-File -FilePath $dest -Operation 'delete' -Timestamp $timestamp -WhatIf:$WhatIfPreference
        if ($PSCmdlet.ShouldProcess($dest, "Delete $($entry.Path)")) {
            Remove-Item -Path $dest -Force
        }
        Write-Log "Removed $($entry.Path)"
    }
    # remove empty directories under standard roots
    Prune-EmptyDirs -Roots @(
        (Join-Path $GameRoot 'archive\pc\mod'),
        (Join-Path $GameRoot 'r6\scripts'),
        (Join-Path $GameRoot 'r6\tweaks')
    )
    if ((Get-ActiveProfile) -eq $Profile) { Set-ActiveProfile -Profile $null }
    Write-Log "Finished removing mods for $Profile"
}
# endregion

# region Status report
function Show-Status {
    param()
    $profiles = Get-ChildItem -Path $MultiManageRoot -Directory | Where-Object { $_.Name -notmatch '^\.' }
    foreach ($p in $profiles) {
        $manifestPath = Join-Path $p.FullName '.manifest.json'
        if (-not (Test-Path $manifestPath)) { continue }
        $manifest = Get-Content $manifestPath | ConvertFrom-Json
        $match=0;$missing=0;$diff=0
        foreach ($entry in $manifest) {
            $dest = Join-Path $GameRoot $entry.Path
            if (-not (Test-Path $dest)) { $missing++; continue }
            $hash = Get-Hash $dest
            if ($hash -eq $entry.Hash) { $match++ } else { $diff++ }
        }
        $status = if ($missing -eq 0 -and $diff -eq 0) { 'present' } elseif ($match -gt 0) { 'partial' } else { 'absent' }
        Write-Host "$($p.Name): $status (match=$match, diff=$diff, missing=$missing)"
    }
    $active = Get-ActiveProfile
    if ($active) { Write-Host "Active profile: $active" }
}
# endregion

# region Switch profile helper
function Switch-Profile {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([string]$NewProfile)
    $current = Get-ActiveProfile
    if ($current) {
        Write-Log "Switching: removing $current"
        Remove-Mods -Profile $current -WhatIf:$WhatIfPreference
    }
    Write-Log "Switching: adding $NewProfile"
    Add-Mods -Profile $NewProfile -WhatIf:$WhatIfPreference
}
# endregion

# region Restore last backup
function Restore-LastBackup {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param()
    $latest = Get-ChildItem -Path $BackupRoot -Directory | Sort-Object Name -Descending | Select-Object -First 1
    if (-not $latest) { Write-Log "No backups found"; return }
    Write-Log "Restoring backup from $($latest.Name)"
    $files = Get-ChildItem -Path $latest.FullName -Recurse -File
    foreach ($file in $files) {
        $relative = Get-RelativePath -Root $latest.FullName -FullPath $file.FullName
        $dest = Join-Path $GameRoot $relative
        New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
        if ($PSCmdlet.ShouldProcess($dest, "Restore $relative")) {
            Copy-Item -Path $file.FullName -Destination $dest -Force
        }
    }
}
# endregion

# region Sandbox setup and demo
function Setup-Sandbox {
    # Build dummy files for sandbox testing
    $dirs = @(
        (Join-Path $GameRoot 'archive\pc\mod'),
        (Join-Path $GameRoot 'r6\scripts'),
        (Join-Path $GameRoot 'r6\tweaks')
    )
    foreach ($d in $dirs) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
    # create MultiManage directories and profile
    $profile = Join-Path $MultiManageRoot 'Dummy'
    New-Item -ItemType Directory -Force -Path (Join-Path $profile 'archive\pc\mod') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $profile 'r6\scripts') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $profile 'r6\tweaks') | Out-Null
    # create dummy files
    Set-Content -Path (Join-Path $profile 'archive\pc\mod\dummy.archive') -Value 'dummy'
    Set-Content -Path (Join-Path $profile 'r6\scripts\dummy.lua') -Value 'print("hi")'
    Set-Content -Path (Join-Path $profile 'r6\tweaks\dummy.ini') -Value '[dummy]'
    Write-Host "Sandbox created under $SandboxRoot"
}

function Run-Sandbox {
    Setup-Sandbox
    Add-Mods -Profile 'Dummy'
    Remove-Mods -Profile 'Dummy'
    Add-Mods -Profile 'Dummy'
    Show-Status
    Write-Host "Sandbox verification complete"
}
# endregion

if ($Sandbox) {
    Run-Sandbox
    return
}

# region Interactive menu
while ($true) {
    $selection = Read-Host "`n`nWhat do you want to do?`n1) Add character mods`n2) Remove character mods`n3) Show current status`n4) Dry-run (no changes)`n5) Switch character`n6) Restore last backup`n7) Quit"
    switch ($selection) {
        '1' {
            $WhatIfPreference = $false
            $profile = Select-Profile
            if ($profile) {
                $confirm = Read-Host "Add mods for $profile? Y/N"
                if ($confirm -match '^[Yy]') { Add-Mods -Profile $profile }
            }
        }
        '2' {
            $WhatIfPreference = $false
            $profile = Select-Profile
            if ($profile) {
                $confirm = Read-Host "Remove mods for $profile? Y/N"
                if ($confirm -match '^[Yy]') { Remove-Mods -Profile $profile }
            }
        }
        '3' { Show-Status }
        '4' {
            $WhatIfPreference = $true
            $mode = Read-Host "Dry-run selected. Choose action: 1) Add 2) Remove 3) Status"
            $profile = $null
            if ($mode -eq '1' -or $mode -eq '2') { $profile = Select-Profile }
            switch ($mode) {
                '1' { if ($profile) { Add-Mods -Profile $profile -WhatIf } }
                '2' { if ($profile) { Remove-Mods -Profile $profile -WhatIf } }
                '3' { Show-Status }
            }
            $WhatIfPreference = $false
        }
        '5' {
            $WhatIfPreference = $false
            $profile = Select-Profile
            if ($profile) {
                $confirm = Read-Host "Switch to $profile? Y/N"
                if ($confirm -match '^[Yy]') { Switch-Profile -NewProfile $profile }
            }
        }
        '6' {
            Restore-LastBackup
        }
        '7' { break }
        default { Write-Host 'Invalid option' }
    }
}
# endregion
