$ErrorActionPreference = "Stop"

$Repo = if ($env:MIHU_REPO) { $env:MIHU_REPO } else { "mihu-ai/mihu-cli-releases" }
$Arch = if ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq "Arm64") { "arm64" } else { "amd64" }

if ($env:MIHU_VERSION) {
  $Version = $env:MIHU_VERSION
} else {
  $Version = (Invoke-RestMethod "https://api.github.com/repos/$Repo/releases/latest" -Headers @{ "User-Agent" = "mihu-installer" }).tag_name
}
$VersionNum = $Version.TrimStart("v")
$Asset = "mihu-cli_${VersionNum}_windows_${Arch}.zip"
$Base = "https://github.com/$Repo/releases/download/$Version"

$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("mihu-" + [System.Guid]::NewGuid())
New-Item -ItemType Directory -Path $Tmp | Out-Null
try {
  Write-Host "==> Downloading mihu $Version (windows/$Arch)"
  Invoke-WebRequest "$Base/$Asset" -OutFile (Join-Path $Tmp $Asset) -UseBasicParsing
  Invoke-WebRequest "$Base/checksums.txt" -OutFile (Join-Path $Tmp "checksums.txt") -UseBasicParsing

  Write-Host "==> Verifying checksum"
  $Expected = (Get-Content (Join-Path $Tmp "checksums.txt") | Where-Object { $_ -match " $([regex]::Escape($Asset))$" }) -split "\s+" | Select-Object -First 1
  $Actual = (Get-FileHash (Join-Path $Tmp $Asset) -Algorithm SHA256).Hash.ToLower()
  if (-not $Expected -or $Expected -ne $Actual) { throw "checksum mismatch (expected $Expected, got $Actual)" }

  Expand-Archive (Join-Path $Tmp $Asset) -DestinationPath $Tmp -Force

  $InstallDir = if ($env:MIHU_INSTALL_DIR) { $env:MIHU_INSTALL_DIR } else { Join-Path $env:LOCALAPPDATA "Programs\mihu" }
  New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
  Copy-Item (Join-Path $Tmp "mihu.exe") (Join-Path $InstallDir "mihu.exe") -Force
  Write-Host "==> Installed to $InstallDir\mihu.exe"

  $UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
  if (($UserPath -split ";") -notcontains $InstallDir) {
    [Environment]::SetEnvironmentVariable("Path", "$UserPath;$InstallDir", "User")
    $env:Path = "$env:Path;$InstallDir"
    Write-Host "==> Added $InstallDir to your user PATH (restart your shell if 'mihu' is not found)"
  }
  Write-Host ""
  Write-Host "Get started:"
  Write-Host "    mihu login"
} finally {
  Remove-Item $Tmp -Recurse -Force -ErrorAction SilentlyContinue
}
