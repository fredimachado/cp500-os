#!/usr/bin/env pwsh
# Installs the pinned sjasmplus into build/tools/sjasmplus. Safe to rerun.
$ErrorActionPreference = 'Stop'

$version = '1.24.0'
$release = "https://github.com/z00m128/sjasmplus/releases/download/v$version"
$windowsZip = @{ Name = "sjasmplus-$version.win.zip"; Sha256 = '7e1f8840842039bdb97e51a59abda2e5c25a9da160097e8f79a62583ab72d0e0' }
$sourceTarball = @{ Name = "sjasmplus-$version-src.tar.xz"; Sha256 = '0b5013f07e8d8505f9e296529655668b6fdf0268625c19e883b0fff484e209f1' }

$repoRoot = Split-Path -Parent $PSScriptRoot
$installDir = Join-Path $repoRoot 'build/tools/sjasmplus'
$exe = Join-Path $installDir ($IsWindows ? 'sjasmplus.exe' : 'sjasmplus')

if ((Test-Path $exe) -and ((& $exe --version 2>&1 | Out-String) -match [regex]::Escape($version))) {
    Write-Host "sjasmplus $version already installed at $exe"
    return
}

function Get-VerifiedAsset($asset, $directory) {
    $path = Join-Path $directory $asset.Name
    Invoke-WebRequest "$release/$($asset.Name)" -OutFile $path
    $actual = (Get-FileHash $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $asset.Sha256) {
        throw "$($asset.Name): SHA-256 $actual does not match the pinned $($asset.Sha256)"
    }
    $path
}

$work = Join-Path ([IO.Path]::GetTempPath()) "sjasmplus-$version-$([Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Force $work | Out-Null
try {
    if (Test-Path $installDir) { Remove-Item -Recurse -Force $installDir }
    New-Item -ItemType Directory -Force $installDir | Out-Null

    if ($IsWindows) {
        $zip = Get-VerifiedAsset $windowsZip $work
        Expand-Archive $zip -DestinationPath $work
        $built = Get-ChildItem $work -Recurse -Filter 'sjasmplus.exe' | Select-Object -First 1
    }
    else {
        $tarball = Get-VerifiedAsset $sourceTarball $work
        tar -xJf $tarball -C $work
        if ($LASTEXITCODE -ne 0) { throw "tar failed with exit code $LASTEXITCODE" }
        $source = Get-ChildItem $work -Directory | Select-Object -First 1
        $jobs = [Environment]::ProcessorCount
        make -C $source.FullName -j $jobs
        if ($LASTEXITCODE -ne 0) { throw "make failed with exit code $LASTEXITCODE" }
        $built = Get-Item (Join-Path $source.FullName 'sjasmplus')
    }

    if (-not $built) { throw "sjasmplus binary not found in the $version release" }
    Copy-Item $built.FullName $exe
    Write-Host "Installed $(& $exe --version 2>&1 | Select-Object -First 1) at $exe"
}
finally {
    Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}
