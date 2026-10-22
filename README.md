# cp500-os

A small, Unix-flavored operating system for the Prologica CP-500, a Brazilian
TRS-80 Model III compatible: preemptive multitasking, a hierarchical file
system, virtual consoles and pipes on a 2 MHz Z80 with 48 KiB of RAM.

Status: milestone 8 (W5100 sockets, telnet, get, and time sync). See [docs/design.md](docs/design.md).

Development and testing use the [heh8080](https://github.com/fredimachado/heh8080)
emulator's CP-500 machine.

## Running

Build the boot disk, then start the desktop emulator with it in drive 0. The
CP-500 ROMs must already be in `%LOCALAPPDATA%\heh8080\` (or `cp500/` next to
the executable). Click the logo on the bezel to attach RS-232.

```sh
dotnet build image/Cp500Os.Disk.proj
dotnet run --project external/heh8080/src/Heh8080.Desktop -p:PublishAot=false -- --disk build/cp500-os.dsk
```

`eng/run-emulator.sh` and `eng/run-emulator.ps1` do both steps.

## Building

Requirements: the .NET 10 SDK and PowerShell 7. On Linux and macOS, `make`
and a C++ compiler too, because sjasmplus is built from source there.

```sh
pwsh eng/install-sjasmplus.ps1   # once: pinned assembler into build/tools
dotnet test --solution cp500-os.slnx
```

Everything the build produces goes under `build/`. Clone with
`--recurse-submodules` (or run `git submodule update --init`): the boot tests
run heh8080's headless runner from `external/heh8080`.

CI boots with the stub ROM in `rom/`. To also run the boot tests against the
real CP-500 ROM, copy your dump to `roms/cp500.rom` or point `CP500_ROM` at it.
The ROM is copyrighted and never committed.
