$ErrorActionPreference = "Stop"

$Version = "2.0.1"
$ExpectedSha256 = "a0fa81022a6e0204b67c92f0046aaebac923bf6ffc786f503c5acff483807b4a"
$Url = "https://github.com/amnezia-vpn/amneziawg-windows-client/releases/download/$Version/amneziawg-amd64-$Version.msi"
$Root = Split-Path -Parent $PSScriptRoot
$Msi = Join-Path $env:RUNNER_TEMP "router1-awg-engine.msi"
$Extract = Join-Path $env:RUNNER_TEMP "router1-awg-engine"
$Release = Join-Path $Root "build\windows\x64\runner\Release"
$Destination = Join-Path $Release "engine"

Invoke-WebRequest -Uri $Url -OutFile $Msi
$ActualSha256 = (Get-FileHash -Algorithm SHA256 $Msi).Hash.ToLowerInvariant()
if ($ActualSha256 -ne $ExpectedSha256) {
  throw "AWG engine checksum mismatch: $ActualSha256"
}

New-Item -ItemType Directory -Force -Path $Extract | Out-Null
$Arguments = "/a `"$Msi`" /qn TARGETDIR=`"$Extract`""
$Process = Start-Process msiexec.exe -ArgumentList $Arguments -Wait -PassThru
if ($Process.ExitCode -ne 0) {
  throw "AWG engine extraction failed: $($Process.ExitCode)"
}

$Executable = Get-ChildItem -Path $Extract -Recurse -Filter "amneziawg.exe" | Select-Object -First 1
if (-not $Executable) {
  throw "amneziawg.exe not found in verified engine package"
}

Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $Destination
New-Item -ItemType Directory -Force -Path $Destination | Out-Null
Copy-Item -Recurse -Force (Join-Path $Executable.Directory.FullName "*") $Destination
Copy-Item -Force (Join-Path $Root "third_party\amneziawg\COPYING") (Join-Path $Destination "COPYING")
Set-Content -Encoding ASCII -Path (Join-Path $Destination "ENGINE_VERSION") -Value "$Version`n$ActualSha256"

Write-Host "Router1 embedded AWG engine prepared"
