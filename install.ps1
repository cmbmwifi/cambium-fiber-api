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

function Request-DocsAuth {
    Write-ColorOutput "Documentation Authentication Setup" -Level INFO
    Write-Host ""
    Write-ColorOutput "SECURITY: The /docs and /setup endpoints WILL be protected with HTTP Basic Authentication." -Level WARN
    Write-Host ""

    if ($env:DOCS_AUTH_ENABLED) {
        if ($env:DOCS_AUTH_ENABLED -eq "false") {
            Write-ColorOutput "DOCS_AUTH_ENABLED=false detected - documentation will be publicly accessible" -Level WARN
            $protectDocs = "N"
        }
        else {
            $protectDocs = "Y"
            Write-ColorOutput "Using DOCS_AUTH_ENABLED from environment: $protectDocs" -Level INFO
        }
    }
    else {
        Write-Host "Press ENTER to protect endpoints (recommended)"
        $disableProtection = Read-Host "Or type exactly 'I understand the risk' to disable protection"
        if ($disableProtection -eq "I understand the risk") {
            $protectDocs = "N"
        }
        else {
            $protectDocs = "Y"
        }
    }

    if ($protectDocs -match "^[Yy]") {
        if ($env:DOCS_USERNAME) {
            $docsUser = $env:DOCS_USERNAME
            Write-ColorOutput "Using DOCS_USERNAME from environment: $docsUser" -Level INFO
        }
        else {
            $docsUser = Read-Host "Enter username for /docs and /setup [admin]"
            if (-not $docsUser) {
                $docsUser = "admin"
            }
        }

        if ($env:DOCS_PASSWORD) {
            $docsPass = $env:DOCS_PASSWORD
            Write-ColorOutput "Using DOCS_PASSWORD from environment" -Level INFO
        }
        else {
            $securePass = Read-Host "Enter password" -AsSecureString
            $securePassConfirm = Read-Host "Confirm password" -AsSecureString

            $docsPass = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePass))
            $docsPassConfirm = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassConfirm))

            if ($docsPass -ne $docsPassConfirm) {
                Write-ColorOutput "Passwords do not match!" -Level ERROR
                exit 1
            }

            if (-not $docsPass) {
                Write-ColorOutput "Password cannot be empty!" -Level ERROR
                exit 1
            }
        }

        Write-ColorOutput "Generating password hash..." -Level INFO

        $escapedPass = $docsPass -replace "'", "''"
        $dockerCmd = "pip install -q bcrypt && python -c `"import bcrypt; print(bcrypt.hashpw('$escapedPass'.encode('utf-8'), bcrypt.gensalt()).decode('utf-8'))`""

        try {
            $docsHash = docker run --rm python:3.11-slim bash -c $dockerCmd 2>$null
            if ($LASTEXITCODE -ne 0 -or -not $docsHash) {
                throw "Docker command failed"
            }
        }
        catch {
            Write-ColorOutput "Failed to generate password hash" -Level ERROR
            exit 1
        }

        $script:docsAuthEnabled = $true
        $script:docsAuthUsername = $docsUser
        $script:docsAuthHash = $docsHash.Trim()

        Write-ColorOutput "✓ Documentation authentication configured" -Level INFO
    }
    else {
        $script:docsAuthEnabled = $false
        Write-ColorOutput "Documentation endpoints will be publicly accessible" -Level WARN
    }
    Write-Host ""
}

function New-ConnectionsFile {
    Write-ColorOutput "Creating connections configuration file..." -Level INFO

    $connectionsFile = "$InstallDir\connections.json"

    # Remove if it exists as a directory (from previous failed install)
    if (Test-Path $connectionsFile -PathType Container) {
        Write-ColorOutput "Removing stale connections.json directory from previous install" -Level WARN
        Remove-Item -Path $connectionsFile -Recurse -Force
    }

    if ($script:docsAuthEnabled) {
        $connectionsContent = @"
{
  "docs_auth": {
    "username": "$($script:docsAuthUsername)",
    "password_hash": "$($script:docsAuthHash)"
  }
}
"@
        Set-Content -Path $connectionsFile -Value $connectionsContent -Encoding UTF8
        Write-ColorOutput "connections.json created with documentation authentication" -Level INFO
    }
    else {
        Set-Content -Path $connectionsFile -Value "{}" -Encoding UTF8
        Write-ColorOutput "Empty connections.json created (will be configured via setup wizard)" -Level INFO
    }
}

function Test-Endpoint {
    param(
        [string]$Url,
        [string]$Name,
        [int]$MaxRetries = 3,
        [int[]]$AcceptableCodes = @(200)
    )

    $retryCount = 0
    while ($retryCount -lt $MaxRetries) {
        try {
            $response = Invoke-WebRequest -Uri $Url -Method Get -TimeoutSec 2 -ErrorAction Stop
            if ($AcceptableCodes -contains $response.StatusCode) {
                return $true
            }
        }
        catch [System.Net.WebException] {
            $statusCode = [int]$_.Exception.Response.StatusCode
            if ($AcceptableCodes -contains $statusCode) {
                return $true
            }
        }
        catch {
            # Continue to retry
        }
        $retryCount++
        if ($retryCount -lt $MaxRetries) {
            Start-Sleep -Seconds 1
        }
    }
    return $false
}

function Get-ContainerLogs {
    Write-ColorOutput "Checking container logs for errors..." -Level INFO
    Write-Host ""
    Write-Host "==================== Last 30 Log Lines ===================="
    docker logs --tail 30 cambium-fiber-api 2>&1 | ForEach-Object { Write-Host $_ }
    Write-Host "==========================================================="
    Write-Host ""
}

function Write-Troubleshooting {
    param([int]$ApiPort)

    Write-Host ""
    Write-ColorOutput "================================================================" -Level ERROR
    Write-ColorOutput "  Installation Incomplete - Endpoints Not Ready" -Level ERROR
    Write-ColorOutput "================================================================" -Level ERROR
    Write-Host ""
    Write-ColorOutput "Troubleshooting Steps:" -Level INFO
    Write-Host ""
    Write-ColorOutput "1. Check container status:" -Level INFO
    Write-ColorOutput "   docker ps -a | Select-String cambium-fiber-api" -Level INFO
    Write-Host ""
    Write-ColorOutput "2. View full logs:" -Level INFO
    Write-ColorOutput "   docker logs cambium-fiber-api" -Level INFO
    Write-Host ""
    Write-ColorOutput "3. Check for common issues:" -Level INFO
    Write-ColorOutput "   - Port $ApiPort already in use: netstat -ano | Select-String $ApiPort" -Level INFO
    Write-ColorOutput "   - Permissions on connections.json: Get-ChildItem $InstallDir\connections.json" -Level INFO
    Write-ColorOutput "   - Docker resources: docker system df" -Level INFO
    Write-Host ""
    Write-ColorOutput "4. Try restarting the container:" -Level INFO
    Write-ColorOutput "   cd $InstallDir" -Level INFO
    Write-ColorOutput "   docker compose down" -Level INFO
    Write-ColorOutput "   docker compose up -d" -Level INFO
    Write-Host ""
    Write-ColorOutput "5. Check Docker networking:" -Level INFO
    Write-ColorOutput "   curl http://localhost:$ApiPort/health -Verbose" -Level INFO
    Write-Host ""
    Write-ColorOutput "Common Issues:" -Level INFO
    Write-ColorOutput "  - If /health works but /docs fails: Check for Python import errors in logs" -Level INFO
    Write-ColorOutput "  - If connection refused: Container may not be running or port not exposed" -Level INFO
    Write-ColorOutput "  - If 500 errors: Check application logs for exceptions" -Level INFO
    Write-Host ""
    Write-ColorOutput "================================================================" -Level INFO
}

function Start-ApiContainer {
    Write-ColorOutput "Starting Cambium Fiber API..." -Level INFO

    Push-Location $InstallDir
    docker compose --env-file $EnvFile up -d
    Pop-Location

    # Read port from env file
    $envContent = Get-Content $EnvFile
    $portLine = $envContent | Where-Object { $_ -match "^CAMBIUM_API_PORT=" }
    $apiPort = $portLine -replace "^CAMBIUM_API_PORT=", ""

    Write-ColorOutput "Waiting for container to start..." -Level INFO
    Start-Sleep -Seconds 5

    # Check if container is actually running
    $containerRunning = docker ps | Select-String "cambium-fiber-api"
    if (-not $containerRunning) {
        Write-ColorOutput "Container failed to start!" -Level ERROR
        Get-ContainerLogs
        Write-Troubleshooting -ApiPort $apiPort
        exit 1
    }

    Write-ColorOutput "Validating endpoints..." -Level INFO

    # Track which endpoints work
    $script:healthOk = $false
    $script:docsOk = $false
    $script:setupOk = $false

    # Wait for health endpoint with retry
    $maxRetries = 30
    $retryCount = 0

    while ($retryCount -lt $maxRetries) {
        if (Test-Endpoint -Url "http://localhost:$apiPort/health" -Name "health" -MaxRetries 1) {
            $script:healthOk = $true
            break
        }
        Write-Host "." -NoNewline
        Start-Sleep -Seconds 2
        $retryCount++
    }
    Write-Host ""

    if (-not $script:healthOk) {
        Write-ColorOutput "✗ Health endpoint failed to respond" -Level ERROR
        Get-ContainerLogs
        Write-Troubleshooting -ApiPort $apiPort
        exit 1
    }

    # Now validate the other critical endpoints
    # If docs auth is enabled, 401 Unauthorized is expected and means endpoints are working
    $expectedDocsCodes = @(200)
    if ($script:docsAuthEnabled) {
        $expectedDocsCodes = @(200, 401)
    }

    if (Test-Endpoint -Url "http://localhost:$apiPort/docs" -Name "docs" -MaxRetries 3 -AcceptableCodes $expectedDocsCodes) {
        $script:docsOk = $true
    }
    else {
        Write-ColorOutput "✗ /docs endpoint is not responding or returning errors" -Level ERROR
        $script:docsOk = $false
    }

    if (Test-Endpoint -Url "http://localhost:$apiPort/setup" -Name "setup" -MaxRetries 3 -AcceptableCodes $expectedDocsCodes) {
        $script:setupOk = $true
    }
    else {
        Write-ColorOutput "✗ /setup endpoint is not responding or returning errors" -Level ERROR
        $script:setupOk = $false
    }

    # If any critical endpoint failed, show diagnostics and fail
    if (-not $script:docsOk -or -not $script:setupOk) {
        Write-Host ""
        Write-ColorOutput "Critical endpoints are not responding correctly!" -Level ERROR
        Write-ColorOutput "Getting diagnostic information..." -Level INFO
        Get-ContainerLogs

        # Test each endpoint manually to get detailed error info
        Write-Host ""
        Write-ColorOutput "Detailed endpoint testing:" -Level INFO
        foreach ($endpoint in @("health", "docs", "setup")) {
            Write-Host ""
            Write-ColorOutput "Testing /$endpoint:" -Level INFO
            try {
                $response = Invoke-WebRequest -Uri "http://localhost:$apiPort/$endpoint" -Method Get -TimeoutSec 5 -ErrorAction Stop
                Write-Host "Status: $($response.StatusCode)"
            }
            catch {
                Write-Host "Error: $($_.Exception.Message)"
            }
        }

        Write-Troubleshooting -ApiPort $apiPort
        exit 1
    }

    Write-ColorOutput "✓ Ready" -Level INFO
}

function Open-SetupWizard {
    # Check if browser should be opened (skip for headless/CI environments)
    # If OPEN_BROWSER is set (uncommented), skip browser open
    if ($env:OPEN_BROWSER) {
        return
    }

    # Read port from env file
    $envContent = Get-Content $EnvFile
    $portLine = $envContent | Where-Object { $_ -match "^CAMBIUM_API_PORT=" }
    $apiPort = $portLine -replace "^CAMBIUM_API_PORT=", ""

    $setupUrl = "http://localhost:$apiPort/setup"

    try {
        Start-Process $setupUrl
    }
    catch {
        # Silently fail
    }
}

function Write-Success {
    # Read port from env file
    $envContent = Get-Content $EnvFile
    $portLine = $envContent | Where-Object { $_ -match "^CAMBIUM_API_PORT=" }
    $apiPort = $portLine -replace "^CAMBIUM_API_PORT=", ""

    Write-Host ""
    Write-Host "================================================================"
    Write-Host "  ✓ Installation Complete!"
    Write-Host "================================================================"
    Write-Host ""
    Write-Host "  Next: Open http://localhost:$apiPort/setup to configure your OLTs"
    Write-Host ""
    Write-Host "  API Documentation: http://localhost:$apiPort/docs"
    Write-Host "  View Logs: docker logs -f cambium-fiber-api"
    Write-Host ""
    Write-Host "================================================================"
    Write-Host ""
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
    Request-DocsAuth
    New-ConnectionsFile
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
