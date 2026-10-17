# cp500-os

A small, Unix-flavored operating system for the Prologica CP-500, a Brazilian
TRS-80 Model III compatible: preemptive multitasking, a hierarchical file
system, virtual consoles and pipes on a 2 MHz Z80 with 48 KiB of RAM.

Status: milestone 6 (serial driver and `poll`). See [docs/design.md](docs/design.md).

Development and testing use the [heh8080](https://github.com/fredimachado/heh8080)
emulator's CP-500 machine.

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
