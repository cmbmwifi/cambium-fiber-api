# Cambium Fiber API - Windows Installer
# Self-contained PowerShell installer script for Docker-based deployment
# Usage: Invoke-WebRequest -Uri https://raw.githubusercontent.com/USERNAME/REPO/main/install.ps1 -OutFile install.ps1; .\install.ps1

param(
    [string]$Version = "latest",
    [int]$Port = 8000,
    [string]$InstallDir = "$env:LOCALAPPDATA\Cambium\cambium-fiber-api"
)

# Load .env if it exists (for non-interactive installs)
if (Test-Path ".env") {
    Get-Content ".env" | ForEach-Object {
        if ($_ -match '^\s*([^#][^=]+)=(.*)$') {
            $name = $matches[1].Trim()
            $value = $matches[2].Trim()
            Set-Item -Path "env:$name" -Value $value
        }
    }
}

# Configuration
$ComposeFile = "$InstallDir\docker-compose.yml"
$EnvFile = "$InstallDir\.env"

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

function Test-Docker {
    Write-ColorOutput "Checking Docker installation..." -Level INFO

    try {
        $dockerVersion = docker --version
        if ($LASTEXITCODE -ne 0) {
            throw "Docker command failed"
        }
    }
    catch {
        Write-ColorOutput "Docker is not installed" -Level ERROR
        Write-ColorOutput "Please install Docker Desktop from: https://www.docker.com/products/docker-desktop" -Level INFO
        exit 1
    }

    try {
        docker info | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Docker daemon not running"
        }
    }
    catch {
        Write-ColorOutput "Docker daemon is not running" -Level ERROR
        Write-ColorOutput "Please start Docker Desktop and try again" -Level INFO
        exit 1
    }

    Write-ColorOutput "Docker is ready ($dockerVersion)" -Level INFO
}

function Test-DockerCompose {
    Write-ColorOutput "Checking Docker Compose..." -Level INFO

    try {
        $composeVersion = docker compose version
        if ($LASTEXITCODE -ne 0) {
            throw "Docker Compose command failed"
        }
    }
    catch {
        Write-ColorOutput "Docker Compose is not available" -Level ERROR
        Write-ColorOutput "Please install Docker Compose v2 or Docker Desktop" -Level INFO
        exit 1
    }

    Write-ColorOutput "Docker Compose is ready ($composeVersion)" -Level INFO
}

function New-InstallDirectory {
    Write-ColorOutput "Creating installation directory: $InstallDir" -Level INFO

    if (-not (Test-Path $InstallDir)) {
        try {
            New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
        }
        catch {
            Write-ColorOutput "Failed to create directory. Please run PowerShell as Administrator." -Level ERROR
            exit 1
        }
    Write-ColorOutput "Creating docker-compose.yml..." -Level INFO

    $composeContent = @'
version: '3.8'

services:
  cambium-fiber-api:
    image: ${CAMBIUM_API_IMAGE:-cambium-fiber-api:latest}
    container_name: cambium-fiber-api
    ports:
      - "${CAMBIUM_API_PORT:-8000}:8000"
    volumes:
      - ${CAMBIUM_CONFIG_PATH:-./connections.json}:/app/connections.json${CAMBIUM_CONFIG_MODE:-}
      - api-data:/app/data
      - api-logs:/app/logs
      - api-backups:/app/backups
    environment:
      - ENABLE_SETUP_WIZARD=${ENABLE_SETUP_WIZARD:-true}
      - OAUTH_CLIENT_ID=${OAUTH_CLIENT_ID:-}
      - OAUTH_CLIENT_SECRET=${OAUTH_CLIENT_SECRET:-}
      - SSL_CERT_PATH=${SSL_CERT_PATH:-}
      - SSL_KEY_PATH=${SSL_KEY_PATH:-}
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "wget", "--spider", "--quiet", "http://localhost:8000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

volumes:
  api-data:
    driver: local
  api-logs:
    driver: local
  api-backups:
    driver: local
'@

    Set-Content -Path $ComposeFile -Value $composeContent -Encoding UTF8
    Write-ColorOutput "docker-compose.yml created" -Level INFO
}

function New-EnvFile {
    Write-ColorOutput "Creating environment configuration..." -Level INFO

    # Check for local tarball to suggest version
    $suggestedVersion = "latest"
    $tarball = Get-ChildItem -Path . -Filter "cambium-fiber-api-*.tar*" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($tarball) {
        # Extract version from tarball filename (e.g., cambium-fiber-api-1.0.0-beta.1.tar.gz -> 1.0.0-beta.1)
        if ($tarball.Name -match "cambium-fiber-api-(.+)\.tar") {
            $detectedVersion = $Matches[1]
            $suggestedVersion = $detectedVersion
            Write-ColorOutput "Found local tarball with version: $detectedVersion" -Level INFO
        }
    }

    # Check for environment variables, prompt if not set (non-interactive mode)
    if ($env:VERSION) {
        $Version = $env:VERSION
        Write-ColorOutput "Using version from VERSION: $Version" -Level INFO
    }
    elseif ($Version -eq "latest") {
        $userVersion = Read-Host "Enter version to install [$suggestedVersion]"
        if ($userVersion) {
            $Version = $userVersion
        }
        else {
            $Version = $suggestedVersion
        }
    }

    if ($env:API_PORT) {
        $Port = [int]$env:API_PORT
        Write-ColorOutput "Using port from API_PORT: $Port" -Level INFO
    }
    elseif ($Port -eq 8000) {
        $userPort = Read-Host "Enter port to expose API [8000]"
        if ($userPort) {
            $Port = [int]$userPort
        }
    }

    $envContent = @"
# Cambium Fiber API Configuration
CAMBIUM_API_IMAGE=cambium-fiber-api:$Version
CAMBIUM_API_PORT=$Port
ENABLE_SETUP_WIZARD=$(if ($env:ENABLE_SETUP_WIZARD) { $env:ENABLE_SETUP_WIZARD } else { 'true' })
OAUTH_CLIENT_ID=$(if ($env:OAUTH_CLIENT_ID) { $env:OAUTH_CLIENT_ID } else { '' })
OAUTH_CLIENT_SECRET=$(if ($env:OAUTH_CLIENT_SECRET) { $env:OAUTH_CLIENT_SECRET } else { '' })
SSL_CERT_PATH=$(if ($env:SSL_CERT_PATH) { $env:SSL_CERT_PATH } else { '' })
SSL_KEY_PATH=$(if ($env:SSL_KEY_PATH) { $env:SSL_KEY_PATH } else { '' })
"@

    Set-Content -Path $EnvFile -Value $envContent -Encoding UTF8
    Write-ColorOutput "Environment file created: $EnvFile" -Level INFO
}

function Import-DockerImage {
    Write-ColorOutput "Checking for Docker image..." -Level INFO

    # Read env file to get desired IMAGE variable
    $envContent = Get-Content $EnvFile
    $imageLine = $envContent | Where-Object { $_ -match "^CAMBIUM_API_IMAGE=" }
    $desiredImage = $imageLine -replace "^CAMBIUM_API_IMAGE=", ""

    # Check if tarball exists in current directory
    $tarball = Get-ChildItem -Path . -Filter "cambium-fiber-api-*.tar*" | Select-Object -First 1

    if ($tarball) {
        Write-ColorOutput "Found local tarball: $($tarball.Name)" -Level INFO
        Write-ColorOutput "Loading Docker image from tarball..." -Level INFO

        # Extract version from tarball filename
        $tarballVersion = ""
        if ($tarball.Name -match "cambium-fiber-api-(.+)\.tar") {
            $tarballVersion = $Matches[1]
        }

        if ($tarball.Extension -eq ".gz") {
            # Decompress and load
            $tempTar = "$env:TEMP\cambium-temp.tar"

            # Use 7-Zip if available, otherwise use .NET
            if (Get-Command 7z -ErrorAction SilentlyContinue) {
                7z x $tarball.FullName -o"$env:TEMP" -y | Out-Null
                docker load -i $tempTar
            }
            else {
                Write-ColorOutput "Please decompress $($tarball.Name) manually and run: docker load -i <tarfile>" -Level WARN
                return
            }

            Remove-Item $tempTar -ErrorAction SilentlyContinue
        }
        else {
            docker load -i $tarball.FullName
        }

        if ($LASTEXITCODE -eq 0) {
            Write-ColorOutput "Image loaded successfully" -Level INFO

            # Re-tag the loaded image to match the requested version if different
            if ($tarballVersion -and $desiredImage -ne "cambium-fiber-api:$tarballVersion") {
                Write-ColorOutput "Tagging image as: $desiredImage" -Level INFO
                docker tag "cambium-fiber-api:$tarballVersion" $desiredImage
            }
        }
        else {
            Write-ColorOutput "Failed to load image from tarball" -Level ERROR
            exit 1
        }
    }
    else {
        Write-ColorOutput "No local tarball found - pulling from registry" -Level WARN
        Write-ColorOutput "Pulling Docker image..." -Level INFO

        docker pull $desiredImage

        if ($LASTEXITCODE -eq 0) {
            Write-ColorOutput "Image pulled successfully" -Level INFO
        }
        else {
            Write-ColorOutput "Failed to pull image from registry" -Level ERROR
            Write-ColorOutput "Please download the tarball manually or check registry access" -Level INFO
            exit 1
        }
    }
}

function Start-ApiContainer {
    Write-ColorOutput "Starting Cambium Fiber API..." -Level INFO

    Push-Location $InstallDir
    docker compose --env-file $EnvFile up -d
    Pop-Location

    Write-ColorOutput "Waiting for API to be ready..." -Level INFO

    # Read port from env file
    $envContent = Get-Content $EnvFile
    $portLine = $envContent | Where-Object { $_ -match "^CAMBIUM_API_PORT=" }
    $apiPort = $portLine -replace "^CAMBIUM_API_PORT=", ""

    $healthUrl = "http://localhost:$apiPort/health"
    $maxRetries = 30
    $retryCount = 0

    while ($retryCount -lt $maxRetries) {
        try {
            $response = Invoke-WebRequest -Uri $healthUrl -Method Get -TimeoutSec 2 -ErrorAction SilentlyContinue
            if ($response.StatusCode -eq 200) {
                Write-ColorOutput "API is ready!" -Level INFO
                return
            }
        }
        catch {
            # Ignore and retry
        }

        Write-Host "." -NoNewline
        Start-Sleep -Seconds 2
        $retryCount++
    }

    Write-Host ""
    Write-ColorOutput "API did not become ready within expected time" -Level WARN
    Write-ColorOutput "Check logs with: docker logs cambium-fiber-api" -Level INFO
}

function Open-SetupWizard {
    # Check if browser should be opened (skip for headless/CI environments)
    # If OPEN_BROWSER is set (uncommented), skip browser open
    if ($env:OPEN_BROWSER) {
        Write-ColorOutput "Skipping browser open (headless mode: OPEN_BROWSER is set)" -Level INFO
        # Read port from env file
        $envContent = Get-Content $EnvFile
        $portLine = $envContent | Where-Object { $_ -match "^CAMBIUM_API_PORT=" }
        $apiPort = $portLine -replace "^CAMBIUM_API_PORT=", ""
        $setupUrl = "http://localhost:$apiPort/setup"
        Write-ColorOutput "Setup wizard URL: $setupUrl" -Level INFO
        return
    }

    # Read port from env file
    $envContent = Get-Content $EnvFile
    $portLine = $envContent | Where-Object { $_ -match "^CAMBIUM_API_PORT=" }
    $apiPort = $portLine -replace "^CAMBIUM_API_PORT=", ""

    $setupUrl = "http://localhost:$apiPort/setup"

    Write-ColorOutput "Opening setup wizard in browser..." -Level INFO

    try {
        Start-Process $setupUrl
        Write-ColorOutput "Setup wizard opened at: $setupUrl" -Level INFO
    }
    catch {
        Write-ColorOutput "Could not auto-open browser" -Level WARN
        Write-ColorOutput "Please open this URL manually: $setupUrl" -Level INFO
    }
}

function Write-Success {
    # Read port from env file
    $envContent = Get-Content $EnvFile
    $portLine = $envContent | Where-Object { $_ -match "^CAMBIUM_API_PORT=" }
    $apiPort = $portLine -replace "^CAMBIUM_API_PORT=", ""

    Write-Host ""
    Write-ColorOutput "================================================================" -Level INFO
    Write-ColorOutput "  Cambium Fiber API Installation Complete!" -Level INFO
    Write-ColorOutput "================================================================" -Level INFO
    Write-Host ""

    Write-ColorOutput "Installation directory: $InstallDir" -Level INFO
    Write-ColorOutput "API URL: http://localhost:$apiPort" -Level INFO
    Write-ColorOutput "Setup wizard: http://localhost:$apiPort/setup" -Level INFO
    Write-ColorOutput "API docs: http://localhost:$apiPort/docs" -Level INFO
    Write-Host ""
    Write-ColorOutput "Common commands:" -Level INFO
    Write-ColorOutput "  Start:   cd $InstallDir; docker compose up -d" -Level INFO
    Write-ColorOutput "  Stop:    cd $InstallDir; docker compose down" -Level INFO
    Write-ColorOutput "  Logs:    docker logs -f cambium-fiber-api" -Level INFO
    Write-ColorOutput "  Status:  docker ps | Select-String cambium-fiber-api" -Level INFO
    Write-Host ""
    Write-ColorOutput "Complete the setup wizard to configure your OLT connections" -Level INFO
    Write-ColorOutput "================================================================" -Level INFO
}

# Main installation flow
function Main {
    Write-Host ""
    Write-ColorOutput "Cambium Fiber API - Windows Installer" -Level INFO
    Write-ColorOutput "====================================" -Level INFO
    Write-Host ""

    Test-Docker
    Test-DockerCompose
    New-InstallDirectory
    New-ComposeFile
    New-EnvFile
    Import-DockerImage
    Start-ApiContainer
    Open-SetupWizard
    Write-Success
}

# Run main installation
try {
    Main
}
catch {
    Write-ColorOutput "Installation failed: $_" -Level ERROR
    exit 1
}
