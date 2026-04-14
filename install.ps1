# Cambium Fiber API - Windows Installer
# Self-contained PowerShell installer script for Docker-based deployment
# Usage: Invoke-WebRequest -Uri https://raw.githubusercontent.com/USERNAME/REPO/main/install.ps1 -OutFile install.ps1; .\install.ps1

param(
    [string]$Version = "latest",
    [int]$Port = 8192,
    [string]$InstallDir = "$env:ProgramData\Cambium\cambium-fiber-api"
)

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host "This script requires PowerShell 7 or newer (current: $($PSVersionTable.PSVersion))." -ForegroundColor Red
    Write-Host "Install PowerShell 7: https://learn.microsoft.com/en-us/powershell/scripting/install/install-powershell-on-windows" -ForegroundColor Yellow
    exit 1
}

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

$ComposeFile = "$InstallDir\docker-compose.yml"
$EnvFile = "$InstallDir\.env"

# --- Windows Forms GUI (always available on Windows) ---
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
$script:HAS_GUI = $true

# ============================================================
# GUI: Single wizard form -- collects all inputs in one window
# ============================================================

function Show-InstallerWizard {
    # Auto-detect version from local tarball
    $suggestedVersion = $Version
    $tarball = Get-ChildItem -Path . -Filter "cambium-fiber-api-*.tar*" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($tarball -and $tarball.Name -match "cambium-fiber-api-(.+)\.tar") {
        $suggestedVersion = $Matches[1]
    }

    # Skip wizard entirely if all values provided via env vars
    if ($env:VERSION) { $suggestedVersion = $env:VERSION }
    if ($env:API_PORT) { $Port = [int]$env:API_PORT }
    if ($env:VERSION -and $env:API_PORT -and $env:DOCS_AUTH_ENABLED) {
        return @{
            Version  = $suggestedVersion
            Port     = $Port
            DocsAuth = ($env:DOCS_AUTH_ENABLED -ne "false")
            Username = $(if ($env:DOCS_USERNAME) { $env:DOCS_USERNAME } else { "admin" })
            Password = $(if ($env:DOCS_PASSWORD) { $env:DOCS_PASSWORD } else { "" })
        }
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Cambium Fiber API Installer"
    $form.Size = New-Object System.Drawing.Size(480, 430)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $y = 15

    # Header
    $header = New-Object System.Windows.Forms.Label
    $header.Text = "Cambium Fiber API"
    $header.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $header.Location = New-Object System.Drawing.Point(15, $y)
    $header.AutoSize = $true
    $form.Controls.Add($header)
    $y += 35

    $sub = New-Object System.Windows.Forms.Label
    $sub.Text = "Configure your installation settings below."
    $sub.ForeColor = [System.Drawing.Color]::Gray
    $sub.Location = New-Object System.Drawing.Point(15, $y)
    $sub.AutoSize = $true
    $form.Controls.Add($sub)
    $y += 30

    # Separator
    $sep1 = New-Object System.Windows.Forms.Label
    $sep1.BorderStyle = "Fixed3D"
    $sep1.Location = New-Object System.Drawing.Point(15, $y)
    $sep1.Size = New-Object System.Drawing.Size(430, 2)
    $form.Controls.Add($sep1)
    $y += 15

    # Version
    $lblV = New-Object System.Windows.Forms.Label
    $lblV.Text = "Image version:"; $lblV.Location = New-Object System.Drawing.Point(15, $y); $lblV.AutoSize = $true
    $form.Controls.Add($lblV)
    $txtV = New-Object System.Windows.Forms.TextBox
    $txtV.Text = $suggestedVersion; $txtV.Location = New-Object System.Drawing.Point(140, ($y - 3)); $txtV.Size = New-Object System.Drawing.Size(300, 23)
    $form.Controls.Add($txtV)
    $y += 35

    # Port
    $lblP = New-Object System.Windows.Forms.Label
    $lblP.Text = "API port:"; $lblP.Location = New-Object System.Drawing.Point(15, $y); $lblP.AutoSize = $true
    $form.Controls.Add($lblP)
    $txtP = New-Object System.Windows.Forms.TextBox
    $txtP.Text = "$Port"; $txtP.Location = New-Object System.Drawing.Point(140, ($y - 3)); $txtP.Size = New-Object System.Drawing.Size(100, 23)
    $form.Controls.Add($txtP)
    $y += 35

    # Separator
    $sep2 = New-Object System.Windows.Forms.Label
    $sep2.BorderStyle = "Fixed3D"
    $sep2.Location = New-Object System.Drawing.Point(15, $y)
    $sep2.Size = New-Object System.Drawing.Size(430, 2)
    $form.Controls.Add($sep2)
    $y += 15

    # Docs auth checkbox
    $chk = New-Object System.Windows.Forms.CheckBox
    $chk.Text = "Protect /docs and /setup with HTTP Basic Auth (recommended)"
    $chk.Checked = $true
    $chk.Location = New-Object System.Drawing.Point(15, $y)
    $chk.AutoSize = $true
    $form.Controls.Add($chk)
    $y += 30

    # Username
    $lblU = New-Object System.Windows.Forms.Label
    $lblU.Text = "Username:"; $lblU.Location = New-Object System.Drawing.Point(35, $y); $lblU.AutoSize = $true
    $form.Controls.Add($lblU)
    $txtU = New-Object System.Windows.Forms.TextBox
    $txtU.Text = "admin"; $txtU.Location = New-Object System.Drawing.Point(140, ($y - 3)); $txtU.Size = New-Object System.Drawing.Size(200, 23)
    $form.Controls.Add($txtU)
    $y += 30

    # Password
    $lblPw = New-Object System.Windows.Forms.Label
    $lblPw.Text = "Password:"; $lblPw.Location = New-Object System.Drawing.Point(35, $y); $lblPw.AutoSize = $true
    $form.Controls.Add($lblPw)
    $txtPw = New-Object System.Windows.Forms.TextBox
    $txtPw.UseSystemPasswordChar = $true; $txtPw.Location = New-Object System.Drawing.Point(140, ($y - 3)); $txtPw.Size = New-Object System.Drawing.Size(200, 23)
    $form.Controls.Add($txtPw)
    $y += 30

    # Confirm password
    $lblC = New-Object System.Windows.Forms.Label
    $lblC.Text = "Confirm:"; $lblC.Location = New-Object System.Drawing.Point(35, $y); $lblC.AutoSize = $true
    $form.Controls.Add($lblC)
    $txtC = New-Object System.Windows.Forms.TextBox
    $txtC.UseSystemPasswordChar = $true; $txtC.Location = New-Object System.Drawing.Point(140, ($y - 3)); $txtC.Size = New-Object System.Drawing.Size(200, 23)
    $form.Controls.Add($txtC)
    $y += 40

    # Toggle auth fields
    $authControls = @($lblU, $txtU, $lblPw, $txtPw, $lblC, $txtC)
    $chk.Add_CheckedChanged({ foreach ($c in $authControls) { $c.Enabled = $chk.Checked } })

    # Buttons
    $btnInstall = New-Object System.Windows.Forms.Button
    $btnInstall.Text = "Install"; $btnInstall.Size = New-Object System.Drawing.Size(90, 30)
    $btnInstall.Location = New-Object System.Drawing.Point(260, $y)
    $btnInstall.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.Controls.Add($btnInstall)
    $form.AcceptButton = $btnInstall

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"; $btnCancel.Size = New-Object System.Drawing.Size(90, 30)
    $btnCancel.Location = New-Object System.Drawing.Point(355, $y)
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($btnCancel)
    $form.CancelButton = $btnCancel

    $btnInstall.Add_Click({
        if ($chk.Checked) {
            if ([string]::IsNullOrWhiteSpace($txtPw.Text)) {
                [System.Windows.Forms.MessageBox]::Show("Password cannot be empty.", "Validation", "OK", "Warning") | Out-Null
                return
            }
            if ($txtPw.Text -ne $txtC.Text) {
                [System.Windows.Forms.MessageBox]::Show("Passwords do not match.", "Validation", "OK", "Warning") | Out-Null
                return
            }
        }
    })

    $result = $form.ShowDialog()
    if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
        Write-Host "Installation cancelled." -ForegroundColor Yellow; exit 0
    }

    return @{
        Version  = $txtV.Text
        Port     = [int]$txtP.Text
        DocsAuth = $chk.Checked
        Username = $txtU.Text
        Password = $txtPw.Text
    }
}

# ============================================================
# Standalone UI helpers (for Docker-start confirmation, etc.)
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

function UI-TextPrompt {
    param([string]$Prompt, [string]$Default = "")
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Cambium Fiber API"; $form.Size = New-Object System.Drawing.Size(400, 170)
    $form.StartPosition = "CenterScreen"; $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false; $form.MinimizeBox = $false
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $Prompt; $lbl.Location = New-Object System.Drawing.Point(15, 15); $lbl.Size = New-Object System.Drawing.Size(350, 20)
    $form.Controls.Add($lbl)
    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Text = $Default; $txt.Location = New-Object System.Drawing.Point(15, 45); $txt.Size = New-Object System.Drawing.Size(350, 23)
    $form.Controls.Add($txt)
    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = "OK"; $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK; $ok.Location = New-Object System.Drawing.Point(210, 90)
    $form.Controls.Add($ok); $form.AcceptButton = $ok
    $cn = New-Object System.Windows.Forms.Button
    $cn.Text = "Cancel"; $cn.DialogResult = [System.Windows.Forms.DialogResult]::Cancel; $cn.Location = New-Object System.Drawing.Point(295, 90)
    $form.Controls.Add($cn); $form.CancelButton = $cn
    if ($form.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK -and $txt.Text) { return $txt.Text }
    return $Default
}

function UI-PasswordPrompt {
    param([string]$Prompt)
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Cambium Fiber API"; $form.Size = New-Object System.Drawing.Size(400, 170)
    $form.StartPosition = "CenterScreen"; $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false; $form.MinimizeBox = $false
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $Prompt; $lbl.Location = New-Object System.Drawing.Point(15, 15); $lbl.Size = New-Object System.Drawing.Size(350, 20)
    $form.Controls.Add($lbl)
    $txt = New-Object System.Windows.Forms.TextBox
    $txt.UseSystemPasswordChar = $true; $txt.Location = New-Object System.Drawing.Point(15, 45); $txt.Size = New-Object System.Drawing.Size(350, 23)
    $form.Controls.Add($txt)
    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = "OK"; $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK; $ok.Location = New-Object System.Drawing.Point(210, 90)
    $form.Controls.Add($ok); $form.AcceptButton = $ok
    $cn = New-Object System.Windows.Forms.Button
    $cn.Text = "Cancel"; $cn.DialogResult = [System.Windows.Forms.DialogResult]::Cancel; $cn.Location = New-Object System.Drawing.Point(295, 90)
    $form.Controls.Add($cn); $form.CancelButton = $cn
    if ($form.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $txt.Text }
    return ""
}

# ============================================================
# Console logging
# ============================================================

function Write-ColorOutput {
    param([Parameter(Mandatory=$true)][string]$Message, [string]$Level = "INFO")
    $color = switch($Level) { "ERROR" { "Red" } "WARN" { "Yellow" } "INFO" { "Green" } default { "White" } }
    Write-Host "[$Level] $Message" -ForegroundColor $color
}

# ============================================================
# Docker checks
# ============================================================

function Test-Docker {
    Write-ColorOutput "Checking Docker..." -Level INFO
    try {
        $dockerVersion = docker --version
        if ($LASTEXITCODE -ne 0) { throw "fail" }
    } catch {
        Write-ColorOutput "Docker is not installed" -Level ERROR
        [System.Windows.Forms.MessageBox]::Show(
            "Docker is not installed.`n`nPlease install Docker Desktop from:`nhttps://www.docker.com/products/docker-desktop",
            "Cambium Fiber API", "OK", "Error") | Out-Null
        exit 1
    }

    try {
        docker info 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "not running" }
    } catch {
        $dockerDesktop = "${env:ProgramFiles}\Docker\Docker\Docker Desktop.exe"
        if (Test-Path $dockerDesktop) {
            Write-ColorOutput "Docker Desktop is installed but not running" -Level WARN
            if (-not (UI-Confirm -Prompt "Docker Desktop is not running. Start it now?" -DefaultYes $true)) {
                exit 1
            }
            Write-ColorOutput "Starting Docker Desktop..." -Level INFO
            Start-Process $dockerDesktop
            $maxWait = 60; $waited = 0
            while ($waited -lt $maxWait) {
                Start-Sleep -Seconds 3; $waited += 3; Write-Host "." -NoNewline
                docker info 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) { Write-Host ""; break }
            }
            if ($waited -ge $maxWait) {
                Write-Host ""; Write-ColorOutput "Docker Desktop did not start within ${maxWait}s" -Level ERROR; exit 1
            }
        } else {
            Write-ColorOutput "Docker daemon is not running" -Level ERROR; exit 1
        }
    }
    Write-ColorOutput "Docker is ready ($dockerVersion)" -Level INFO

    try { docker compose version | Out-Null; if ($LASTEXITCODE -ne 0) { throw "fail" } }
    catch { Write-ColorOutput "Docker Compose not available" -Level ERROR; exit 1 }
}

# ============================================================
# File generation
# ============================================================

function New-ComposeFile {
    $composeContent = @'
services:
  cambium-fiber-api:
    image: ${CAMBIUM_API_IMAGE:-cambium-fiber-api:latest}
    container_name: cambium-fiber-api
    ports:
      - "${CAMBIUM_API_PORT:-8192}:8192"
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
      test: ["CMD", "wget", "--spider", "--quiet", "http://localhost:8192/health"]
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
}

function New-EnvFile {
    param([hashtable]$Config)
    if ($env:VERSION) { $Config.Version = $env:VERSION }
    if ($env:API_PORT) { $Config.Port = [int]$env:API_PORT }

    $enableSetup = $(if ($env:ENABLE_SETUP_WIZARD) { $env:ENABLE_SETUP_WIZARD } else { 'true' })
    $oauthId = $(if ($env:OAUTH_CLIENT_ID) { $env:OAUTH_CLIENT_ID } else { '' })
    $oauthSecret = $(if ($env:OAUTH_CLIENT_SECRET) { $env:OAUTH_CLIENT_SECRET } else { '' })
    $sslCert = $(if ($env:SSL_CERT_PATH) { $env:SSL_CERT_PATH } else { '' })
    $sslKey = $(if ($env:SSL_KEY_PATH) { $env:SSL_KEY_PATH } else { '' })

    $envContent = @"
# Cambium Fiber API Configuration
CAMBIUM_API_IMAGE=cambium-fiber-api:$($Config.Version)
CAMBIUM_API_PORT=$($Config.Port)
ENABLE_SETUP_WIZARD=$enableSetup
OAUTH_CLIENT_ID=$oauthId
OAUTH_CLIENT_SECRET=$oauthSecret
SSL_CERT_PATH=$sslCert
SSL_KEY_PATH=$sslKey
"@
    Set-Content -Path $EnvFile -Value $envContent -Encoding UTF8
}

function New-ConnectionsFile {
    param([hashtable]$Config)
    $connectionsFile = "$InstallDir\connections.json"
    if (Test-Path $connectionsFile -PathType Container) {
        Remove-Item -Path $connectionsFile -Recurse -Force
    }

    if ($Config.DocsAuth) {
        $escapedPass = $Config.Password -replace "'", "''"
        $dockerCmd = "pip install -q bcrypt; python -c `"import bcrypt; print(bcrypt.hashpw('$escapedPass'.encode('utf-8'), bcrypt.gensalt()).decode('utf-8'))`""
        try {
            $docsHash = docker run --rm python:3.11-slim bash -c $dockerCmd 2>$null
            if ($LASTEXITCODE -ne 0 -or -not $docsHash) { throw "hash failed" }
        } catch {
            Write-ColorOutput "Failed to generate password hash" -Level ERROR; exit 1
        }
        $script:docsAuthEnabled = $true
        $json = @'
{
  "docs_auth": {
    "username": "__USERNAME__",
    "password_hash": "__HASH__"
  }
}
'@
        $json = $json -replace '__USERNAME__', $Config.Username -replace '__HASH__', $docsHash.Trim()
        Set-Content -Path $connectionsFile -Value $json -Encoding UTF8
    } else {
        $script:docsAuthEnabled = $false
        Set-Content -Path $connectionsFile -Value "{}" -Encoding UTF8
    }
}

# ============================================================
# Docker image loading
# ============================================================

function Import-DockerImage {
    Write-ColorOutput "Loading Docker image..." -Level INFO
    $envContent = Get-Content $EnvFile
    $imageLine = $envContent | Where-Object { $_ -match "^CAMBIUM_API_IMAGE=" }
    $desiredImage = $imageLine -replace "^CAMBIUM_API_IMAGE=", ""

    $tarball = Get-ChildItem -Path . -Filter "cambium-fiber-api-*.tar*" | Select-Object -First 1
    if ($tarball) {
        $tarballVersion = ""
        if ($tarball.Name -match "cambium-fiber-api-(.+)\.tar") { $tarballVersion = $Matches[1] }

        if ($tarball.Extension -eq ".gz") {
            $tempTar = "$env:TEMP\cambium-temp.tar"
            if (Get-Command tar -ErrorAction SilentlyContinue) {
                tar -xzf $tarball.FullName -C $env:TEMP
                $innerTar = Get-ChildItem -Path $env:TEMP -Filter "*.tar" -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -match "cambium" } | Select-Object -First 1
                if ($innerTar) { docker load -i $innerTar.FullName; Remove-Item $innerTar.FullName -ErrorAction SilentlyContinue }
                else { docker load -i $tarball.FullName }
            } else {
                $gzStream = [System.IO.File]::OpenRead($tarball.FullName)
                $decompress = New-Object System.IO.Compression.GZipStream($gzStream, [System.IO.Compression.CompressionMode]::Decompress)
                $outStream = [System.IO.File]::Create($tempTar)
                $decompress.CopyTo($outStream)
                $outStream.Close(); $decompress.Close(); $gzStream.Close()
                docker load -i $tempTar
                Remove-Item $tempTar -ErrorAction SilentlyContinue
            }
        } else {
            docker load -i $tarball.FullName
        }
        if ($LASTEXITCODE -ne 0) { Write-ColorOutput "Failed to load image" -Level ERROR; exit 1 }
        if ($tarballVersion -and $desiredImage -ne "cambium-fiber-api:$tarballVersion") {
            docker tag "cambium-fiber-api:$tarballVersion" $desiredImage
        }
    } else {
        Write-ColorOutput "No local tarball -- pulling from registry..." -Level WARN
        docker pull $desiredImage
        if ($LASTEXITCODE -ne 0) { Write-ColorOutput "Failed to pull image" -Level ERROR; exit 1 }
    }
    Write-ColorOutput "Image ready" -Level INFO
}

# ============================================================
# Container startup & endpoint validation
# ============================================================

function Test-Endpoint {
    param([string]$Url, [string]$Name, [int]$MaxRetries = 3, [int[]]$AcceptableCodes = @(200))
    for ($i = 0; $i -lt $MaxRetries; $i++) {
        try {
            $r = Invoke-WebRequest -Uri $Url -Method Get -TimeoutSec 2 -ErrorAction Stop
            if ($AcceptableCodes -contains $r.StatusCode) { return $true }
        } catch [System.Net.WebException] {
            $code = [int]$_.Exception.Response.StatusCode
            if ($AcceptableCodes -contains $code) { return $true }
        } catch { }
        if ($i -lt ($MaxRetries - 1)) { Start-Sleep -Seconds 1 }
    }
    return $false
}

function Get-ContainerLogs {
    Write-ColorOutput "Last 30 log lines:" -Level INFO
    docker logs --tail 30 cambium-fiber-api 2>&1 | ForEach-Object { Write-Host $_ }
}

function Write-Troubleshooting {
    param([int]$ApiPort)
    Write-ColorOutput "Troubleshooting:" -Level ERROR
    Write-ColorOutput "  docker ps -a | Select-String cambium-fiber-api" -Level INFO
    Write-ColorOutput "  docker logs cambium-fiber-api" -Level INFO
    Write-ColorOutput "  netstat -ano | Select-String $ApiPort" -Level INFO
    Write-ColorOutput "  cd $InstallDir; docker compose down; docker compose up -d" -Level INFO
}

function Start-ApiContainer {
    param([int]$ApiPort)
    Write-ColorOutput "Starting container..." -Level INFO
    Push-Location $InstallDir
    docker compose --env-file $EnvFile up -d
    Pop-Location
    Start-Sleep -Seconds 5

    if (-not (docker ps | Select-String "cambium-fiber-api")) {
        Write-ColorOutput "Container failed to start!" -Level ERROR
        Get-ContainerLogs; Write-Troubleshooting -ApiPort $ApiPort; exit 1
    }

    $script:healthOk = $false; $script:docsOk = $false; $script:setupOk = $false

    Write-ColorOutput "Validating /health endpoint..." -Level INFO
    for ($i = 0; $i -lt 30; $i++) {
        if (Test-Endpoint -Url "http://localhost:$ApiPort/health" -Name "health" -MaxRetries 1) {
            $script:healthOk = $true; break
        }
        Write-Host "." -NoNewline; Start-Sleep -Seconds 2
    }
    Write-Host ""
    if (-not $script:healthOk) {
        Write-ColorOutput "Health endpoint failed" -Level ERROR
        Get-ContainerLogs; Write-Troubleshooting -ApiPort $ApiPort; exit 1
    }

    $codes = @(200)
    if ($script:docsAuthEnabled) { $codes = @(200, 303, 307, 401) }

    if (Test-Endpoint -Url "http://localhost:$ApiPort/docs" -Name "docs" -MaxRetries 3 -AcceptableCodes $codes) { $script:docsOk = $true }
    if (Test-Endpoint -Url "http://localhost:$ApiPort/setup" -Name "setup" -MaxRetries 3 -AcceptableCodes $codes) { $script:setupOk = $true }

    if (-not $script:docsOk -or -not $script:setupOk) {
        Write-ColorOutput "Critical endpoints not responding" -Level ERROR
        Get-ContainerLogs; Write-Troubleshooting -ApiPort $ApiPort; exit 1
    }
    Write-ColorOutput "All endpoints verified" -Level INFO
}

# ============================================================
# Success
# ============================================================

function Write-Success {
    param([int]$ApiPort)
    # Verified -- all endpoints passed validation
    $msg = "Installation Complete!`n`n" +
        "Setup Wizard:  http://localhost:${ApiPort}/setup`n" +
        "API Docs:         http://localhost:${ApiPort}/docs`n" +
        "View Logs:        docker logs -f cambium-fiber-api"
    [System.Windows.Forms.MessageBox]::Show($msg,
        "Cambium Fiber API",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    Write-ColorOutput "Done: http://localhost:$ApiPort/setup" -Level INFO
}

# ============================================================
# Main
# ============================================================

function Main {
    Test-Docker
    $config = Show-InstallerWizard

    if (-not (Test-Path $InstallDir)) {
        try { New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null }
        catch { Write-ColorOutput "Cannot create $InstallDir -- run as Administrator" -Level ERROR; exit 1 }
    }

    New-ComposeFile
    New-EnvFile -Config $config
    New-ConnectionsFile -Config $config
    Import-DockerImage
    Start-ApiContainer -ApiPort $config.Port

    # Open setup wizard in browser (skip in CI/headless)
    if ($env:OPEN_BROWSER) {
        # OPEN_BROWSER set -- skip browser launch
    } else {
        try { Start-Process "http://localhost:$($config.Port)/setup" } catch { }
    }
    Write-Success -ApiPort $config.Port
}

try { Main }
catch {
    Write-ColorOutput "Installation failed: $_" -Level ERROR
    [System.Windows.Forms.MessageBox]::Show("Installation failed:`n`n$_", "Cambium Fiber API",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    exit 1
}
