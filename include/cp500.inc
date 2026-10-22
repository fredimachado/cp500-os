; Prologica CP-500 (TRS-80 Model III compatible) hardware equates.
; Shared by the stub ROM, the boot sector and the kernel. Port and bit meanings
; follow docs/design.md sections 2-3 and heh8080's CP-500 devices.

    ifndef CP500_INC
    define CP500_INC

; ---------------------------------------------------------------- memory map

ROM_BASE            equ 0000h
ROM_SIZE            equ 3800h           ; 14 KiB visible; the rest of the EPROM hides behind keyboard and video

KBD_BASE            equ 3800h           ; 8x8 matrix, active high; address bit n selects row n
KBD_SIZE            equ 0400h

VIDEO_BASE          equ 3C00h
VIDEO_COLS          equ 64
VIDEO_ROWS          equ 16
VIDEO_SIZE          equ VIDEO_COLS * VIDEO_ROWS

RAM_BASE            equ 4000h

; System page: the ROM's RST, IM 1 and NMI vectors jump here.
SYSPAGE             equ 4000h
SYS_RST08           equ 4000h           ; RST 08h, the system call
SYS_RST10           equ 4003h
SYS_RST18           equ 4006h
SYS_RST20           equ 4009h
SYS_RST28           equ 400Ch
SYS_RST30           equ 400Fh           ; RST 30h, the debugger breakpoint
SYS_ISR             equ 4012h           ; RST 38h / IM 1 interrupt
SYS_NMI             equ 4049h           ; NMI, FDC INTRQ

BOOT_STACK_BASE     equ 4100h
BOOT_STACK_TOP      equ 4200h           ; initial SP; the first push writes 41FFh

KERNEL_BASE         equ 4200h

BOOT_SECTOR         equ 4300h           ; the ROM loads track 0 sector 1 here and jumps to it
BOOT_SECTOR_SIZE    equ 256

; The boot sector runs from this copy. Superblocks and geometry bytes sit under it.
BOOT_HIGH           equ 0FF00h
SB_A                equ 0FE00h          ; superblock A, boot only
SB_B                equ 0FD00h          ; superblock B, boot only
BOOT_SIDES          equ 0FC00h          ; boot only
BOOT_SPT            equ 0FC01h          ; boot only

; Offsets inside one 256-byte superblock. Boot code uses these names.
SB_MAGIC            equ 0
SB_VERSION          equ 4
SB_FLAGS            equ 5
SB_SEQ              equ 6
SB_SIDES            equ 27
SB_TRACKS           equ 28
SB_SPT              equ 29
SB_KERNEL_START     equ 30
SB_KERNEL_COUNT     equ 32
SB_CRC              equ 254

; System-page bytes. One owner writes each address. See docs/design.md.
TICK_COUNT          equ 4015h           ; 4 bytes, little-endian, ISR writes
KBD_HEAD            equ 4019h           ; ISR writes, main reads
KBD_TAIL            equ 401Ah           ; main writes, ISR reads
KBD_REP_ROW         equ 401Bh           ; 0FFh means no repeat key
KBD_REP_COL         equ 401Ch
KBD_REP_AGE         equ 401Dh
KBD_PREV            equ 401Eh           ; 8 raw samples
KBD_RING            equ 4026h           ; 32 slots, ends at 4045h
KBD_RING_SIZE       equ 32
KBD_ACCEPTED        equ 404Ch           ; 8 debounced rows

CUR_ROW             equ 4054h
CUR_COL             equ 4055h
CUR_PHASE           equ 4056h           ; 0 hidden, 1 block
CUR_UNDER           equ 4057h
CUR_SHOWN           equ 4058h           ; 0 video holds CUR_UNDER, 1 video holds the block
ESC_ROW             equ 4059h
ESC_COL             equ 405Ah
ANSI_STATE          equ 405Bh           ; 0 ground, 1 esc, 2 csi
ANSI_P0             equ 405Ch
ANSI_P1             equ 405Dh
ANSI_N              equ 405Eh           ; parameters stored, 0 to 2
ANSI_ACC            equ 405Fh           ; digit accumulator, saturates at 255
ANSI_BAD            equ 4060h
BLINK_DIV           equ 4061h

ANSI_GROUND         equ 0
ANSI_ESC            equ 1
ANSI_CSI            equ 2
CURSOR_BLOCK        equ 0B0h
K_UP                equ 1               ; keyboard table only, never a ring byte
K_DOWN              equ 2
K_LEFT              equ 3
K_RIGHT             equ 4
K_BREAK             equ 5
K_CLEAR             equ 6

VOL                 equ 4062h
VOL_SIZE            equ 10
                assert VOL + VOL_SIZE == INO_BUF
; VOL..VOL_FIRST and vol_sb..vol_kcount are the bound volume window. /sys/dev swaps
; them across syscalls; kernel code must not cache them across RST 08h.
VOL_SIDES           equ VOL + 0
VOL_SPT             equ VOL + 1
VOL_BLOCKS          equ VOL + 2
VOL_ITABLE          equ VOL + 4
VOL_ICOUNT          equ VOL + 6
VOL_FIRST           equ VOL + 8

INO_BUF             equ 406Ch
TASK                equ 408Ch           ; the running task's record; T_LIVE[CUR] is stale while it runs
CUR                 equ 409Ch           ; running slot
KBUSY               equ 409Dh           ; 1 while a call or a switch runs; the ISR never switches then
QUANTUM             equ 409Eh           ; ISR counts down; 0 asks for a switch
CON_ACTIVE          equ 409Fh           ; console in video RAM
SC_FRAME            equ 40A0h           ; SP of the current call's frame
CON_BOUND           equ 40A2h           ; console whose state is in CUR_ROW..BLINK_DIV, 0FFh none
CON_PLANE_CUR       equ 40A3h           ; plane page of the bound console
CON_WANT            equ 40A4h           ; bit k: console k needs a shell
KBD_PREFIX          equ 40A5h           ; 0, K_CLEAR or a dead key
RUN_START           equ 40A6h           ; largest free run of arena pages
RUN_END             equ 40A7h           ; exclusive
T_STATE             equ 40A8h           ; 8 slots
T_CHAN              equ 40B0h
T_PARENT            equ 40B8h
T_ARG               equ 40C0h           ; 8 words
PIPE                equ 40D0h           ; 4 x state, page, head, tail
CON_STATE           equ 40E0h           ; per console: 0 no shell, 1 shell started
CON_PLANE           equ 40E2h           ; plane page per console, 3Ch while shown
CON_FG              equ 40E4h           ; foreground task per console, 0 none
CON_MODE            equ 40E6h           ; CON_FG + 2

KEYMAP              equ 0F000h          ; /sys/keymap: unshifted and shifted 8x8 tables
KBD_UNSHIFTED       equ KEYMAP
KBD_SHIFTED         equ KEYMAP + 64
ACUTE_FROM          equ KEYMAP + 128    ; 14 keys that compose after DEAD_ACUTE
ACUTE_TO            equ KEYMAP + 142    ; their ISO-8859-1 results
LAT1_GLYPH          equ KEYMAP + 156    ; video code for C0h-FFh
DEAD_ACUTE          equ 27h
SHADOW1             equ 0F100h          ; console 1's hidden screen
KPAGE               equ 0F500h
OWNER               equ KPAGE           ; owner of page ARENA_FIRST + i: 0 free, slot, 0FFh kernel
CON_BLOCK           equ KPAGE + 96h     ; 14 saved console bytes per console
KVARS               equ KPAGE + 0B2h
T_LIVE              equ KPAGE + 180h    ; 16-byte record per slot, TASK layout
OFILE               equ KPAGE + 200h
KPAGE_DEV           equ KPAGE + 280h
KPAGE_SNAP          equ KPAGE + 2F0h

TASK_ID             equ 0
TASK_BASE           equ 1
TASK_PAGES          equ 2
TASK_SP             equ 3
TASK_VOL            equ 5               ; cwd volume, always 0
TASK_FD             equ 6
TASK_CWD            equ 14              ; cwd inode

OF_KIND             equ 0
OF_REFS             equ 1
OF_INO              equ 2
OF_POS              equ 4
OF_STRIDE           equ 8

KIND_FREE           equ 0
KIND_CON_IN         equ 1
KIND_CON_OUT        equ 2
KIND_FILE           equ 3
KIND_DIR            equ 4
KIND_PIPE_R         equ 5
KIND_PIPE_W         equ 6
KIND_DEV            equ 7
KIND_SER            equ KIND_DEV + 0
KIND_HD             equ KIND_DEV + 1
KIND_NULL           equ KIND_DEV + 2
KIND_CON            equ KIND_DEV + 3
KIND_CON0           equ KIND_DEV + 4
KIND_CON1           equ KIND_DEV + 5
KIND_TTY            equ KIND_DEV + 6
KIND_FD0            equ KIND_DEV + 7
KIND_FD1            equ KIND_DEV + 8
KIND_FD2            equ KIND_DEV + 9
KIND_FD3            equ KIND_DEV + 10
KIND_PRN            equ KIND_DEV + 11
KIND_NET            equ KIND_DEV + 12

TASK_SLOTS          equ 8
TS_FREE             equ 0
TS_READY            equ 1               ; bit 0 is runnable
TS_BLOCKED          equ 2
TS_DYING            equ 3
TS_ZOMBIE           equ 4
QUANTUM_TICKS       equ 2
EXIT_KILLED         equ 0FFh

CH_KEY              equ 1
CH_TICK             equ 2
CH_CHILD            equ 3
CH_SER              equ 4
CH_SLEEP            equ 5
CH_PIPE             equ 8               ; + pipe

NCON                equ 2
NPIPE               equ 4
PIPE_R_OPEN         equ 1
PIPE_W_OPEN         equ 2

; User frame offsets from its SP. Syscall entry and the ISR push the same 22 bytes.
F_IY                equ 8
F_IX                equ 10
F_HL                equ 12
F_AF                equ 18
F_PC                equ 20
F_DE                equ 14
F_C                 equ 16
F_B                 equ 17
FRAME_SIZE          equ 22

INO_TYPE            equ 0
INO_EXTENTS         equ 1
INO_SIZE            equ 2
INO_MOD             equ 5
INO_CREATE          equ 9
INO_EXT0            equ 13
INO_RES             equ 31
INO_KIND_FILE       equ 1
INO_KIND_DIR        equ 2
INO_RO              equ 10h
INO_HIDDEN          equ 20h
INO_INDIRECT        equ 40h

BLK_BUF             equ 6100h
ARENA_BASE          equ 6200h

; Resident write routines, loaded from /sys/wr. Not part of the 8 KiB kernel.
WR_BASE             equ 0F800h
WR_MKDIR            equ WR_BASE
WR_REMOVE           equ WR_BASE + 3
WR_RENAME           equ WR_BASE + 6
WR_OPEN             equ WR_BASE + 9
WR_WRITE            equ WR_BASE + 12
WR_SYNC             equ WR_BASE + 15
WR_TIME             equ WR_BASE + 18
WR_SET              equ WR_BASE + 21
ARENA_FIRST         equ 62h
ARENA_LAST          equ 0EFh            ; last page programs and pipes may use
KERNEL_RESERVE      equ 192
PATH_MAX            equ 127
ARGV_MAX            equ 128
FD_SLOTS            equ 8
OFILE_SLOTS         equ 16

; ------------------------------------------------------------ interrupts E0h-E7h

; OUT: IRQ mask. IN: active-low IRQ status, ~(mask & pending).
PORT_IRQ            equ 0E0h
IRQ_TIMER_BIT       equ 2               ; 30 Hz timer, latched until PORT_TIMER_ACK is read
IRQ_TIMER           equ 1 << IRQ_TIMER_BIT

; OUT: NMI mask. IN: active-low NMI status, ~(mask & sources).
PORT_NMI            equ 0E4h
NMI_RESET_BIT       equ 5               ; IN: 0 while the reset button is held (not modelled by heh8080)
NMI_FDC_BIT         equ 7               ; FDC INTRQ, mirrors the live line
NMI_RESET           equ 1 << NMI_RESET_BIT
NMI_FDC             equ 1 << NMI_FDC_BIT

; ------------------------------------------------------- timer ack / video ECh-EFh

; IN: acknowledges the timer IRQ, returns 00h. OUT: video control latch.
PORT_TIMER_ACK      equ 0ECh
PORT_VIDEO          equ 0ECh
VIDEO_32COL_BIT     equ 2               ; 32-column (double width) characters
VIDEO_ALTCHARS_BIT  equ 3               ; C0h-FFh use the alternate (katakana) character set
VIDEO_32COL         equ 1 << VIDEO_32COL_BIT
VIDEO_ALTCHARS      equ 1 << VIDEO_ALTCHARS_BIT

; ------------------------------------------------------- WD1791 FDC F0h-F3h

FDC_COMMAND         equ 0F0h            ; OUT
FDC_STATUS          equ 0F0h            ; IN; reading clears INTRQ
FDC_TRACK           equ 0F1h
FDC_SECTOR          equ 0F2h
FDC_DATA            equ 0F3h

; Status bits. Bits 1, 2 and 5 mean different things after Type I commands
; (restore, seek, step) and Type II/III commands (read, write).
FDC_BUSY_BIT        equ 0
FDC_DRQ_BIT         equ 1               ; Type II/III: data register wants a transfer
FDC_INDEX_BIT       equ 1               ; Type I: index hole under the sensor
FDC_LOST_DATA_BIT   equ 2               ; Type II/III: the CPU missed a byte
FDC_TRACK0_BIT      equ 2               ; Type I: head at track 0
FDC_CRC_ERROR_BIT   equ 3
FDC_NOT_FOUND_BIT   equ 4               ; record (or, after a verify, track) not found
FDC_RECORD_TYPE_BIT equ 5               ; read: deleted data mark
FDC_HEAD_LOADED_BIT equ 5               ; Type I
FDC_WRITE_FAULT_BIT equ 5               ; write
FDC_WRITE_PROT_BIT  equ 6
FDC_NOT_READY_BIT   equ 7

FDC_BUSY            equ 1 << FDC_BUSY_BIT
FDC_DRQ             equ 1 << FDC_DRQ_BIT
FDC_INDEX           equ 1 << FDC_INDEX_BIT
FDC_LOST_DATA       equ 1 << FDC_LOST_DATA_BIT
FDC_TRACK0          equ 1 << FDC_TRACK0_BIT
FDC_CRC_ERROR       equ 1 << FDC_CRC_ERROR_BIT
FDC_NOT_FOUND       equ 1 << FDC_NOT_FOUND_BIT
FDC_RECORD_TYPE     equ 1 << FDC_RECORD_TYPE_BIT
FDC_HEAD_LOADED     equ 1 << FDC_HEAD_LOADED_BIT
FDC_WRITE_FAULT     equ 1 << FDC_WRITE_FAULT_BIT
FDC_WRITE_PROT      equ 1 << FDC_WRITE_PROT_BIT
FDC_NOT_READY       equ 1 << FDC_NOT_READY_BIT

; Commands (high nibble) and their flags.
FDC_CMD_RESTORE     equ 00h
FDC_CMD_SEEK        equ 10h
FDC_CMD_STEP        equ 20h
FDC_CMD_STEP_IN     equ 40h
FDC_CMD_STEP_OUT    equ 60h
FDC_CMD_READ        equ 80h
FDC_CMD_WRITE       equ 0A0h
FDC_CMD_READ_ADDR   equ 0C0h
FDC_CMD_FORCE_INT   equ 0D0h
FDC_CMD_READ_TRACK  equ 0E0h
FDC_CMD_WRITE_TRACK equ 0F0h

; Type I
FDC_STEP_6MS        equ 00h             ; step rates with the Model III's 1 MHz FDC clock
FDC_STEP_12MS       equ 01h
FDC_STEP_20MS       equ 02h
FDC_STEP_30MS       equ 03h
FDC_VERIFY          equ 04h
FDC_HEAD_LOAD       equ 08h
FDC_UPDATE_TRACK    equ 10h             ; step commands
; Type II/III
FDC_DELETED_MARK    equ 01h             ; write: deleted data address mark
FDC_SIDE_COMPARE    equ 02h
FDC_SETTLE_DELAY    equ 04h             ; 15 ms head settle before the command
FDC_SIDE_ONE        equ 08h             ; with FDC_SIDE_COMPARE
FDC_MULTI_SECTOR    equ 10h
; Force interrupt (Type IV)
FDC_INT_ON_INDEX    equ 04h
FDC_INT_NOW         equ 08h

; --------------------------------------------------- disk control F4h-F7h

; OUT only: drive select, side, WAIT, density. Never IN from F4h-F7h: on the
; CP-500 every read toggles the ROM A11 flip-flop.
PORT_DISK           equ 0F4h
DISK_DRIVE0         equ 01h
DISK_DRIVE1         equ 02h
DISK_DRIVE2         equ 04h
DISK_DRIVE3         equ 08h
DISK_SIDE1_BIT      equ 4
DISK_WAIT_BIT       equ 6               ; hold the CPU in WAIT until DRQ or INTRQ
DISK_MFM_BIT        equ 7               ; set MFM (double density), clear FM
DISK_SIDE1          equ 1 << DISK_SIDE1_BIT
DISK_WAIT           equ 1 << DISK_WAIT_BIT
DISK_MFM            equ 1 << DISK_MFM_BIT

; ------------------------------------------------------------- printer F8h

; OUT: data. IN: status.
PORT_PRINTER        equ 0F8h
PRN_FAULT_BIT       equ 4               ; 1 = no fault
PRN_SELECT_BIT      equ 5
PRN_PAPER_OUT_BIT   equ 6
PRN_BUSY_BIT        equ 7
PRN_FAULT           equ 1 << PRN_FAULT_BIT
PRN_SELECT          equ 1 << PRN_SELECT_BIT
PRN_PAPER_OUT       equ 1 << PRN_PAPER_OUT_BIT
PRN_BUSY            equ 1 << PRN_BUSY_BIT

; --------------------------------------------------------------- syscalls

SYS_EXIT            equ 00h
SYS_SPAWN           equ 01h
SYS_WAIT            equ 02h
SYS_GETPID          equ 03h
SYS_YIELD           equ 04h
SYS_SLEEP           equ 05h
SYS_KILL            equ 06h
SYS_UPTIME          equ 07h
SYS_ALLOC           equ 10h
SYS_FREE            equ 11h
SYS_MEMINFO         equ 12h
SYS_OPEN            equ 20h
SYS_CLOSE           equ 21h
SYS_READ            equ 22h
SYS_WRITE           equ 23h
SYS_SEEK            equ 24h
SYS_STAT            equ 25h
SYS_FSTAT           equ 26h
SYS_READDIR         equ 27h
SYS_MKDIR           equ 28h
SYS_REMOVE          equ 29h
SYS_RENAME          equ 2Ah
SYS_CHDIR           equ 2Bh
SYS_GETCWD          equ 2Ch
SYS_DUP2            equ 2Dh
SYS_PIPE            equ 2Eh
SYS_IOCTL           equ 2Fh
SYS_SYNC            equ 30h
SYS_POLL            equ 31h
SYS_TIME            equ 40h
SYS_SETTIME         equ 41h
SYS_SOCKET          equ 50h
SYS_CONNECT         equ 51h
SYS_LISTEN          equ 52h
SYS_ACCEPT          equ 53h
SYS_SEND            equ 54h
SYS_RECV            equ 55h
SYS_SOCKCLOSE       equ 56h
SYS_RESOLVE         equ 57h

SOCK_NONBLOCK       equ 1

PORT_W5_MR          equ 0D0h
PORT_W5_AR0         equ 0D1h
PORT_W5_AR1         equ 0D2h
PORT_W5_DR          equ 0D3h
W5_MR_IND           equ 03h

IOCTL_SETFG         equ 01h             ; IX = foreground task, 0 none
IOCTL_SETMODE       equ 02h             ; IX = console mode bits
CON_GETHIST         equ 5               ; IX = slot byte then 128-byte line
CON_PUTHIST         equ 6               ; IX = null-terminated line
CON_RAW             equ 01h             ; BREAK reads as KEY_BREAK, no dead keys
HIST_LINES          equ 4
HIST_LINE           equ 128
HIST_META           equ 4               ; head, count, pad, pad per console
HIST_CON_SIZE       equ HIST_META + HIST_LINES * HIST_LINE
HIST_PAGE           equ 0BFh              ; below SER/DEV (D4h+); not the E8h arena/SER alias
OWNER_HIST          equ 0FEh              ; keeps CON_HIST pages out of the program arena
HIST_PAGES          equ 5
CON_HIST            equ HIST_PAGE << 8
                assert CON_HIST + NCON * HIST_CON_SIZE <= (HIST_PAGE + HIST_PAGES) << 8
KEY_BREAK           equ 03h

POLLIN              equ 01h
POLLOUT             equ 02h
POLLHUP             equ 04h
POLLERR             equ 08h
POLLNVAL            equ 10h
POLL_ALWAYS         equ POLLHUP | POLLERR | POLLNVAL
POLL_ENTRY          equ 3
POLL_MAX            equ 8
POLL_FOREVER        equ 0FFFFh

SER_CLASS           equ 02h
SER_GETCFG          equ 0201h
SER_SETCFG          equ 0202h
SER_GETLINES        equ 0203h
SER_SETDTR          equ 0204h
SER_BREAK           equ 0205h
SER_STATS           equ 0206h
CFG_BAUD            equ 0
CFG_DATA            equ 1
CFG_PARITY          equ 2
CFG_STOP            equ 3
CFG_FLAGS           equ 4
CFG_RESERVED        equ 5
CFG_SIZE            equ 6
CFG_F_RTSCTS        equ 01h
CFG_F_DCD           equ 02h
STATS_SIZE          equ 8

HOOK_DISK           equ 10h
HOOK_CALL           equ 18h
HOOK_CLOSE          equ 20h
HOOK_INODE          equ 28h
HOOK_SLOT           equ SYS_RST10
                assert SYS_RST18 == HOOK_SLOT + 3 && SYS_RST20 == HOOK_SLOT + 6
                assert SYS_RST28 == HOOK_SLOT + 9

; Pages below the old base hold the six new calls and the extra devices.
; The 8 KiB kernel and the device image have no room for them.
SER_PAGES           equ 13
SER_BASE            equ 0D400h
SEV_OPEN            equ SER_BASE
SEV_READ            equ SER_BASE + 3
SEV_WRITE           equ SER_BASE + 6
SEV_IOCTL           equ SER_BASE + 9
SEV_CLOSE           equ SER_BASE + 12
SEV_REVENTS         equ SER_BASE + 15
SEV_TICK            equ SER_BASE + 18
SEV_IRQ             equ SER_BASE + 21
SEV_DISK            equ SER_BASE + 24
SEV_MASK            equ SER_BASE + 27
; Fixed jumps in /sys/ser. The bodies sit above ser_body and below the
; syscall block, so editing a body does not move these addresses.
EXT_OPEN            equ 0DAC0h
EXT_GO              equ 0DAC3h
BOOT_BODY           equ 0DAC6h
SEEK_BODY           equ 0DAC9h
FD_ROUTE            equ 0DACCh
FD_DRV              equ 0DACFh

DEV_PAGES           equ 15
DEV_BASE            equ (ARENA_LAST + 1 - DEV_PAGES) << 8
DEV_INIT            equ DEV_BASE
DEV_V_OK            equ DEV_BASE + 3
DEV_V_ERR           equ DEV_BASE + 6
DEV_V_EINVAL        equ DEV_BASE + 9
DEV_V_RWSHORT       equ DEV_BASE + 12
DEV_SLEEP           equ DEV_BASE + 15
DEV_UPTIME          equ DEV_BASE + 18
DEV_ALLOC           equ DEV_BASE + 21
DEV_FREE            equ DEV_BASE + 24
DEV_MEMINFO         equ DEV_BASE + 27
DEV_DUP2            equ DEV_BASE + 30
DEV_SEEK            equ DEV_BASE + 33
DEV_INIT_BOOT       equ DEV_BASE + 36
VB_ENT              equ DEV_BASE + 39
DEV_BANNER          equ DEV_BASE + 42
; Fixed tails of /sys/ser. Each one jumps to the body. The bodies sit
; under this table, so editing a body does not move the address dev calls.
SC_SLEEP            equ 0E0EDh
SC_UPTIME           equ 0E0F0h
SC_ALLOC            equ 0E0F3h
SC_FREE             equ 0E0F6h
SC_MEMINFO          equ 0E0F9h
SC_DUP2             equ 0E0FCh
SC_HIST             equ 0DE25h
SER_SIZE            equ 31
SER_REC             equ DEV_BASE + DEV_PAGES * 256 - SER_SIZE
SER                 equ SER_REC

PORT_HD_CLOCK       equ 0C2h
PORT_HD_CMD2        equ 0C4h
HD_GET_TIME         equ 01h
PORT_HD_DATA        equ 0C8h
PORT_HD_ERROR       equ 0C9h
PORT_HD_COUNT       equ 0CAh
PORT_HD_SECTOR      equ 0CBh
PORT_HD_CYL_LO      equ 0CCh
PORT_HD_CYL_HI      equ 0CDh
PORT_HD_SDH         equ 0CEh
PORT_HD_STATUS      equ 0CFh
HD_PROBE_VAL        equ 07h
HD_BUSY             equ 80h
HD_WF               equ 20h
HD_DRQ              equ 08h
HD_ERR              equ 01h
HD_CMD_READ         equ 20h
HD_CMD_WRITE        equ 30h

PORT_SER_MODEM      equ 0E8h
PORT_SER_RESET      equ 0E8h
PORT_SER_BAUD       equ 0E9h
PORT_SER_STATUS     equ 0EAh
PORT_SER_CTL        equ 0EAh
PORT_SER_DATA       equ 0EBh

SER_MS_CTS_BIT      equ 7
SER_MS_DSR_BIT      equ 6
SER_MS_DCD_BIT      equ 5
SER_MS_RI_BIT       equ 4

SER_ST_DR_BIT       equ 7
SER_ST_THRE_BIT     equ 6
SER_ST_OE_BIT       equ 5
SER_ST_FE_BIT       equ 4
SER_ST_PE_BIT       equ 3
SER_ST_DR           equ 1 << SER_ST_DR_BIT
SER_ST_THRE         equ 1 << SER_ST_THRE_BIT

SER_CT_DTR          equ 01h
SER_CT_RTS          equ 02h
SER_CT_BREAK        equ 04h
SER_CT_NOPARITY     equ 08h
SER_CT_STOP2        equ 10h
SER_CT_WLEN_SHIFT   equ 5
SER_CT_EVEN         equ 80h

IRQ_SER_TX_BIT      equ 4
IRQ_SER_RX_BIT      equ 5
IRQ_SER_ERR_BIT     equ 6
IRQ_SER_TX          equ 1 << IRQ_SER_TX_BIT
IRQ_SER_RX          equ 1 << IRQ_SER_RX_BIT

S_PHASE             equ 0
S_RXPG              equ 1
S_TXPG              equ 2
S_RXH               equ 3
S_RXT               equ 4
S_TXH               equ 5
S_TXT               equ 6
S_CFG               equ 7
S_LINE              equ 13
S_HI_SET            equ 14
S_HI_CLR            equ 15
S_ERR_SET           equ 16
S_ERR_SEEN          equ 17
S_GAP               equ 18
S_BRK               equ 19
S_LINGER            equ 20
S_STATS             equ 21
S_DELAY             equ 29
PH_CLOSED           equ 0
PH_OPEN             equ 1
PH_LINGER           equ 2
LN_DTR              equ 01h
LN_DISK             equ 02h
LN_HUNG             equ 04h
LN_DCD              equ 08h
SER_RX_HIGH         equ 192
SER_RX_LOW          equ 64
SER_TX_WAKE         equ 128
DTR_GAP_TICKS       equ 4
LINGER_TICKS        equ 60
BREAK_MAX           equ 30
CPU_HZ              equ 2027520

O_READ              equ 01h
O_WRITE             equ 02h
O_CREATE            equ 04h
O_TRUNC             equ 08h
O_APPEND            equ 10h
O_EXCL              equ 20h

ENOENT              equ 1
EEXIST              equ 2
ENOMEM              equ 3
EBADF               equ 4
EINVAL              equ 5
ENOSPC              equ 6
EIO                 equ 7
ENOTDIR             equ 8
EISDIR              equ 9
ENOEXEC             equ 10
EMFILE              equ 11
ECHILD              equ 12
EROFS               equ 13
ENOTEMPTY           equ 14
EBUSY               equ 15
EAGAIN              equ 16
ECHANGED            equ 17
ENODEV              equ 18

    endif
