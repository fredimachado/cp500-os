#!/bin/sh
# Builds the boot disk and starts the heh8080 desktop emulator with it in drive 0.
# Extra arguments go to the emulator.
set -e

repo_root=$(cd "$(dirname "$0")/.." && pwd)

dotnet build "$repo_root/image/Cp500Os.Disk.proj"
exec dotnet run --project "$repo_root/external/heh8080/src/Heh8080.Desktop" -p:PublishAot=false -- --disk "$repo_root/build/cp500-os.dsk" "$@"
