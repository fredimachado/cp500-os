#!/usr/bin/env pwsh
# Builds the boot disk and starts the heh8080 desktop emulator with it in drive 0.
# Extra arguments go to the emulator.
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$disk = Join-Path $repoRoot 'build/cp500-os.dsk'

dotnet build (Join-Path $repoRoot 'image/Cp500Os.Disk.proj')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

dotnet run --project (Join-Path $repoRoot 'external/heh8080/src/Heh8080.Desktop') -p:PublishAot=false -- --disk $disk @args --w5100
exit $LASTEXITCODE
