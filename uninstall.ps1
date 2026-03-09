# Cambium Fiber API - Windows Uninstaller
# Removes installed Cambium Fiber API components
# Usage: .\uninstall.ps1

param(
    [string]$InstallDir = "$env:LOCALAPPDATA\Cambium\cambium-fiber-api"
)

# Configuration
$ContainerName = "cambium-fiber-api"
$ImageName = "cambium-fiber-api"

# Functions
function Write-ColorOutput {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [Parameter(Mandatory=$false)]
        [string]$Level = "INFO"
    )

    $color = switch($Level) {
        "ERROR" { "Red" }
        "WARN"  { "Yellow" }
        "INFO"  { "Green" }
        default { "White" }
    }

    Write-Host "[$Level] $Message" -ForegroundColor $color
}

function Confirm-Action {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Prompt,
        [Parameter(Mandatory=$false)]
        [string]$Default = "N"
    )

    if ($Default -eq "Y") {
        $promptText = "$Prompt [Y/n]: "
        $defaultResponse = "Y"
    }
    else {
        $promptText = "$Prompt [y/N]: "
        $defaultResponse = "N"
    }

    $response = Read-Host $promptText
    if ([string]::IsNullOrWhiteSpace($response)) {
        $response = $defaultResponse
    }

    return ($response -match '^[yY]')
}

function Test-DockerAvailable {
    try {
        docker --version | Out-Null
        if ($LASTEXITCODE -ne 0) {
            return $false
        }

        docker info | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-ColorOutput "Docker daemon not running - some cleanup may be skipped" -Level WARN
            return $false
        }

        return $true
    }
    catch {
        Write-ColorOutput "Docker command not found - assuming already uninstalled" -Level WARN
        return $false
    }
}

function Stop-AndRemoveContainer {
    Write-ColorOutput "Checking for running containers..." -Level INFO

    if (-not (Test-DockerAvailable)) {
        Write-ColorOutput "Skipping container removal (Docker not available)" -Level WARN
        return
    }

    # Check if container exists
    $containerExists = docker ps -a --format "{{.Names}}" | Where-Object { $_ -eq $ContainerName }

    if ($containerExists) {
        Write-ColorOutput "Stopping and removing container: $ContainerName" -Level INFO

        # Stop container if running
        $containerRunning = docker ps --format "{{.Names}}" | Where-Object { $_ -eq $ContainerName }
        if ($containerRunning) {
            docker stop $ContainerName 2>&1 | Out-Null
        }

        # Remove container
        docker rm $ContainerName 2>&1 | Out-Null

        Write-ColorOutput "Container removed" -Level INFO
    }
    else {
        Write-ColorOutput "Container not found (already removed or never created)" -Level INFO
    }

    # Check and remove orphaned volumes
    Write-ColorOutput "Checking for Docker volumes..." -Level INFO
    $volumes = docker volume ls --format "{{.Name}}" | Where-Object { $_ -match 'cambium.*api' }

    if ($volumes) {
        if (Confirm-Action -Prompt "Remove associated Docker volumes (data, logs, backups)?" -Default "Y") {
            foreach ($volume in $volumes) {
                Write-ColorOutput "Removing volume: $volume" -Level INFO
                docker volume rm $volume 2>&1 | Out-Null
            }
        }
        else {
            Write-ColorOutput "Keeping Docker volumes" -Level INFO
        }
    }
}

function Remove-DockerImages {
    if (-not (Test-DockerAvailable)) {
        Write-ColorOutput "Skipping image removal (Docker not available)" -Level WARN
        return
    }

    # Check if image exists (any tag)
    $images = docker images $ImageName --format "{{.Repository}}" | Where-Object { $_ -eq $ImageName }

    if ($images) {
        Write-Host ""
        Write-ColorOutput "Docker image(s) found:" -Level WARN
        docker images $ImageName --format "  - {{.Repository}}:{{.Tag}} ({{.Size}})" | ForEach-Object { Write-Host $_ }
        Write-Host ""

        if (Confirm-Action -Prompt "Remove Docker image(s)?" -Default "Y") {
            Write-ColorOutput "Removing Docker images..." -Level INFO
            $imageTags = docker images $ImageName --format "{{.Repository}}:{{.Tag}}"
            foreach ($imageTag in $imageTags) {
                docker rmi $imageTag 2>&1 | Out-Null
            }
            Write-ColorOutput "Docker image(s) removed" -Level INFO
        }
        else {
            Write-ColorOutput "Keeping Docker image(s)" -Level INFO
        }
    }
    else {
        Write-ColorOutput "No Docker images found for $ImageName" -Level INFO
    }
}

function Remove-DataDirectory {
    if (Test-Path $InstallDir) {
        Write-Host ""
        Write-ColorOutput "Installation directory found: $InstallDir" -Level WARN

        # Show disk usage
        try {
            $size = (Get-ChildItem -Path $InstallDir -Recurse -ErrorAction SilentlyContinue |
                     Measure-Object -Property Length -Sum).Sum
            $sizeMB = [math]::Round($size / 1MB, 2)
            Write-ColorOutput "Directory size: $sizeMB MB" -Level INFO
        }
        catch {
            # Ignore errors calculating size
        }

        Write-Host ""
        if (Confirm-Action -Prompt "Remove installation directory and all data?" -Default "Y") {
            Write-ColorOutput "Removing $InstallDir..." -Level INFO

            try {
                Remove-Item -Path $InstallDir -Recurse -Force -ErrorAction Stop
                Write-ColorOutput "Directory removed" -Level INFO
            }
            catch {
                Write-ColorOutput "Failed to remove directory: $_" -Level ERROR
                Write-ColorOutput "You may need to close any programs using files in this directory" -Level WARN
            }
        }
        else {
            Write-ColorOutput "Keeping installation directory" -Level INFO
            Write-ColorOutput "You can manually remove it later with: Remove-Item -Path '$InstallDir' -Recurse -Force" -Level INFO
        }
    }
    else {
        Write-ColorOutput "Installation directory not found (already removed or never created)" -Level INFO
    }
}

function Write-Summary {
    Write-Host ""
    Write-ColorOutput "================================================================" -Level INFO
    Write-ColorOutput "  Cambium Fiber API Uninstallation Complete" -Level INFO
    Write-ColorOutput "================================================================" -Level INFO
    Write-Host ""
    Write-ColorOutput "Summary:" -Level INFO

    # Check what remains
    $remainsCount = 0

    $containerExists = $null
    if (Test-DockerAvailable) {
        $containerExists = docker ps -a --format "{{.Names}}" 2>$null | Where-Object { $_ -eq $ContainerName }
    }

    if ($containerExists) {
        Write-ColorOutput "  ✗ Container still exists: $ContainerName" -Level WARN
        $remainsCount++
    }
    else {
        Write-ColorOutput "  ✓ Container removed" -Level INFO
    }

    $imageExists = $null
    if (Test-DockerAvailable) {
        $imageExists = docker images --format "{{.Repository}}" 2>$null | Where-Object { $_ -eq $ImageName }
    }

    if ($imageExists) {
        Write-ColorOutput "  ✗ Docker image still exists: $ImageName" -Level WARN
        $remainsCount++
    }
    else {
        Write-ColorOutput "  ✓ Docker image removed" -Level INFO
    }

    if (Test-Path $InstallDir) {
        Write-ColorOutput "  ✗ Installation directory still exists: $InstallDir" -Level WARN
        $remainsCount++
    }
    else {
        Write-ColorOutput "  ✓ Installation directory removed" -Level INFO
    }

    Write-Host ""

    if ($remainsCount -eq 0) {
        Write-ColorOutput "All components successfully removed" -Level INFO
    }
    else {
        Write-ColorOutput "Some components were kept (by your choice or due to errors)" -Level WARN
    }

    Write-Host ""
    Write-ColorOutput "Docker Desktop was not affected by this uninstallation" -Level INFO
    Write-ColorOutput "================================================================" -Level INFO
}

# Main uninstallation flow
function Main {
    Write-Host ""
    Write-ColorOutput "Cambium Fiber API - Windows Uninstaller" -Level INFO
    Write-ColorOutput "======================================" -Level INFO
    Write-Host ""

    Write-ColorOutput "This will remove Cambium Fiber API from your system" -Level WARN
    Write-Host ""

    if (-not (Confirm-Action -Prompt "Continue with uninstallation?" -Default "Y")) {
        Write-ColorOutput "Uninstallation cancelled" -Level INFO
        exit 0
    }

    Write-Host ""
    Stop-AndRemoveContainer
    Remove-DockerImages
    Remove-DataDirectory
    Write-Summary
}

# Run main uninstallation
try {
    Main
}
catch {
    Write-ColorOutput "Uninstallation failed: $_" -Level ERROR
    exit 1
}
