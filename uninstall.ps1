# Cambium Fiber API - Windows Uninstaller
# Removes installed Cambium Fiber API components
# Usage: .\uninstall.ps1

param(
    [string]$InstallDir = "$env:ProgramData\Cambium\cambium-fiber-api"
)

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host "This script requires PowerShell 7 or newer (current: $($PSVersionTable.PSVersion))." -ForegroundColor Red
    Write-Host "Install PowerShell 7: https://learn.microsoft.com/en-us/powershell/scripting/install/install-powershell-on-windows" -ForegroundColor Yellow
    exit 1
}

$ContainerName = "cambium-fiber-api"
$ImageName = "cambium-fiber-api"

# --- Windows Forms GUI (always available on Windows) ---
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
$script:HAS_GUI = $true

# ============================================================
# UI helpers
# ============================================================

function UI-Banner {
    param([string]$Title, [string]$Subtitle)
    $msg = $Title
    if ($Subtitle) { $msg += "`n`n$Subtitle" }
    [System.Windows.Forms.MessageBox]::Show($msg, "Cambium Fiber API",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
}

function UI-Confirm {
    param([string]$Prompt, [bool]$DefaultYes = $false)
    $result = [System.Windows.Forms.MessageBox]::Show($Prompt, "Cambium Fiber API",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question)
    return ($result -eq [System.Windows.Forms.DialogResult]::Yes)
}

function Write-ColorOutput {
    param([Parameter(Mandatory=$true)][string]$Message, [string]$Level = "INFO")
    $color = switch($Level) { "ERROR" { "Red" } "WARN" { "Yellow" } "INFO" { "Green" } default { "White" } }
    Write-Host "[$Level] $Message" -ForegroundColor $color
}

function Confirm-Action {
    param([Parameter(Mandatory=$true)][string]$Prompt, [string]$Default = "N")
    return UI-Confirm -Prompt $Prompt -DefaultYes ($Default -eq "Y")
}

# ============================================================
# Docker helpers
# ============================================================

function Test-DockerAvailable {
    try {
        docker --version | Out-Null
        if ($LASTEXITCODE -ne 0) { return $false }
        docker info | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-ColorOutput "Docker daemon not running -- some cleanup may be skipped" -Level WARN
            return $false
        }
        return $true
    } catch {
        Write-ColorOutput "Docker command not found -- assuming already uninstalled" -Level WARN
        return $false
    }
}

# ============================================================
# Removal functions
# ============================================================

function Stop-AndRemoveContainer {
    Write-ColorOutput "Checking for running containers..." -Level INFO
    if (-not (Test-DockerAvailable)) { return }

    $containerExists = docker ps -a --format "{{.Names}}" | Where-Object { $_ -eq $ContainerName }
    if ($containerExists) {
        Write-ColorOutput "Stopping and removing container: $ContainerName" -Level INFO
        $running = docker ps --format "{{.Names}}" | Where-Object { $_ -eq $ContainerName }
        if ($running) { docker stop $ContainerName 2>&1 | Out-Null }
        docker rm $ContainerName 2>&1 | Out-Null
        Write-ColorOutput "Container removed" -Level INFO
    } else {
        Write-ColorOutput "Container not found (already removed)" -Level INFO
    }

    $volumes = docker volume ls --format "{{.Name}}" | Where-Object { $_ -match 'cambium.*api' }
    if ($volumes) {
        foreach ($v in $volumes) {
            Write-ColorOutput "Removing volume: $v" -Level INFO
            docker volume rm $v 2>&1 | Out-Null
        }
    }
}

function Remove-DockerImages {
    if (-not (Test-DockerAvailable)) { return }
    $images = docker images $ImageName --format "{{.Repository}}" | Where-Object { $_ -eq $ImageName }
    if ($images) {
        Write-ColorOutput "Removing Docker images..." -Level INFO
        docker images $ImageName --format "{{.Repository}}:{{.Tag}}" | ForEach-Object { docker rmi $_ 2>&1 | Out-Null }
        Write-ColorOutput "Images removed" -Level INFO
    } else {
        Write-ColorOutput "No images found for $ImageName" -Level INFO
    }
}

function Remove-DataDirectory {
    if (Test-Path $InstallDir) {
        Write-ColorOutput "Removing directory: $InstallDir" -Level INFO
        try {
            Remove-Item -Path $InstallDir -Recurse -Force -ErrorAction Stop
            Write-ColorOutput "Directory removed" -Level INFO
        } catch {
            Write-ColorOutput "Failed to remove directory: $_" -Level ERROR
        }
    } else {
        Write-ColorOutput "Directory not found (already removed)" -Level INFO
    }
}

# ============================================================
# Summary
# ============================================================

function Write-Summary {
    $remainsCount = 0
    $lines = @()

    $containerExists = $null
    if (Test-DockerAvailable) {
        $containerExists = docker ps -a --format "{{.Names}}" 2>$null | Where-Object { $_ -eq $ContainerName }
    }
    if ($containerExists) { $lines += "Container still exists: $ContainerName"; $remainsCount++ }
    else { $lines += "Container removed" }

    $imageExists = $null
    if (Test-DockerAvailable) {
        $imageExists = docker images --format "{{.Repository}}" 2>$null | Where-Object { $_ -eq $ImageName }
    }
    if ($imageExists) { $lines += "Image still exists: $ImageName"; $remainsCount++ }
    else { $lines += "Image removed" }

    if (Test-Path $InstallDir) { $lines += "Directory still exists: $InstallDir"; $remainsCount++ }
    else { $lines += "Directory removed" }

    # Console output
    Write-Host ""
    foreach ($l in $lines) { Write-ColorOutput "  $l" -Level $(if ($l -match "still exists") { "WARN" } else { "INFO" }) }
    Write-Host ""
    Write-ColorOutput "Docker Desktop was not affected by this uninstallation" -Level INFO

    # GUI dialog
    if ($script:HAS_GUI) {
        $msg = "Uninstallation Complete`n`n"
        if ($remainsCount -eq 0) { $msg += "All components successfully removed." }
        else { $msg += "Some components could not be removed.`n`n" + ($lines -join "`n") }
        [System.Windows.Forms.MessageBox]::Show($msg, "Cambium Fiber API",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    }
}

# ============================================================
# Main
# ============================================================

function Main {
    if (-not (Confirm-Action -Prompt "Continue with the uninstallation?`n`nThis removes the API container and its local data only.`nNo changes will be made to the OLT, OSS/BSS, or subscribers." -Default "Y")) {
        Write-ColorOutput "Uninstallation cancelled" -Level INFO
        exit 0
    }

    Stop-AndRemoveContainer
    Remove-DockerImages
    Remove-DataDirectory
    Write-Summary
}

try { Main }
catch {
    Write-ColorOutput "Uninstallation failed: $_" -Level ERROR
    [System.Windows.Forms.MessageBox]::Show("Uninstallation failed:`n`n$_", "Cambium Fiber API",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    exit 1
}
