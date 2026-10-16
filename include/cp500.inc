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
CURSOR_BLOCK        equ 0BFh
K_DOWN              equ 1               ; keyboard table only, never a ring byte
K_LEFT              equ 2
K_RIGHT             equ 3

ARENA_BASE          equ 6200h

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

    endif
