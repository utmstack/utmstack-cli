# UTMStack CLI installer (Windows, native PowerShell)
#
#   irm https://raw.githubusercontent.com/utmstack/utmstack-cli/main/install.ps1 | iex
#
# The bash installer (`install`) only runs under Git Bash / MSYS / WSL. This is
# the native path for PowerShell. It installs the `utmstack` CLI and, unless
# skipped, the UTMStack MCP server that provides the SIEM tools.

$ErrorActionPreference = 'Stop'
# On PowerShell 5.1 the Invoke-WebRequest progress bar makes large
# downloads roughly an order of magnitude slower.
$ProgressPreference = 'SilentlyContinue'

$Repo    = 'utmstack/utmstack-cli'
$App     = 'utmstack'
$Version = if ($env:UTMSTACK_VERSION) { $env:UTMSTACK_VERSION } else { 'latest' }

function Info($m) { Write-Host $m }
# `throw`, not `exit`: these scripts are documented for `irm ... | iex`, which
# runs in the caller's scope — `exit` would close the user's console before
# they could read the error, and inside a &-invoked scriptblock it bypasses
# the surrounding try/catch entirely.
function Fail($m) { throw "utmstack install: $m" }

# --- platform ------------------------------------------------------------- #
# Under WOW64 (a 32-bit PowerShell host) PROCESSOR_ARCHITECTURE reads x86
# on an x64 machine; PROCESSOR_ARCHITEW6432 carries the real value.
$rawArch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
$arch = switch ($rawArch) {
    'AMD64' { 'x64' }
    'ARM64' { 'arm64' }
    'x86'   { Fail '32-bit Windows is not supported' }
    default { Fail "unsupported architecture: $rawArch" }
}
$target = "windows-$arch"
$asset  = "$App-$target.zip"

# --- resolve release ------------------------------------------------------ #
$api = if ($Version -eq 'latest') {
    "https://api.github.com/repos/$Repo/releases/latest"
} else {
    "https://api.github.com/repos/$Repo/releases/tags/v$($Version -replace '^v','')"
}

Info "Resolving $Version release of $Repo ..."
try {
    $release = Invoke-RestMethod -Uri $api -UseBasicParsing
} catch {
    Fail 'could not resolve a release (is the repository public and does it have a release?)'
}
$tag = $release.tag_name
if (-not $tag) { Fail 'no tag_name in release response' }
Info "  version: $tag"
Info "  platform: $target"

$base = "https://github.com/$Repo/releases/download/$tag"
$tmp  = Join-Path $env:TEMP ("utmstack-install-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

try {
    # --- download + verify ------------------------------------------------ #
    Info "Downloading $asset ..."
    $pkg = Join-Path $tmp $asset
    try {
        Invoke-WebRequest -Uri "$base/$asset" -OutFile $pkg -UseBasicParsing
    } catch {
        Fail "no build published for $target in $tag"
    }

    Info 'Verifying checksum ...'
    $sumFile = Join-Path $tmp 'checksums.txt'
    try {
        Invoke-WebRequest -Uri "$base/checksums.txt" -OutFile $sumFile -UseBasicParsing
    } catch {
        Fail 'could not download checksums.txt - refusing to install an unverified binary'
    }

    $expected = $null
    foreach ($line in Get-Content $sumFile) {
        if ($line -match "^([0-9a-fA-F]{64})\s+\*?$([regex]::Escape($asset))$") {
            $expected = $Matches[1].ToLower(); break
        }
    }
    if (-not $expected) { Fail "no checksum listed for $asset - refusing to install" }

    $actual = (Get-FileHash -Path $pkg -Algorithm SHA256).Hash.ToLower()
    if ($expected -ne $actual) { Fail "checksum mismatch - expected $expected, got $actual" }
    Info '  checksum OK'

    # --- install ---------------------------------------------------------- #
    $installDir = Join-Path $env:USERPROFILE ".$App\bin"
    New-Item -ItemType Directory -Force -Path $installDir | Out-Null

    Info "Installing to $installDir ..."
    # Extract into a dedicated subdirectory. Expanding into $tmp would mix the
    # archive and checksums.txt in with the payload, and the sidecar copy below
    # would then install them too.
    $extract = Join-Path $tmp 'extract'
    New-Item -ItemType Directory -Force -Path $extract | Out-Null
    # Prefer tar (bsdtar, shipped on Windows 10+): Expand-Archive is very slow on
    # ARM for a large many-file zip and can take minutes. Fall back to
    # Expand-Archive where tar is unavailable.
    $tar = Get-Command tar.exe -ErrorAction SilentlyContinue
    if ($tar) {
        & $tar.Source -xf $pkg -C $extract
        if ($LASTEXITCODE -ne 0) { Expand-Archive -Path $pkg -DestinationPath $extract -Force }
    } else {
        Expand-Archive -Path $pkg -DestinationPath $extract -Force
    }
    $exeSource = Get-ChildItem -Path $extract -Recurse -Filter "$App.exe" | Select-Object -First 1
    if (-not $exeSource) { Fail "archive does not contain $App.exe" }

    # Windows refuses to overwrite a running executable; say so plainly.
    try {
        Copy-Item -Path $exeSource.FullName -Destination (Join-Path $installDir "$App.exe") -Force -ErrorAction Stop
    } catch {
        Fail "could not write $App.exe - it may be running. Close any $App session and re-run."
    }

    # Ship any sidecar files the archive carries alongside the executable.
    Get-ChildItem -Path $exeSource.DirectoryName -File |
        Where-Object { $_.Name -ne "$App.exe" } |
        ForEach-Object { Copy-Item $_.FullName -Destination $installDir -Force }

    $exe = Join-Path $installDir "$App.exe"

    # --- PATH ------------------------------------------------------------- #
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $pathUpdated = $false
    if ($userPath -notlike "*$installDir*") {
        $newPath = if ($userPath) { "$userPath;$installDir" } else { $installDir }
        [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
        $env:Path = "$env:Path;$installDir"
        $pathUpdated = $true
    }

    $installed = (& $exe --version 2>&1 | Out-String).Trim()
    Info ''
    Info "Installed $App $installed"
    Info "  binary: $exe"

    # --- UTMStack MCP server ---------------------------------------------- #
    # The CLI ships a default config pointing at `utmstack-mcp`, so the SIEM
    # tools only work if that binary exists. A failure here is reported but
    # never fails the CLI install.
    if ($env:UTMSTACK_SKIP_MCP) {
        Info ''
        Info 'Skipping UTMStack MCP server (UTMSTACK_SKIP_MCP set)'
    } elseif (Get-Command utmstack-mcp -ErrorAction SilentlyContinue) {
        Info 'UTMStack MCP server already installed'
    } else {
        Info ''
        Info 'Installing utmstack-mcp (SIEM tools) ...'
        try {
            & ([scriptblock]::Create((Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/utmstack/MCP/main/install.ps1' -UseBasicParsing)))
        } catch {
            Info 'Could not install the UTMStack MCP server automatically.'
            Info 'The CLI works without it; SIEM tools stay unavailable until you run:'
            Info '  irm https://raw.githubusercontent.com/utmstack/MCP/main/install.ps1 | iex'
        }
    }

    Info ''
    Info '  UTMSTACK CLI'
    Info ''
    if ($pathUpdated) {
        Info '  NOTE: PATH was updated. Open a new terminal for `utmstack` to resolve.'
        Info ''
    }
    Info 'First run:'
    Info '  utmstack-mcp init     # connect your UTMStack server'
    Info '  utmstack              # start the CLI, then /connect for your ThreatWinds API key'
    Info ''
    Info 'Docs: https://docs.utmstack.com'
    Info ''
}
finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
