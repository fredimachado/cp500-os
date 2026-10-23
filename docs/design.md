# cp500-os Design

Status: milestone 8 is implemented, including the six syscalls loaded from
`/sys/ser`, the extra device nodes and `/mnt/fd` mounts, shell line editing,
and the host TRSDOS/LDOS importer. Numbers marked "budget" are targets to
measure against, not facts. Addresses, escape sequences and the keyboard map
below are the ones the kernel uses.

## 1. Goals and non-goals

cp500-os is a small, Unix-flavored operating system for the Prologica CP-500
(a TRS-80 Model III compatible). "Modern" means how the system behaves, not how
big it is.

Goals:

- Runs on a stock CP-500: Z80 at 2.03 MHz, 48 KiB RAM, 64x16 text, 1-4 floppy
  drives. Optional expansions (serial, virtual hard disk, network) are detected
  at boot and used when present.
- Preemptive multitasking with a small, fixed number of tasks.
- One hierarchical file tree with long names, timestamps and exact sizes.
- Everything is a file descriptor: consoles, printer, serial port, pipes.
- Virtual consoles, a shell with line editing, history and completion.
- Relocatable programs, so several can be resident at once.
- Portuguese text works out of the box (accented letters, dead keys).

Non-goals:

- Memory protection. There is no MMU; a bad program can crash the machine.
- Running TRSDOS, LDOS or BASIC programs. They call ROM and DOS entry points
  this OS does not provide. The host `c5fs import` command copies files from
  TRSDOS and LDOS disks in JV3 and DMK images instead.
- On-machine `fsck`, Model III WAIT-plus-interrupt floppy transfers,
  32-column video, a RAM disk, and a repository license.
- Mouse-driven GUI, Unicode, multiple users or permissions.

## 2. Hardware contract

The OS depends on exactly these ROM behaviors, verified against the CP-500 ROM
dump (CRC32 `c2fc1b92`):

| ROM address | Behavior | What the OS does with it |
|-------------|----------|--------------------------|
| reset | Reads track 0 sector 1 to `4300h` and jumps there | Boot sector entry |
| `0008h`-`0030h` | `RST n` jumps to `4000h`, `4003h`, ..., `400Fh` | `RST 08h` is the system call |
| `0038h` | IM 1 interrupt jumps to `4012h` | Interrupt service routine |
| `0066h` | NMI: `3039h` checks port `E4h` bit 5; if reset is not held, jumps to `4049h`, else waits for release and reboots | Floppy controller completion |

Everything else is hardware the kernel drives directly:

| Device | Ports / addresses | Notes |
|--------|-------------------|-------|
| Keyboard | `3800h-3BFFh` | 8x8 matrix, polled, active high |
| Video | `3C00h-3FFFh`, control `ECh` | 64x16 characters, `80h-BFh` are 2x3 block graphics (128x48), no hardware cursor, no reverse video |
| Interrupts | `E0h` IRQ mask/status, `E4h` NMI mask/status, `ECh` timer ack | 30 Hz timer IRQ, FDC INTRQ on NMI |
| Floppy | `F0h-F3h` WD1791, `F4h` drive select/side/WAIT/MFM | 40 tracks, 18 x 256-byte sectors, 180 or 360 KiB |
| Printer | `F8h` | Parallel, status + data |

There is no real-time clock, no memory banking and no DMA. Interrupt mode 1 is
used rather than mode 2: the ROM already routes it to RAM, and mode 2 would
depend on what the data bus floats to during acknowledge, which is not
guaranteed on real hardware.

## 3. Memory map

```text
0000-37FF  ROM (fixed, 14 KiB)
3800-3BFF  keyboard matrix
3C00-3FFF  video RAM (64x16)
4000-40FF  system page
4100-41FF  boot and idle stack
4200-60FF  kernel code and read-only data in the disk image (8 KiB budget)
6100-61FF  sector buffer in the image (zeroed; BLK_BUF at runtime)
6200-BEFF  arena pages for programs and pipes (pages 62h-0BEh)
BF00-C3FF  console history rings (5 pages, owner FEh); task names at C308h
C400-D2FF  arena pages for programs and pipes (pages 0C4h-0D2h)
D300-DFFF  /sys/ser (13 pages)
E000-EFFF  /sys/dev (16 pages), with the serial state record at its top
F000-F0FF  copy of /sys/keymap (keyboard tables and Latin-1 glyphs)
F100-F4FF  console 1 shadow screen and other fixed RAM below KPAGE
F500-FFFF  KPAGE (page owners, task records, open files) and /sys/wr
```

System page (`4000h-40FFh`):

| Address | Content |
|---------|---------|
| `4000h` | `JP syscall` (target of `RST 08h`) |
| `4003h`-`400Fh` | `RST 10h`-`30h` slots, reserved. `RST 30h` is the debugger breakpoint |
| `4012h` | `JP isr` |
| `4015h`-`4048h` | Kernel variables (tick counter, current task, flags) |
| `4049h` | `JP nmi` |
| `404Ch`-`40FFh` | Kernel variables |

The boot sector lands at `4300h`, inside the kernel range. It first copies
itself to `FF00h` and continues there, then loads the first kernel block to
`4200h`. That block loads the rest of the run to `4300h` and jumps there. A
256-byte sector cannot hold the CRC, the superblock choice and a multi-block
read together. The boot sector's own divide uses the low byte of the kernel
start, so that block number has to be below 256. The continuing loader uses
the full 16-bit start.

### Arena

All dynamic memory comes from two arena runs: pages `62h` through `0BEh` (93
pages) and `0C4h` through `0D2h` (15 pages), 108 pages in all. A page owner
table at `KPAGE` records `00h` free, `FFh` kernel, or the owning task id, so
everything a task owned is freed when it exits. Pages `0BFh`-`0C3h` hold the
console history and task names, `0D3h`-`0EFh` hold `/sys/ser` and `/sys/dev`,
and pages from `F000h` upward hold `/sys/keymap`, the second console shadow,
kernel RAM and `/sys/wr`. Programs and pipes never use those pages.

- Programs and their stacks are allocated from the bottom up, first fit.
- Pipes take one arena page each from the same pool.
- There is no compaction: without an MMU, absolute pointers cannot be moved.

At mount the kernel copies `/sys/keymap` to `F000h` and `/sys/wr` to `F800h`.
The banner prints only after both files load, so keys typed at the banner use
the same map as the shell.

The task-name table `TASK_NAMES` at `C308h` takes 8 bytes for each task slot:
the basename of the spawned program without its extension, 7 characters and a
NUL. It sits in the history pages after the two consoles' rings, and boot does
not clear it. The `/sys/dev` gate fills it on spawn, and `taskinfo` reads it.

## 4. Tasks and scheduling

- Eight task slots. Task 0 is init: it spawns a shell for each console that
  needs one, otherwise `HALT` until the next interrupt.
- Round-robin among runnable tasks, quantum of 2 ticks (66 ms). `yield` forces
  an immediate reschedule by zeroing the quantum.
- Preemption is deferred inside the kernel. While `KBUSY` is set during a system
  call, the timer only decrements the quantum. When the quantum reaches zero on
  return to user code, the kernel switches tasks. A blocked call saves a frame
  that points back at its own `RST 08h` and reruns the call when woken, so the
  kernel holds no I/O state across a block.
- A context switch pushes `AF BC DE HL IX IY AF' BC' DE' HL'` on the current
  task's stack and saves `SP` in the live task record at `T_LIVE`.
- Kernel code runs on the calling task's stack. Every task stack must reserve
  192 bytes for the kernel and interrupt frames on top of its own needs. The
  loader adds this automatically.

Per-slot state lives in the system page, `KPAGE` and the history RAM:

| Location | Size | Meaning |
|----------|------|---------|
| `T_STATE` | 1 per slot | free, ready, blocked, dying, zombie |
| `T_CHAN` | 1 per slot | Wait channel when blocked |
| `T_PARENT` | 1 per slot | Parent task id |
| `T_ARG` | 2 per slot | Exit code in the low byte when zombie |
| `T_LIVE` record | 16 bytes | Saved `SP`, arena base, page count, cwd, fd table |
| `TASK_NAMES` | 8 bytes | Program name for `taskinfo` (history RAM, `C308h`) |

Open files and pipe metadata sit in `KPAGE` outside the disk image.

### Processes are spawned, not forked

`fork` would need to copy a program and fix up its pointers, which is
impossible without an MMU. `spawn` loads a new program, sets up its arguments,
environment and file descriptors, and makes it ready, like `posix_spawn`. The
CP-500 keyboard has no `|` key, so the shell runs pipelines as `a ! b` with
two spawns and a pipe (`a`'s stdout and `b`'s stdin on the pipe ends). Each side
uses the same spawn rules as a foreground line (bare words from `/bin/`). The
`?` prefix spawns a background child the same way, without waiting. The shell
prints `ok <id>` with the child's task id.

### Break

BREAK on the active console ends the foreground task with exit code `0FFh`,
unless that console is in raw mode, where BREAK is delivered as key `03h`. The
shell sets the foreground task with `ioctl` request `01h` before `wait`, and
calls `wait` with `FEh` at the prompt to reap background zombies without
blocking. If task 1 (the first shell) exits, the machine halts.

## 5. Interrupts and drivers

### Timer interrupt (30 Hz)

`4012h` jumps to the interrupt service routine, which:

1. Pushes `AF`, `BC`, `DE`, and `HL`.
2. Reads `ECh` to acknowledge the timer.
3. Advances the tick counter. If the keyboard ring is not empty, it wakes tasks blocked on keyboard input. Every tick also wakes tasks blocked on `sleep`, so the call reruns until the duration expires.
4. Scans the keyboard and blinks the cursor.
5. If the quantum is already zero and the kernel is not inside a system call, it pushes the rest of the registers and switches. A tick during a system call only counts the quantum down.
6. Otherwise it pops `AF`, `BC`, `DE`, and `HL`, enables interrupts, and returns with `RETI`.

### Keyboard

Scanned every tick. A key must read the same in two consecutive scans to
count, which gives up to 66 ms of latency, comparable to the ROM. Repeat starts
after 15 ticks (0.5 s) and runs at one key every 3 ticks. Keys go into one 32-byte ring at `4026h`. A console switch empties that ring. The scan tables and composition rules
come from `/sys/keymap` at `F000h`. Table byte `00h` means no key. The acute
dead key (`27h`) composes ISO-8859-1 letters listed in the map. If the next
key does not compose, the acute is delivered and then the key. CLEAR plus a
digit switches virtual consoles.

Milestone 2 pins the scan in the system page. `4015h` is the 4-byte
little-endian tick count. The ring is 32 bytes at `4026h`, with the head at
`4019h` (the scanner writes it) and the tail at `401Ah` (the main line writes
it). One slot stays empty so the two indexes can tell full from empty. Repeat
state is `401Bh`-`401Dh`. Raw samples are `401Eh`-`4025h`. Debounced rows are
`404Ch`-`4053h`.

Row `n` is the byte at `3800h` with address bit `n` set (`3801h` is `@` and
A-G). Unshifted letters are lowercase, so a typed `Hi` is `Hi`. SHIFT is row 7
bit 0 and changes the glyph. ENTER is `0Dh` and moves to column 0 of the next
row. BREAK, CLEAR and SHIFT alone are dropped. UP, DOWN, LEFT and RIGHT are
delivered as `ESC [ A`, `ESC [ B`, `ESC [ D` and `ESC [ C`, so the keyboard has
no `[`. Bytes from
`C0h` through `FFh` map to video codes through the `LAT1_GLYPH` table in
`/sys/keymap`. A `--type` hold is about three ticks, so it cannot reach the
repeat delay.

### Console

- Each virtual console is 64x16. The active one lives in video RAM; inactive
  ones keep a 1 KiB shadow copy in the arena. Switching swaps the two, about
  20 ms.
- Output understands a subset of ANSI/VT100 escape sequences: cursor movement
  and positioning, erase line/screen, save/restore cursor. This keeps ported
  programs and future serial or telnet sessions consistent. Milestone 2
  accepts `ESC 7` and `ESC 8` (save and restore), `ESC [ A/B/C/D` (move; a
  missing or zero count moves one cell), `ESC [ H` and `ESC [ f` (1-based
  position; a missing row or column is 1), `ESC [ J` and `ESC [ K` (0 from
  the cursor, 1 through the cursor, 2 the whole screen or line; a missing
  count is 0). An unknown sequence is discarded. The cursor is the CP-500's
  `B0h` bar, toggled every 7 ticks and saved and restored around blinks. A
  console shows no cursor until a program prints to it, so it first appears
  at the shell's `sh>`. Console state is `4054h`-`4061h`.
- Text is ISO-8859-1. The console maps bytes through `LAT1_GLYPH` in
  `/sys/keymap`, then writes the resulting video code.
- Raw mode (console `ioctl` request `02h`, bit 0) disables dead-key composition
  and delivers BREAK as key `03h` instead of killing the foreground task.
- The cursor is drawn in software by blinking a block on the tick.
- Default: 2 consoles. A shell is started on a console the first time it is
  shown, not at boot, to save memory.

### Floppy

`floppy_read` is the polled loop the boot sector already runs. `DE` is the
16-bit block and `HL` is the 256-byte destination. The routine divides by
`VOL_SPT`, then takes the track from the quotient (shifted right when the
volume has two sides) and the sector from the remainder plus one. A track
above 255 is `EIO`. Interrupts stay off for the seek and the read. Seek is
`FDC_CMD_SEEK` with head load and the 30 ms step rate, followed by a poll for
not-busy. The read is `FDC_CMD_READ`. Not-busy before 256 bytes is `EIO`.
`DRQ` moves one byte with `INI`, and `B` starts at 0 so the loop runs 256
times. A 16-bit poll that expires is `EIO`. After the sector, not ready, CRC
error, record not found, or lost data is `EIO`. Both returns enable
interrupts. The routine does not call the console. `DE`, `HL`, `IX`, `IY`,
and the alternate registers are unchanged. `DISK_WAIT` is never set.
`PORT_NMI` stays 0. `nmi` is `RETN`.

`floppy_write` is the same poll with `FDC_CMD_WRITE` and `OUTI`. A failed
write, including write protect or write fault, is `EIO`. This is the polled
path. WAIT plus NMI is still not claimed.

The Model III WAIT-plus-INTRQ transfer is not implemented and is not claimed.
A green emulator run shows only that the poll completed the sector. The notes
below describe that unimplemented technique.

- Sector transfers would run with interrupts off, WAIT enabled on the disk
  port, an `INI` loop that the WAIT line paces against DRQ, and the FDC's
  INTRQ arriving as NMI to end the transfer. At 2 MHz, MFM leaves about 65 CPU
  cycles per byte, so no interrupt may run during a transfer. One sector holds
  interrupts off for about 8 ms, well under a tick. The timer IRQ stays
  latched and is serviced right after.
- Seeks would run with interrupts on. The NMI handler would record completion
  and the waiting task would wake on the next tick, so other tasks run during
  seeks.
- Disk changes cannot be detected by hardware on this machine. After a drive
  has been idle for 2 s (motor off), the next access rereads the superblock
  and compares the volume id and generation (section 7). A mismatch drops the
  cached blocks, and open files on that volume fail with `ECHANGED`.
- Floppy writes are write-through: the user can eject at any moment.

### Block device interface

All storage is addressed in 256-byte blocks, the native sector size of both the
floppies and the Model III hard disk interface.

```text
read_block(dev, block, buffer)    write_block(dev, block, buffer)
block_count(dev)                  media_check(dev) -> unchanged | changed | absent
```

Character devices implement `open`, `close`, `read`, `write`, `ioctl`. Drivers
for expansions are built into the kernel at first and enabled only when their
probe finds the hardware; open-bus reads return `FFh`, so a probe writes and
reads back a register with known behavior.

## 6. System call interface

Programs call the kernel with `RST 08h`. The ROM forwards it to `4000h`, which
jumps to the dispatcher. One byte per call, and no program needs to know where
the kernel lives.

Registers:

| Register | Role |
|----------|------|
| `C` | Function number |
| `DE`, `HL`, `B` | Arguments 1, 2, 3 |
| `IX` | Pointer argument 4, when needed |
| `HL` | Result |
| `A` | Error code, `0` on success |
| carry | Set on error, so assembly can `RST 08h` then `JR C,fail` |

The kernel preserves `IX`, `IY` and the alternate register set, and destroys
`AF`, `BC`, `DE`, `HL`. Values wider than 16 bits (file offsets, times) are
passed through a pointer to 4 little-endian bytes.

### Functions

Process:

| # | Name | Arguments | Result |
|---|------|-----------|--------|
| `00h` | exit | `DE` code | does not return |
| `01h` | spawn | `DE` path, `HL` argv/envp block, `IX` fd map | `HL` task id |
| `02h` | wait | `DE` task id (`FFh` = any child) | `HL` low = exit code, high = task id |
| `03h` | getpid | | `HL` task id |
| `04h` | yield | | |
| `05h` | sleep | `DE` ticks | |
| `06h` | kill | `DE` task id | `EBUSY` for a child of init |
| `07h` | uptime | `DE` pointer to 4 bytes | tick count since boot |
| `58h` | taskinfo | `DE` task id (0-7), `HL` pointer to a 16-byte record | record written at `HL` |

Memory:

| # | Name | Arguments | Result |
|---|------|-----------|--------|
| `10h` | alloc | `DE` pages | `HL` address |
| `11h` | free | `DE` address | |
| `12h` | meminfo | `DE` pointer to info record | |

Files and directories:

| # | Name | Arguments | Result |
|---|------|-----------|--------|
| `20h` | open | `DE` path, `B` flags (read, write, create, truncate, append, exclusive) | `HL` fd |
| `21h` | close | `DE` fd | |
| `22h` | read | `DE` fd, `HL` buffer, `IX` length | `HL` bytes read, `0` at end |
| `23h` | write | `DE` fd, `HL` buffer, `IX` length | `HL` bytes written |
| `24h` | seek | `DE` fd, `HL` pointer to 4-byte offset (updated), `B` whence | |
| `25h` | stat | `DE` path, `HL` stat record | |
| `26h` | fstat | `DE` fd, `HL` stat record | |
| `27h` | readdir | `DE` fd of an open directory, `HL` entry record | `HL` `0` at end |
| `28h` | mkdir | `DE` path | |
| `29h` | remove | `DE` path (file or empty directory) | |
| `2Ah` | rename | `DE` old path, `HL` new path | |
| `2Bh` | chdir | `DE` path | |
| `2Ch` | getcwd | `DE` buffer, `HL` size | |
| `2Dh` | dup2 | `DE` old fd, `HL` new fd | |
| `2Eh` | pipe | `DE` pointer to 2 bytes | read fd, write fd |
| `2Fh` | ioctl | `DE` fd, `HL` request, `IX` argument | `HL` request-specific |
| `30h` | sync | | Flushes all write-back caches |
| `31h` | poll | `DE` pointer to poll entries, `B` count (1-8), `HL` timeout in ticks (`0` = check only, `FFFFh` = forever) | `HL` entries ready |

Time:

| # | Name | Arguments | Result |
|---|------|-----------|--------|
| `40h` | time | `DE` pointer to 4 bytes | Seconds since 1980-01-01 00:00 local time |
| `41h` | settime | `DE` pointer to 4 bytes | |

`50h-57h` are the socket calls (section 9). `58h` is `taskinfo`, and `59h-5Fh`
are reserved.

Limits: 8 descriptors per task, 16 open files system-wide, 4 pipes of 256 bytes
each, paths up to 127 bytes.

### Implemented calls

The kernel implements every call in the table above except `taskinfo`, which
the `/sys/dev` gate handles. The socket calls `50h-57h` are also in `/sys/dev`
(section 9). The bodies of `sleep`, `uptime`, `alloc`, `free`, `meminfo`,
and `dup2` live in `/sys/ser`; `sc_table` jumps to `DEV_SLEEP`, `DEV_UPTIME`,
`DEV_ALLOC`, `DEV_FREE`, `DEV_MEMINFO`, and `DEV_DUP2`.

`RST 08h` saves the syscall frame and sets `SC_FRAME` before `vol_bind`, so a
blocked call reruns with the same register arguments. `sc_sleep` reads the
duration from the saved frame's `DE`, not from live `DE` after a wake.

`sleep` (`05h`) takes the duration in `DE` ticks. `DE = 0` returns immediately
and does not arm. `DE >= 8000h` is `EINVAL`. On the first blocking entry the
kernel stores the start tick in `T_ARG` (`40C0h`) for the current task: bit 15
(the high byte's bit 7) is the armed flag, and the low 15 bits hold the tick. Each timer
tick wakes sleepers on channel `CH_SLEEP`; the call blocks again until
`(TICK_COUNT - start) >= DE`, then clears `T_ARG` and returns.

`uptime` (`07h`) copies the 4-byte tick counter at `TICK_COUNT` through the
pointer in `DE`. `alloc` (`10h`) takes a page count in `DE` (high byte must be
0), allocates a contiguous run from the arena, and returns the base address in
`HL`. `free` (`11h`) takes a page-aligned address in `DE` and returns pages
owned by the caller to the free pool. `meminfo` (`12h`) fills a 6-byte record
at `DE`: free page count, largest free run in pages, total arena pages, and a
zero pad byte. `dup2` (`2Dh`) copies the open file of `DE` onto `HL`, dropping
any previous descriptor there.

Success is `A = 0`, carry clear, and the result in `HL`. Failure is `A` set
to the code, `HL = 0`, and carry set. `exit` does not return. `spawn` uses
the lowest free slot among tasks 1-7 and returns its task id. With no free
slot it returns `EAGAIN`. A pending or running child does not make the next
`spawn` `EBUSY`. `wait` with `DE = FFh` waits for any child. `DE = FEh`
reaps one zombie without blocking and returns `ECHILD` when none are ready.
A specific child id waits only for that task. The result is
`HL = (task_id << 8) | exit_code`.

`kill` (`06h`) ends the task with exit code `FFh`. The console shells and
`/etc/rc` are children of init, so `kill` returns `EBUSY` for them. Ending
task 1 would halt the machine.

`taskinfo` (`58h`) writes the 16-byte record for task `DE` (0-7) at `HL`. A
free slot succeeds with state 0, and an id above 7 is `EINVAL`. The layout is:

| Offset | Size | Field |
|--------|------|-------|
| 0 | 1 | State: `TS_*` (free, ready, blocked, dying, zombie) |
| 1 | 1 | Parent task id, `FFh` for an orphan |
| 2 | 1 | Wait channel: `CH_*`, with pipe `n` as `CH_PIPE + n` |
| 3 | 1 | Base page |
| 4 | 1 | Page count |
| 5 | 1 | Console 0 or 1, `FFh` for none |
| 6-7 | 2 | Reserved |
| 8-15 | 8 | Name: basename of the spawned path without its extension, 7 characters and a NUL. Zeroes for task 0 |

`open` for read of a file or a directory takes the lowest free descriptor.
`read` of a directory is `EISDIR`. `readdir` of a file is `ENOTDIR`. `fstat`
of a console descriptor is `EINVAL`. `write` of a file or directory
descriptor is `EROFS` and does not walk a path. `write` of descriptor 0 is
`EBADF`. Descriptors 1 and 2 write the console. `mkdir`, `remove`, and
`rename` walk first, then refuse the change with `EROFS` when the name
resolution would have modified the volume. `remove` of `/` is `EBUSY`.

`seek` takes a file descriptor in `DE`, a pointer to a signed 32-bit
little-endian offset in `HL`, and a whence in `B`. Whence 0 sets the
position, 1 adds to the current position, and 2 adds to the file size. Any
other whence, or a directory or console descriptor, is `EINVAL`. A negative
result, or a sum that does not fit in a signed 32-bit value, is `EINVAL` and
leaves the position unchanged. Otherwise the new position is stored and
written back through `HL`. A position past the file size is legal, and the
next `read` returns 0.

`chdir` takes an absolute path in `DE`. The walk starts at inode 1. The inode
must be a directory. The task stores volume 0 at offset 5 and the inode at
offsets 14 and 15. `getcwd` takes a buffer in `DE` and a size in `HL`. Inode
1 is `/`. Any other cwd reads directory slot 0 for the parent, finds the
child's name there, and repeats until the root. A missing name is `EIO`. A
buffer shorter than the path plus a NUL is `EINVAL` and is left untouched.

`stat` and `fstat` write this 16-byte record:

| Offset | Size | Field |
|--------|------|-------|
| 0 | 2 | Inode number |
| 2 | 1 | Inode type with the indirect bit and bit 7 cleared |
| 3 | 1 | 0 |
| 4 | 4 | Size, low 3 bytes from the inode, high byte 0 |
| 8 | 4 | Modified |
| 12 | 4 | Created |

`readdir` copies one 32-byte directory slot, including `..`. Holes are
skipped. `HL` is 1 when an entry was stored and 0 at the end. Both are
success. The slot is inode (2 bytes) then a 30-byte NUL-padded name.

The argv block is `argc`, `envc`, then that many NUL-terminated strings.
Both counts are 0 to 8. The shell passes `envc` 0 and `argc` equal to the word
count; a word with no `/` is spawned from `/bin/` plus that word. The loader copies the block
to `load + image + bss` and sets `SP` to `load + image + bss + stack + 192`.

### Character devices

Stdin, stdout and stderr are wired to the task's console through descriptors
0-2. Paths under `/dev/` name devices, not files. They appear in no directory.

The kernel's `dev_table` has two rows: `/dev/ser0` and `/dev/hd0`, each with
a probe and block driver. Every other shipped device name is resolved in
`/sys/ser` before any file system walk:

| Path | Device | Present |
|------|--------|---------|
| `/dev/con` | The task's controlling console | Always |
| `/dev/con0`, `/dev/con1` | Console 0 or 1 | Always |
| `/dev/tty` | The active virtual console | Always |
| `/dev/null` | Discards writes, reads return 0 | Always |
| `/dev/fd0`-`/dev/fd3` | Raw floppy sectors for drives 0-3 | When the drive responds |
| `/dev/prn` | Parallel printer at port `F8h`; busy is bit 7 | Always |
| `/dev/ser0` | Serial board (section 9) | When the probe finds the UART |
| `/dev/hd0` | Virtual hard disk (section 9) | When FreHD answers |

`/mnt/fd1`, `/mnt/fd2`, and `/mnt/fd3` mount floppy drives 1-3 into volume
slots 1-3 on first access. A missing drive returns `ENODEV` (`18`). There is no
separate volume slot tied to a same-numbered hard-disk partition.

`open` of a probed device that is absent is `ENODEV`. `create`, `truncate`,
`append` and `exclusive` on a device are `EINVAL`, and so are `fstat` and
`seek` except on `/dev/fd0`-`/dev/fd3`, where `seek` accepts whence 0 only.
`/dev/ser0` is exclusive: a second `open` while its open file exists is
`EBUSY`. Printer `write` waits for not-busy and does not time out. Descriptors
that share the open file through `spawn` or `dup2` share the device.

Reads and writes on character devices (console, serial, pipes):

- On the console, `read` blocks until it has stored the requested byte count
  (the shell reads one byte at a time). Pipe reads return what is available up
  to the length and block when the pipe is empty while a writer still exists.
- `read` returns 0 only at end of file: a pipe whose writers have all closed,
  or `/dev/ser0` after a hangup (section 9).
- `write` blocks until every byte is queued. Queued is not sent: serial output
  drains from a ring under interrupts.
- The console has no line discipline. It never echoes, and backspace, ENTER
  and arrows arrive as bytes. Programs echo and edit lines themselves. The
  shell uses backspace byte `08h`, TAB completion, UP and DOWN for a 4-line
  by 128-byte history ring in kernel RAM (`CON_HIST` at `BF00h`, owner
  `FEh`, `ioctl` requests `5` get and `6` put), `>` redirection through the
  spawn fd map, and prints `exit N` only when `N` is not 0. LEFT is the
  CP-500's backspace key: it arrives as `ESC [ D`, and the shell erases with
  it as with `08h` (`BS`, space, `BS`). RIGHT is ignored. History is not
  stored in the shell's bss.

### Non-blocking I/O

The open flag `nonblock` (`40h`, after `exclusive` `20h`) or the `FIONBIO`
ioctl marks an open file non-blocking. The mode belongs to the open file, so
descriptors that share it share the mode. On a non-blocking open file:

- `read` with nothing available fails with `EAGAIN`. It never returns 0, so 0
  still means end of file.
- `write` queues what fits and returns that count. If nothing fits, it fails
  with `EAGAIN`.
- Files and directories ignore the mode: disk reads and writes always
  complete.

Descriptors 0-2 are shared with the parent. A program that wants a
non-blocking console opens `/dev/con` with `nonblock`, which gives it a new
open file, instead of changing descriptor 0 under the shell.

### poll

`poll` waits until one of up to 8 descriptors is ready or the timeout passes.
`DE` points to `B` entries of 3 bytes:

| Offset | Size | Field |
|--------|------|-------|
| 0 | 1 | Descriptor |
| 1 | 1 | Events wanted |
| 2 | 1 | Events returned, written by the kernel |

| Bit | Name | Meaning |
|-----|------|---------|
| `01h` | `POLLIN` | `read` would not block: data, or end of file |
| `02h` | `POLLOUT` | `write` of at least one byte would not block |
| `04h` | `POLLHUP` | Serial carrier lost, or a pipe has no writers. Reported whether wanted or not |
| `08h` | `POLLERR` | The device recorded receive errors since the last `poll` (section 9). Reported whether wanted or not |
| `10h` | `POLLNVAL` | The descriptor is not open. Reported, not an error |

`poll` writes every returned byte, 0 where nothing applies, and returns as
soon as one is nonzero or the timeout in ticks passes. `HL` is the number of
entries with a nonzero returned byte, and 0 after a timeout, which is success.
A count of 0 or more than 8 is `EINVAL`. Files and directories are always
`POLLIN` and `POLLOUT`. A waiting task is blocked, so other tasks and the
idle `HALT` run. Without multitasking the kernel waits with `HALT`, as a
console `read` does.

The usual event loop polls the console and the device for `POLLIN` with a
timeout for the program's own timers, then reads each ready descriptor
non-blocking until `EAGAIN`.

### ioctl requests

On console descriptors 0-2 the request is the low byte in `HL`: `01h` sets
the foreground task (`IX` = task id, `0` none) and returns the previous id in
`HL`; `02h` sets the console mode (`IX` = mode bits, only bit 0 raw is
defined) and returns the previous mode; `05h` (`CON_GETHIST`) reads one history
line (`IX` points to a slot byte then a 128-byte buffer); `06h` (`CON_PUTHIST`)
pushes a null-terminated line into the ring. Any other low-byte request on a
console is `EINVAL`.

The table below is the full target. `ioctl` takes the request in `HL`. `IX`
is a value or a pointer, as the table says. The high byte of the request is
the device class. An unknown request, or one for another class, is `EINVAL`.

| Request | Name | Applies to | `IX` | Result `HL` |
|---------|------|------------|------|-------------|
| `0001h` | `FIONBIO` | Devices, pipes | `0` blocking, `1` non-blocking | |
| `0002h` | `FIONREAD` | Devices, pipes | | Bytes readable now |
| `0003h` | `FIONSPACE` | Devices, pipes | | Bytes writable without blocking. The console never blocks: `FFFFh` |
| `0004h` | `FIOFLUSH` | Devices, pipes | Bit 0 discards input, bit 1 discards queued output | |
| `0101h` | `CON_GETMODE` | Console | | Mode bits |
| `0102h` | `CON_SETMODE` | Console | Mode bits | |
| `0103h` | `CON_SETFG` | Console | Task id on this console | |
| `0104h` | `CON_GETSIZE` | Console | | `H` rows, `L` columns |
| `0201h`-`0206h` | Serial | `/dev/ser0` | Section 9 | |

Console mode bit 0 is raw: BREAK arrives as `03h` instead of terminating the
foreground task. The other bits are 0. The mode belongs to the console, not
the open file, and the shell sets it back to 0 after every `wait`.

### Error codes

| Code | Name | | Code | Name |
|------|------|-|------|------|
| 1 | `ENOENT` | | 10 | `ENOEXEC` |
| 2 | `EEXIST` | | 11 | `EMFILE` |
| 3 | `ENOMEM` | | 12 | `ECHILD` |
| 4 | `EBADF` | | 13 | `EROFS` |
| 5 | `EINVAL` | | 14 | `ENOTEMPTY` |
| 6 | `ENOSPC` | | 15 | `EBUSY` |
| 7 | `EIO` | | 16 | `EAGAIN` |
| 8 | `ENOTDIR` | | 17 | `ECHANGED` (disk was swapped) |
| 9 | `EISDIR` | | 18 | `ENODEV` |

### Program format and loading

Programs are linked at `0000h` and loaded on a page boundary. Relocation only
has to add the load page to the high byte of every absolute address, which
keeps both the table and the loader small (the approach CP/M 3 uses for PRL
files).

```text
offset  size        field
0       4           magic "C5X" (43h 35h 58h), version byte 01h
4       2           image size n (code + initialized data)
6       2           bss size
8       2           stack size (the loader adds the 192-byte kernel reserve)
10      2           entry offset
12      4           reserved, must be 00h
16      n           image, linked at 0000h
16+n    ceil(n/8)   relocation bitmap: bit i set means image byte i is the
                    high byte of an absolute address
```

All fields are little-endian. The file is exactly `16 + n + ceil(n/8)`
bytes. Bit `i` of the bitmap is bit `i % 8` (least significant first) of
bitmap byte `i / 8`, and bits past `n` in the last byte are zero. Readers
reject a wrong magic or version, nonzero reserved bytes, a short or long file
and set padding bits, so a future version can give them meaning.

The build computes the bitmap toolchain-independently: link the program at
`0000h` and at `0100h` and mark every byte that is exactly 1 higher (mod 256)
in the second link. A byte that changes by anything else means the code is not
page-relocatable (for example it uses the low byte of an address, or
`addr + 80h` arithmetic that carries differently), and the build fails with
the offending offsets.

Relocating to page `p` (load address `p * 256`) adds `p` mod 256 to every
marked byte and touches nothing else. `Relocator.Relocate` in `Cp500Os.C5x`
is that exact algorithm and is the oracle the kernel loader tests compare
against.

A valid header has `entry offset < image size` (so the image is never empty)
and `image + bss + stack + 192` at most 40,448 bytes, the 158-page arena.

`mkreloc <link0000.bin> <link0100.bin> -o <out.c5x> [--bss n] [--stack n]
[--entry n]` writes the file; numbers are decimal or `0x` hex, and the
defaults are bss 0, stack 256 and entry 0. `mkreloc --info <file.c5x>` prints
the header, relocation count and the memory the loader will allocate.

At `spawn` the kernel allocates one block for image, bss and stack, relocates
it, copies argv and the environment just below the stack, and starts the task
at the entry point with `SP` set. The C runtime's startup code turns that into
`argc`, `argv` and `environ`.

## 7. File system (C5FS)

This section is the on-disk format. The host library (`src/Cp500Os.C5fs`) and
the `c5fs` tool implement it exactly; the kernel must read and write the same
bytes.

### Parameters

- Block = 256 bytes = one sector. Block numbers are 16-bit, so a volume holds
  at most 65,535 blocks (16 MiB). A virtual hard disk can be larger and is
  split into partitions.
- All multi-byte integers are little-endian.
- Floppies have 40 tracks of 18 sectors. A 360 KiB floppy has 2 sides and
  1440 blocks; a 180 KiB floppy has 1 side and 720 blocks.
- Floppy block `n` maps to track `n / (18 * sides)`, side
  `(n / 18) % sides`, sector `n % 18 + 1`. Raw images are track-major with
  the sides interleaved, so block `n` is at byte `n * 256` of the image.
  Images are exactly 184,320 or 368,640 bytes.

### Layout

| Blocks | Content |
|--------|---------|
| 0 | Boot sector (floppies) or partition table (hard disk) |
| 1, 2 | Superblock copies A and B |
| 3 .. | Allocation bitmap, `ceil(block count / 2048)` blocks (1 on floppies, 32 on 16 MiB) |
| .. | Inode table, `inode count / 8` blocks |
| .. | Data, from the first data block to the end |

The inode table starts right after the bitmap and the first data block right
after the inode table. Format presets:

| | 180 KiB | 360 KiB |
|-|---------|---------|
| Inodes (usable) | 64 (63) | 128 (127) |
| Bitmap | block 3 | block 3 |
| Inode table | blocks 4-11 | blocks 4-19 |
| First data block, root directory | 12 | 20 |
| Free after format | 707 blocks, 62 inodes | 1419 blocks, 126 inodes |

On a hard disk, block 0 holds up to 4 partition entries (type, start block,
block count, 3 bytes each for start and count), and each partition is a C5FS
volume starting with its own block 0 (unused) and superblocks at 1 and 2.
Partition volumes record sides, tracks and sectors as `0`.

### Allocation bitmap

Block `n` is bit `n % 8` (least significant first) of byte `n / 8`, counting
from the first bitmap block; `1` = used. The blocks before the first data
block are always marked used. The padding bits past the last block, up to the
end of the last bitmap block, are always `1`, so a byte-wise scan for a
non-`FFh` byte never finds a block that does not exist.

The free block count is not stored; the kernel counts the bitmap at mount,
which avoids a superblock write per allocation.

### Superblock

| Offset | Size | Field |
|--------|------|-------|
| 0 | 4 | Magic `C5FS` |
| 4 | 1 | Version, `1` |
| 5 | 1 | Flags: bit 0 clean; other bits `0` |
| 6 | 4 | Sequence number |
| 10 | 4 | Volume id, random at format time |
| 14 | 2 | Generation, `1` at format |
| 16 | 2 | Block count |
| 18 | 2 | Bitmap start block, `3` |
| 20 | 1 | Bitmap length in blocks |
| 21 | 2 | Inode table start |
| 23 | 2 | Inode count (table slots, a multiple of 8) |
| 25 | 2 | First data block |
| 27 | 1 | Sides (`0` on hard disk) |
| 28 | 1 | Tracks per side (`0` on hard disk) |
| 29 | 1 | Sectors per track (`0` on hard disk) |
| 30 | 2 | Kernel start block, `0` when there is no kernel |
| 32 | 2 | Kernel block count, `0` when there is no kernel, otherwise 1-255 |
| 34 | 4 | Created, seconds since 1980 |
| 38 | 4 | Last written, seconds since 1980 |
| 42 | 16 | Volume label, printable ISO-8859-1, NUL padded (16 bytes has no NUL) |
| 58 | 196 | Reserved, `0` |
| 254 | 2 | CRC over bytes 0-253 |

The CRC is CRC-16/CCITT-FALSE: polynomial `1021h`, initial value `FFFFh`, no
reflection, no final XOR. Its check value (CRC of ASCII `123456789`) is
`29B1h`.

Choosing a copy: a copy is valid when its magic and CRC check out. Of the
valid copies, the one with the higher sequence number wins; on a tie, A wins.
Every reader applies this rule, the boot sector included. Writes go to the
copy that is not current, with the sequence number incremented, so a write
torn by power loss always leaves the previous copy intact. A volume with no
valid copy does not mount.

Format writes both copies, identical except for the sequence: A gets 1 and B
gets 2, so B is current on a fresh volume and the first write goes to A.

The generation lets a kernel that cached a floppy notice that it was changed
elsewhere (section 5). It is incremented each time the volume goes from clean
to dirty. A host tool session (open the image, make changes, save it) counts
as one such transition: it writes one new superblock copy with sequence + 1,
generation + 1, the clean flag set and "last written" updated. A session that
changes nothing writes nothing and leaves the image byte-identical.

### Inode (32 bytes)

Inode `n` is slot `n` of the inode table (block `table start + n / 8`, offset
`(n % 8) * 32`). Slot 0 is reserved and stays all zero, because inode number
`0` in a directory entry means a free entry. Inode 1 is the root directory.
A free inode is 32 zero bytes.

| Offset | Size | Field |
|--------|------|-------|
| 0 | 1 | Type and flags, see below |
| 1 | 1 | Extent count |
| 2 | 3 | Size in bytes (24-bit, at most 16,777,215) |
| 5 | 4 | Modified, seconds since 1980 |
| 9 | 4 | Created, seconds since 1980 |
| 13 | 18 | 6 extent slots of (start block 2 bytes, length 1 byte) |
| 31 | 1 | Reserved, `0` |

Type byte: bits 0-3 type (`0` free, `1` file, `2` directory), bit 4
read-only, bit 5 hidden, bit 6 indirect extents, bit 7 `0`.

An extent is a run of 1-255 consecutive blocks inside the data area. A file
owns exactly `ceil(size / 256)` data blocks in total; nothing is
preallocated, and the bytes after the end of the file in its last block are
`0`.

- With 6 extents or fewer, they sit in the inline slots in file order, the
  extent count is the number used, the indirect flag is clear and unused
  slots are zero.
- With 7 to 90 extents, the indirect flag is set and the extent count is the
  total. Inline slots 1-5 hold extents 1-5. Slot 6 holds the indirect block
  number in its 2 start bytes and `0` in its length byte. The indirect block
  holds extents 6 onwards packed 3 bytes each from offset 0 (up to 85), and
  its remaining bytes are zero. The indirect block is marked used in the
  bitmap and belongs to the inode; it is freed when the extent count drops
  back to 6.

### Directories

A directory is a file of 32-byte entries, 8 per block:

| Offset | Size | Field |
|--------|------|-------|
| 0 | 2 | Inode number, `0` = free entry |
| 2 | 30 | Name, ISO-8859-1, NUL padded |

- The first entry of every directory is `..`, pointing at the parent. The
  root's `..` points at inode 1. `.` is not stored.
- The size is a non-zero multiple of 32. A directory grows by one entry at a
  time and by one zeroed block when the last block is full. Removing an entry
  zeroes all 32 bytes; free entries are reused before the directory grows, and
  directories never shrink.
- Names are 1-30 bytes. A 30-byte name has no terminator; after a shorter
  name every byte is `0`. Allowed bytes are the printable ISO-8859-1
  characters (`20h-7Eh` and `A0h-FFh`) except `/`. `.` and `..` are reserved.
- Names are case-preserving and compared case-insensitively by folding each
  byte: `A-Z` to `a-z`, and `C0h-DEh` to `E0h-FEh` except `D7h` (multiplication
  sign). So `Ação` equals `AÇÃO`, but `Acao` does not equal `Ação`: this is
  case folding, not accent stripping. `DFh` and `FFh` have no partner. Two
  entries of one directory never have equal folded names.
- Paths are absolute, `/`-separated and at most 127 bytes.
- An inode is referenced by exactly one directory entry (no hard links).

Host tools convert names to Unicode NFC and then to ISO-8859-1, rejecting
characters outside it. They list directories in folded byte order.

### Allocation

The kernel and the host tools allocate the same way, so images built on the
host look like images written by the OS:

1. Extend the file's last extent in place while the next blocks are free and
   the extent stays within 255 blocks.
2. Otherwise take the lowest-numbered free run that holds all remaining
   blocks (at most 255).
3. Otherwise take the lowest-numbered free run whatever its size, and repeat.

An indirect block, when needed, is the lowest-numbered free block once the
data blocks are allocated. A file that would need more than 90 extents fails
with `ENOSPC`. The allocator prefers extending the last extent, so files
written sequentially on a fresh disk use one or two extents, and reading them
needs no extra block lookups. Replacing a file's contents frees its old blocks
first and keeps its inode number, attributes and creation time.

### Boot sector and kernel

Block 0 holds up to 256 bytes of boot code, zero-padded.

The kernel is the regular file `/sys/kernel`, stored as exactly one extent of
1-255 blocks (budget: 8 KiB, 32 blocks). The superblock's kernel start and
count record that extent, so the 256-byte boot sector only has to read a block
range and needs no file system code. The `sys` tool installs it: it frees the
previous kernel, takes the lowest-numbered run of enough contiguous free
blocks and fails with `ENOSPC` when there is none. Writing `/sys/kernel` as an
ordinary file is refused, and removing it clears the superblock's kernel
fields, so the two always agree.

### Consistency rules

Host `c5fs check` verifies, reporting every violation:

- The current superblock is valid and its layout fields match the block and
  inode counts.
- Every allocated inode is well-formed as described above, including its
  indirect block and size against its extents. Free inodes and slot 0 are
  all zero.
- The bitmap equals the set of owned blocks exactly: metadata blocks, inode
  extents and indirect blocks, with no block owned twice. Padding bits are set.
- Every directory starts with a correct `..`, has no duplicate folded names,
  only valid names, zeroed free entries, and entries that point at allocated
  inodes.
- Every inode except the root is referenced exactly once; the root is not
  referenced by any entry other than `..`.
- The superblock's kernel fields are zero exactly when `/sys/kernel` does not
  exist, and otherwise equal its single extent.

Errors use the numbers in section 6: `ENOENT`, `EEXIST`, `ENOTDIR`, `EISDIR`,
`ENOTEMPTY` with their usual meaning, `EINVAL` for bad names, paths, sizes and
images, `ENOSPC` for no free blocks, no free inodes, too many extents or no
contiguous kernel run, `EIO` for malformed on-disk structures, and `EBUSY`
for removing `/`.

### Crash consistency

No journal: it would double the writes on a medium where every random block
costs a seek plus up to 200 ms of rotation. Instead, writes are ordered so that a crash at any point
only leaks blocks or inodes, never shares a block between two files:

- Create or grow: write the bitmap with the new blocks marked used, then the
  data, then the inode, then the directory entry.
- Delete: clear the directory entry, then free the inode, then the bitmap.
- Rename within a volume: write the new entry, then clear the old one. A crash
  in between leaves the file under both names; the checker keeps one.

The superblock's clean flag is cleared (and the generation incremented) before
the first write after mount, and set again after `sync` once the volume has
been idle. Mounting a dirty volume rebuilds the bitmap from the inode table,
which on a floppy means reading about 20 blocks. On-machine `fsck` is out of
scope; `c5fs check` does the full check (duplicate names, orphan inodes) on
demand.

The host tools never leave a volume half-written: they change an in-memory
copy and replace the image file in one rename, so a failed command leaves the
image byte-identical.

### File tree

The boot volume is `/`. Other volumes appear under `/mnt` by device name
(`/mnt/fd1`-`/mnt/fd3` for floppy drives 1-3, `/mnt/hd0p1` and siblings for
hard-disk partitions) and are mounted on first access. `/dev` is provided by
the kernel, not stored on disk.

```text
/bin        commands
/etc        startup script (rc); the product image ships an empty /etc/rc
/sys        kernel, ser, fonts, keyboard maps
/tmp        scratch on the boot volume, created and emptied at boot
/home       user files
/dev        con con0 con1 tty null fd0-fd3 prn ser0 hd0
/mnt        fd1-fd3, hd0 partitions, ...
```

### Time

Times are unsigned 32-bit seconds since 1980-01-01 00:00 local time (no time
zone is stored), which lasts until 2116. The kernel keeps time from the 30 Hz
tick. After `/sys/dev` loads, if the FreHD board answers probe register `CEh`
with `07h`, the kernel reads the battery-backed clock on that board and sets
system time through `/sys/wr`; otherwise the root volume's last-written time
from `c5fs_pick` / `mt_apply` remains the base. At mount the base is the volume's last-written time and
the origin tick is `TICK_COUNT`. The current time is that base plus
`(TICK_COUNT - origin) / 30`, integer division. `date` with no arguments
prints `yyyy-MM-dd HH:mm:ss`. `date` with two arguments, the date and the
time separated by a space, sets the clock. `more` shows 16 lines and then
waits for space (`20h`). The editor overwrites with printable ASCII. `:w`
then ENTER saves and exits. `:q` then ENTER quits without saving. Arrow keys
arrive as ESC `[` A/B/C/D. The on-machine `fsck` is not in this image. The
bitmap is not visible through the existing calls, and the kernel has no room
for a second copy of `VolumeChecker`. `c5fs check` remains the oracle.

## 8. Boot sequence

After mount, task 0 spawns `/etc/rc` before the first shell. A missing file or
a file that is not a valid C5X is skipped without error. When `rc` finishes,
the kernel creates `/tmp` if needed, removes every entry under it, and only then
starts shells for consoles that want one. `/tmp` is ordinary disk space, not a
RAM disk.

```mermaid
sequenceDiagram
    participant ROM
    participant Boot as Boot sector
    participant Kernel
    participant RC as /etc/rc
    participant Shell as /bin/sh
    ROM->>Boot: read track 0 sector 1 to 4300h, jump
    Boot->>Boot: copy self to FF00h
    Boot->>Kernel: read superblocks A and B, take the valid one with the higher sequence, read the first kernel block to 4200h, jump
    Kernel->>Kernel: install 4000h, 4012h, 4049h jumps, IM 1, enable timer IRQ and FDC NMI
    Kernel->>Kernel: probe expansions, init arena, consoles, mount /
    Kernel->>RC: spawn /etc/rc
    RC-->>Kernel: exit or skipped
    Kernel->>Kernel: mkdir /tmp, empty /tmp
    Kernel->>Shell: spawn shell on console 0 when wanted
```

## 9. Expansions

Each expansion is a real or realistic piece of hardware, so the OS keeps
running on physical machines that have it. The emulator side is specified in
heh8080 (`lode/plans/cp500-expansions.md`), where the port and register
details are still marked for verification against datasheets.

| Expansion | Hardware model | OS support |
|-----------|----------------|------------|
| Serial | Model III RS-232 board (TR1602 UART, ports `E8h-EBh`), interrupt driven | `/dev/ser0`, terminal program, serial console |
| Modem bridge | Hayes-compatible "Wi-Fi modem" on the serial port: `ATDT host:port` opens a TCP connection | Telnet and BBS access with no TCP/IP code in the OS |
| Virtual hard disk | Radio Shack hard disk interface (WD1010 at `C0h-CFh`), as implemented by FreHD | `/dev/hd0`, partitions, battery-backed clock |
| Network | WIZnet W5100 TCP/IP offload chip, indirect bus mode on 4 I/O ports | Socket system calls `50h-57h`: `socket`, `connect`, `listen`, `accept`, `send`, `recv`, `close`, `resolve` |

TCP/IP is offloaded to the W5100 rather than run on the Z80: a software stack
would cost 10-15 KiB and most of the CPU. The modem bridge comes first because
it gives network access with only a serial driver. The socket calls are in
`/sys/dev`. The boot disk has `/bin/telnet`, `/bin/get`, and `/bin/timesync`.

### Serial board

The Model III RS-232-C board: a TR1602 UART and a BR1941 baud rate generator.
The bits below follow the Model III Technical Reference Manual. Verify them
against the datasheets and heh8080 before the driver depends on them.

| Port | IN | OUT |
|------|----|-----|
| `E8h` | Modem status: bit 7 CTS, 6 DSR, 5 DCD, 4 RI | OUT bit 1 enables loading the UART control register at `EAh`; other OUT bits are not documented here |
| `E9h` | Board configuration switches | Baud rate: bits 0-3 receive, bits 4-7 transmit |
| `EAh` | UART status: bit 7 data received, 6 transmit holding register empty, 5 overrun, 4 framing error, 3 parity error | UART control: bit 0 DTR, 1 RTS, 2 break, 3 parity inhibit, 4 stop bits, 5-6 word length, 7 even parity |
| `EBh` | Received byte; reading clears data received | Byte to transmit |

`E0h` has three serial sources, with the timer's mask and active-low status
convention: bit 4 transmit holding register empty, bit 5 data received, bit 6
receive error. The probe resets the UART and reads `EAh`: bit 7 clear and bit
6 set means a board is present. An absent board reads `FFh`.

Baud codes set both nibbles of `E9h`; the driver always uses one rate in both
directions:

| Code | Rate | Code | Rate | Code | Rate | Code | Rate |
|------|------|------|------|------|------|------|------|
| `0` | 50 | `4` | 150 | `8` | 1800 | `C` | 4800 |
| `1` | 75 | `5` | 300 | `9` | 2000 | `D` | 7200 |
| `2` | 110 | `6` | 600 | `A` | 2400 | `E` | 9600 |
| `3` | 134.5 | `7` | 1200 | `B` | 3600 | `F` | 19200 |

Driver:

- Interrupt driven in both directions. `open` allocates two arena pages: a
  receive ring and a transmit ring of 255 usable bytes each. The last `close`
  frees them.
- The UART holds one received byte, so the ISR reads `EBh` before any timer
  work. The whole ISR, timer path included, must finish within one character
  time: about 1 ms (2,000 T-states) at 9600 baud, half that at 19200. 9600 is
  the recommended rate.
- RTS/CTS flow control, on by default: RTS drops when the receive ring holds
  192 bytes and rises again at 64. The transmitter waits while CTS is low.
- A sector transfer keeps interrupts off for about 8 ms (section 5), about
  eight characters at 9600 baud. Before each transfer the floppy driver drops
  RTS, waits two character times with interrupts on so the ISR takes anything
  in flight, transfers, and restores RTS. Without flow control, serial input
  during disk access is lost and counted as overruns.
- Receive errors increment the counters below and set `POLLERR`. A byte with
  a framing or parity error is still stored.
- `open` raises DTR and RTS, no sooner than 100 ms after the last `close`
  dropped DTR. The last `close` waits up to 2 s for the transmit ring to
  drain, then drops DTR, which hangs up a modem set to `&D2`.

Hangup: with the `dcd` flag set, a falling DCD marks the device hung up.
Bytes already received stay readable; after them `read` returns 0, `poll`
reports `POLLHUP` and `write` is `EIO`. The state clears when DCD rises. The
flag is off by default, so a program can talk to a modem in command mode with
no carrier, and turns it on after `CONNECT`.

| Request | Name | `IX` | Result `HL` |
|---------|------|------|-------------|
| `0201h` | `SER_GETCFG` | Pointer to a 6-byte configuration | |
| `0202h` | `SER_SETCFG` | Pointer to a 6-byte configuration; applied after the transmit ring drains | |
| `0203h` | `SER_GETLINES` | | Bit 0 CTS, 1 DSR, 2 DCD, 3 RI |
| `0204h` | `SER_SETDTR` | `0` drop, `1` raise | |
| `0205h` | `SER_BREAK` | Ticks, 1-30; blocks while the break is sent | |
| `0206h` | `SER_STATS` | Pointer to an 8-byte record; the counters reset | |

Configuration record. Each first `open` starts from the defaults, and an
out-of-range value is `EINVAL`:

| Offset | Field | Values | Default |
|--------|-------|--------|---------|
| 0 | Baud code | `0`-`Fh` | `Eh`, 9600 |
| 1 | Data bits | 5-8 | 8 |
| 2 | Parity | 0 none, 1 odd, 2 even | 0 |
| 3 | Stop bits | 1-2 | 1 |
| 4 | Flags | Bit 0 RTS/CTS, bit 1 `dcd`, other bits 0 | `01h` |
| 5 | Reserved | 0 | 0 |

The statistics record is four 16-bit counters that stop at `FFFFh`:
overruns, framing errors, parity errors and bytes dropped because the receive
ring was full.

### Modem bridge

A Hayes-compatible "Wi-Fi modem", like the ESP8266 modems sold for retro
machines, on the serial port. The OS has no driver for it: programs send AT
commands through `/dev/ser0`. This section is the subset programs may rely on
and heh8080 must implement. Real modems implement more.

The bridge starts in command mode and returns to it after every hangup. In
online mode, after `CONNECT`, bytes pass through unchanged in both
directions: no telnet negotiation, no CR or LF translation, no escaping. A
program that talks to a telnet server handles IAC itself. The bridge always
uses RTS/CTS: it stops sending while RTS is low and drops CTS when its own
buffer is full.

A command line starts with `AT`, ends with CR (`0Dh`), ignores LF and case,
and is at most 80 characters. Several commands may share one `AT`, and a dial
must come last.

| Command | Effect |
|---------|--------|
| `AT` | `OK` |
| `ATZ` | Restore the defaults below, `OK` |
| `ATE0`, `ATE1` | Command echo off, on (default on) |
| `ATV0`, `ATV1` | Numeric, verbose results (default verbose) |
| `ATQ0`, `ATQ1` | Results sent, suppressed (default sent) |
| `AT&C0`, `AT&C1` | DCD always on, DCD follows the connection (default `&C1`) |
| `AT&D0`, `AT&D2` | Ignore DTR, DTR drop hangs up (default `&D2`) |
| `ATDT host:port` | Open a TCP connection. `ATD` and `ATDP` do the same. The host is a DNS name or dotted IPv4 address of up to 63 characters; the port is decimal, 23 when omitted |
| `ATH`, `ATH0` | Close the connection |
| `ATO` | Return to online mode |
| `ATI` | Identification lines, then `OK` |

Verbose results are CR LF, the text, CR LF. Numeric results are the code and
CR.

| Code | Text | Meaning |
|------|------|---------|
| 0 | `OK` | Command done |
| 1 | `CONNECT` | Connection open. Online mode starts after the result. A rate may follow (`CONNECT 9600`), so programs match the prefix |
| 3 | `NO CARRIER` | Connection refused, name lookup failed, or the connection closed |
| 4 | `ERROR` | Unknown command or bad syntax |
| 8 | `NO ANSWER` | No connection within 30 s |

Escape: one second with nothing sent, `+++`, and one more second with nothing
sent returns to command mode with the connection open, then `OK`. `ATO` goes
back online and `ATH` closes it. The guard times keep `+++` inside data safe.

When the remote side closes, or DTR drops under `&D2`, the bridge closes the
connection, drops DCD under `&C1`, sends `NO CARRIER` and returns to command
mode. A program with `dcd` set may see end of file before or after the
`NO CARRIER` bytes, and treats either one as the end of the session. Because
the last `close` of `/dev/ser0` drops DTR, every program starts with the
bridge in command mode. A program begins with `ATE0V1` and waits for `OK`.

heh8080's bridge opens real TCP connections from the host and paces bytes at
the configured baud rate, so end-to-end tests can dial a listener the test
starts on `127.0.0.1`.

## 10. Toolchain and testing

- Kernel and boot sector: Z80 assembly (sjasmplus).
- Programs: C with SDCC (`__sdcccall(1)`), plus assembly where size matters.
  The SDK provides the startup code, system call wrappers and a small libc.
- Host tools in this repo: `mkreloc` (bitmap from two links), `c5fs` (format,
  copy files in and out, install the kernel, `import` from TRSDOS/LDOS JV3 or
  DMK disks, `check` for consistency). They write raw 184,320 or 368,640 byte
  images, which heh8080 mounts directly.
- Tests boot images in heh8080's headless CP-500 machine, type keys and check
  the screen. The copyrighted ROM cannot go in CI, so the repo includes a stub
  ROM that implements only the contract in section 2 (boot sector load,
  restart jumps, NMI dispatch). The real ROM is used for manual and
  local tests.

### Build layout

- Z80 sources are assembled by sjasmplus 1.24.0 (`eng/install-sjasmplus.ps1`)
  through `eng/Z80.targets`, imported by `Microsoft.Build.NoTargets` projects
  that are part of `cp500-os.slnx`. Binaries, listings and symbol files go to
  `build/z80/`.
- `include/cp500.inc` holds the hardware equates shared by the stub ROM, the
  boot sector and the kernel: memory map, system page entry points, and every
  port with its bit names (`E0h`, `E4h`, `ECh`, `F0h-F3h`, `F4h`, `F8h`). The
  names and bit meanings follow heh8080's CP-500 devices.
- `rom/stub.asm` builds `build/z80/stub.rom`.
- `tests/fixtures/z80/` holds Z80 programs the tests assemble:
  `hello-boot.asm` (`build/z80/hello-boot.bin`) is a boot sector that writes
  `BOOT OK` to the top-left of the screen and spins with interrupts disabled;
  an assert fails the build if it outgrows 256 bytes. `reloc-sample.asm` is
  assembled at `0000h`, `0100h` and `6200h`; a test runs `mkreloc` on the
  first two and checks that relocating to page `62h` reproduces the third
  byte for byte.

### Stub ROM

`build/z80/stub.rom` is exactly 14 KiB (`0000h-37FFh`); unused bytes are
`FFh`.

| Address | Content |
|---------|---------|
| `0000h` | `DI`, `JP boot` |
| `0008h`-`0030h` | `JP 4000h`, `JP 4003h`, ..., `JP 400Fh` |
| `0038h` | `JP 4012h` |
| `0066h` | `JP 4049h` |

Boot, with interrupts disabled throughout:

1. `IM 1`, `SP = 4200h` (the boot stack page). Write `00h` to `E0h` and
   `E4h`: the timer IRQ is enabled at power-on, and `DI` does not stop NMI.
2. Select drive 0 in MFM (`F4h = 81h`), force-interrupt the FDC (`D0h`).
3. Restore (`0Bh`: head load, 30 ms steps) and wait for not-busy. Not ready
   or no track 0 is an error.
4. Read sector 1 (`80h`, track register already 0) into `4300h` by polling
   status: DRQ moves one byte with `INI`; busy clearing early is an error.
5. Wait for not-busy; any of not ready, record not found, CRC error or lost
   data (`9Ch`) is an error. Otherwise `JP 4300h`.

Every command write is followed by about 100 us before status is read, since
the WD1791 status is not valid for up to 56 us (FM). Every wait is bounded:
about 2 s for the sector (more than the five revolutions after which the
WD1791 reports record not found) and about 4.5 s for the restore (more than 40
steps at 30 ms). Waits reselect the drive, which retriggers the Model III
motor-on one-shot.

On failure the stub fills video RAM with spaces, writes one of these to the
top line and halts with interrupts disabled:

| Message | Meaning (last byte is the WD1791 status in hex) |
|---------|------------------------------------------------|
| `STUB ROM: RESTORE ERROR xx` | Drive not ready or not at track 0 after restore. heh8080 shows `A4` for an empty drive, `A0` with no drives installed |
| `STUB ROM: RESTORE TIMEOUT xx` | FDC still busy after the restore wait |
| `STUB ROM: READ ERROR xx` | Read failed: `10` record not found, `08` CRC, `04` lost data, `80` not ready |
| `STUB ROM: READ TIMEOUT xx` | No data or completion within the sector wait |

Differences from the real ROM. The boot sector must not depend on any of
these:

- The NMI vector jumps straight to `4049h`. The real ROM's `3039h` first
  checks `E4h` bit 5 and reboots while the reset button is held.
- No screen clear, logo, BREAK check, index-pulse wait (the real ROM waits
  for five index pulses to see that a disk spins) or `Diskette?` retry loop.
  Without a disk the stub stops with an error instead.
- The sector is read by polling, not with WAIT and the FDC NMI. That is
  exact in heh8080, whose controller has no byte deadline by default, but
  the 59 T-state polled byte loop is not guaranteed to keep up with MFM
  (about 65 T-states per byte) on real hardware. The stub is for the
  emulator only.
- At `4300h` the state differs: the real ROM leaves `SP` near `407Dh`,
  `E0h = 04h` (timer IRQ enabled but `DI`), `RETN` at `4049h`, its own data in
  `4000h-404Bh` and `41E5h-4224h`, and the video control latch at `ECh`
  written. The stub leaves `SP = 4200h`, both interrupt masks at `00h`, and
  does not write `ECh`. Its last `CALL` leaves the return address `C2 00` at
  `41FEh`. The boot sector must set its own stack and must not use `RST`, the
  system page or the interrupt masks before it has set them up.

## 11. Milestones

Milestone 8 is the current tree.

1. Tooling: assembler setup, `mkreloc`, `c5fs`, stub ROM, headless runner in
   heh8080.
2. Boot: boot sector, kernel banner, timer, keyboard, console with ANSI subset.
3. Read-only C5FS, program loader, single-tasking shell. The shell is the
   C5X file `/bin/sh`, loaded at page `62h`. Its first write places `sh>` on
   video row 3 and leaves the cursor on video row 4, column 0. Typed bytes
   are echoed on that input row. The kernel does not contain a shell. A disk
   with no `/bin/sh` halts after the banner and does not echo.
4. Writable C5FS, host `c5fs check`, core commands (`ls cp mv rm mkdir cat more date`),
   a full-screen editor.
5. Preemptive scheduling (eight tasks, quantum 2 ticks), `spawn`, `wait`,
   `yield`, `kill`, pipes, two virtual consoles (CLEAR plus a digit), cooked
   and raw BREAK, console `ioctl` (`01h` foreground, `02h` mode), zombie reap
   at the prompt, `/sys/keymap` with acute dead keys and Latin-1 glyphs, shell
   pipelines as `a ! b` and background `? cmd`.
6. Serial driver and modem bridge (heh8080 expansion), terminal program.
7. Virtual hard disk, partitions, clock.
8. W5100 network driver, sockets, `telnet`, `get` (HTTP), time sync.

## 12. Open questions

- 32-column mode: support it as a console option, or ignore it?
- Should `/tmp` become a RAM disk once a hard disk frees floppy space, or stay
  on disk?
- License for the repository.
