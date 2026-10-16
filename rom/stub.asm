; cp500-os stub boot ROM.
;
; Stands in for the copyrighted CP-500 ROM in CI. It implements only the ROM
; contract in docs/design.md section 2: load track 0 sector 1 of drive 0 to
; 4300h and jump there, and forward RST 08h-30h, IM 1 and NMI to the system
; page. Section 10 lists where it differs from the real ROM.

    include "cp500.inc"

READ_ERRORS         equ FDC_NOT_READY | FDC_NOT_FOUND | FDC_CRC_ERROR | FDC_LOST_DATA
DRIVE0_MFM          equ DISK_DRIVE0 | DISK_MFM

    org ROM_BASE

    di
    jp boot

    macro vector address, target
        ds address - $, 0FFh
        jp target
    endm

    vector 0008h, SYS_RST08
    vector 0010h, SYS_RST10
    vector 0018h, SYS_RST18
    vector 0020h, SYS_RST20
    vector 0028h, SYS_RST28
    vector 0030h, SYS_RST30
    vector 0038h, SYS_ISR
    ; The real ROM first checks the reset button on PORT_NMI bit 5; the stub does not.
    vector 0066h, SYS_NMI

boot:
    im 1
    ld sp, BOOT_STACK_TOP
    ; The timer IRQ is enabled at power-on; DI alone does not stop the NMI.
    xor a
    out (PORT_IRQ), a
    out (PORT_NMI), a

    ld a, DRIVE0_MFM
    out (PORT_DISK), a
    ld a, FDC_CMD_FORCE_INT
    call fdc_command

    ld a, FDC_CMD_RESTORE | FDC_HEAD_LOAD | FDC_STEP_30MS
    call fdc_command
    call fdc_wait_idle
    ld hl, msg_restore_timeout
    jr c, fail
    ld hl, msg_restore_error
    bit FDC_NOT_READY_BIT, a
    jr nz, fail
    bit FDC_TRACK0_BIT, a
    jr z, fail

    ld a, 1
    out (FDC_SECTOR), a
    ld a, FDC_CMD_READ
    call fdc_command

    ld hl, BOOT_SECTOR
    ld bc, BOOT_SECTOR_SIZE % 256 << 8 | FDC_DATA
    ; 65536 polls of 63 T-states is about 2 s: longer than the 5 revolutions
    ; (1 s) after which the WD1791 gives up with record not found.
    ld de, 0
.poll:
    in a, (FDC_STATUS)
    bit FDC_DRQ_BIT, a
    jr nz, .byte
    rrca                                ; busy into carry
    jr nc, .ended
    dec de
    ld a, d
    or e
    jr nz, .poll
    in a, (FDC_STATUS)
    ld hl, msg_read_timeout
    jr fail
.byte:
    ini
    jr nz, .poll

    call fdc_wait_idle
    ld hl, msg_read_timeout
    jr c, fail
    and READ_ERRORS
    jp z, BOOT_SECTOR
.ended:
    in a, (FDC_STATUS)
    ld hl, msg_read_error
    ; fall through

; Clears the screen, shows "STUB ROM: <message at HL> <A in hex>" on the top
; line and halts with interrupts disabled.
fail:
    push af
    push hl
    ld hl, VIDEO_BASE
    ld de, VIDEO_BASE + 1
    ld bc, VIDEO_SIZE - 1
    ld (hl), ' '
    ldir
    ld de, VIDEO_BASE
    ld hl, msg_prefix
    call puts
    pop hl
    call puts
    ld a, ' '
    ld (de), a
    inc de
    pop af
    call put_hex
.halt:
    di
    halt
    jr .halt

; Copies the zero-terminated string at HL to DE.
puts:
    ld a, (hl)
    or a
    ret z
    ld (de), a
    inc hl
    inc de
    jr puts

put_hex:
    push af
    rrca
    rrca
    rrca
    rrca
    call put_nibble
    pop af
put_nibble:
    and 0Fh
    add a, '0'
    cp '9' + 1
    jr c, .digit
    add a, 'A' - '9' - 1
.digit:
    ld (de), a
    inc de
    ret

; Writes the command in A. The WD1791 status register is not valid until
; up to 56 us (FM) after a command write; this waits about 100 us.
fdc_command:
    out (FDC_COMMAND), a
    ld b, 16
.settle:
    djnz .settle
    ret

; Waits for the FDC to finish. Returns the status in A with carry clear, or
; carry set if it is still busy after 2 x 65536 polls of 70 T-states (about
; 4.5 s), longer than a 40-track restore at 30 ms per step.
fdc_wait_idle:
    ld b, 2
    ld de, 0
.loop:
    ; Reselecting retriggers the Model III drive motor one-shot, which
    ; otherwise turns the motor off during a long wait.
    ld a, DRIVE0_MFM
    out (PORT_DISK), a
    in a, (FDC_STATUS)
    bit FDC_BUSY_BIT, a
    jr z, .idle
    dec de
    ld a, d
    or e
    jr nz, .loop
    djnz .loop
    in a, (FDC_STATUS)
    scf
    ret
.idle:
    or a
    ret

msg_prefix:             db "STUB ROM: ", 0
msg_restore_error:      db "RESTORE ERROR", 0
msg_restore_timeout:    db "RESTORE TIMEOUT", 0
msg_read_error:         db "READ ERROR", 0
msg_read_timeout:       db "READ TIMEOUT", 0

    assert $ <= ROM_SIZE, "stub ROM is larger than the 14 KiB ROM"
    ds ROM_SIZE - $, 0FFh
