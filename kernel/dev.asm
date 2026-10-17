; /sys/dev — device table, poll, and RST hook targets.

                include "kernel.sym"

SER_SIZE            equ 35
SER_REC             equ DEV_BASE + DEV_PAGES * 256 - SER_SIZE
SER                 equ SER_REC

                org DEV_BASE

dev_init:
                ld hl, OWNER + (DEV_BASE >> 8)
                ld b, DEV_PAGES
di_own:
                ld (hl), 0FFh
                inc hl
                djnz di_own
                ld hl, SER
                ld bc, SER_SIZE
                xor a
init_s0:
                ld (hl), a
                inc hl
                dec bc
                ld a, b
                or c
                jr nz, init_s0
                ld a, DTR_GAP_TICKS
                ld (SER + S_GAP), a
                out (PORT_SER_RESET), a
                call mask_out
                ld hl, hook_jumps
                ld de, HOOK_SLOT
                ld bc, 9
                ldir
                ld hl, dev_isr
                ld (SYS_ISR + 1), hl
                ei
                ret

hook_jumps:
                jp ser_disk
                jp dev_call
                jp dev_close

DR_NAME             equ 0
DR_OPEN             equ 2
DR_READ             equ 4
DR_WRITE            equ 6
DR_IOCTL            equ 8
DR_CLOSE            equ 10
DR_REVENTS          equ 12
DR_SIZE             equ 14

dev_table:
                dw ser0_name, ser_open, ser_read, ser_write, ser_ioctl, ser_close, ser_revents
dev_table_end:
DEV_ROWS            equ (dev_table_end - dev_table) / DR_SIZE
                assert KIND_SER == KIND_DEV + 0 && DEV_ROWS == 1
ser0_name:      db "/dev/ser0", 0

dev_call:
                push af
                ld a, (KBUSY)
                or a
                jr nz, dc_busy
                pop af
                ret
dc_busy:
                ld ix, (SC_FRAME)
                ld a, (ix + F_C)
                cp SYS_OPEN
                jp z, dc_open
                cp SYS_POLL
                jp z, dc_poll
                cp SYS_READ
                jr z, dc_rw
                cp SYS_WRITE
                jr z, dc_rw
                cp SYS_IOCTL
                jp z, dc_ioctl
                pop af
                ret
dc_ioctl:
                pop af
                cp KIND_DEV
                jr c, dc_ret
                sub KIND_DEV
                cp DEV_ROWS
                jr nc, dc_ret
                jp ser_ioctl
dc_open:
                pop af
                jp dev_open
dc_poll:
                pop af
                jp dev_poll
dc_rw:
                pop af
                cp KIND_DEV
                jr c, dc_ret
                sub KIND_DEV
                cp DEV_ROWS
                jr nc, dc_ret
                add a, a
                add a, a
                add a, a
                ld e, a
                ld d, 0
                ld hl, dev_table
                add hl, de
                ld a, (ix + F_C)
                cp SYS_READ
                jr z, dc_rd
                cp SYS_WRITE
                jr z, dc_wr
                inc hl
                inc hl
                inc hl
                inc hl
                inc hl
                inc hl
                ld e, (hl)
                inc hl
                ld d, (hl)
                ex de, hl
                jp (hl)
dc_rd:
                inc hl
                inc hl
                ld e, (hl)
                inc hl
                ld d, (hl)
                ex de, hl
                jp (hl)
dc_wr:
                inc hl
                inc hl
                inc hl
                inc hl
                ld e, (hl)
                inc hl
                ld d, (hl)
                ex de, hl
                jp (hl)
dc_ret:
                ret

dev_open:
                push de
                ld hl, (io_path)
                ld de, ser0_name
do_cmp:
                ld a, (de)
                cp (hl)
                jr nz, do_nomatch
                inc hl
                inc de
                or a
                jr nz, do_cmp
                ld a, (open_flags)
                and O_CREATE | O_TRUNC | O_APPEND | O_EXCL
                jp nz, dev_err_einval
                jp ser_open
do_nomatch:
                pop de
                ret

dev_close:
                push af
                ld a, (KBUSY)
                or a
                jr nz, dc_kind
                pop af
                ret
dc_kind:
                pop af
                cp KIND_SER
                ret nz
                jp ser_close

dev_isr:
                push af
                ld a, (SER + S_PHASE)
                or a
                jr nz, di_serial
dv_tick:
                push bc
                push de
                push hl
                call ser_tick
                ld a, CH_TICK
                call wake
                pop hl
                pop de
                pop bc
                pop af
                jp isr
di_serial:
                in a, (PORT_IRQ)
                ld b, a
                bit IRQ_SER_RX_BIT, b
                jr z, di_rx
                bit IRQ_SER_TX_BIT, b
                jr z, di_tx
                jr dv_tick
di_rx:
                push bc
                push de
                push hl
                ld a, b
                call ser_irq
                pop hl
                pop de
                pop bc
                bit IRQ_TIMER_BIT, b
                jr z, di_done
                jr dv_tick
di_tx:
                push bc
                push de
                push hl
                ld a, b
                call ser_irq
                pop hl
                pop de
                pop bc
                bit IRQ_TIMER_BIT, b
                jr z, di_done
                jr dv_tick
di_done:
                pop af
                ei
                reti

dev_poll:
                ld ix, (SC_FRAME)
                ld a, (ix + F_B)
                or a
                jp z, dev_err_einval
                cp POLL_MAX + 1
                jp nc, dev_err_einval
                ld b, a
                ld c, 0
                ld hl, (ix + F_DE)
dp_scan:
                push bc
                push hl
                ld a, (hl)
                call poll_one
                ld e, a
                pop hl
                inc hl
                ld a, (hl)
                inc hl
                ld d, a
                ld a, e
                push af
                and d
                and POLLIN | POLLOUT
                ld e, a
                pop af
                and POLL_ALWAYS
                or e
                ld (hl), a
                dec hl
                dec hl
                pop bc
                or a
                jr z, dp_next
                inc c
dp_next:
                ld de, POLL_ENTRY
                add hl, de
                djnz dp_scan
                ld a, c
                or a
                jr nz, dev_ok_a
                ld hl, (ix + F_HL)
                ld a, h
                or l
                jp z, dev_ok_z
                ld de, POLL_FOREVER
                or a
                sbc hl, de
                jp z, dp_forever
                ld a, (ix + F_HL)
                or a
                jp z, dev_ok_z
                ld hl, (TICK_COUNT)
                ld a, h
                and 7Fh
                ld h, a
                ld b, h
                ld c, l
                ld a, (CUR)
                add a, a
                add a, T_ARG & 0FFh
                ld e, a
                ld d, T_ARG >> 8
                ld a, (de)
                ld l, a
                inc de
                ld a, (de)
                ld h, a
                push hl
                pop de
                bit 7, d
                jr z, dp_arm
                ld hl, bc
                ld a, d
                and 7Fh
                ld d, a
                or a
                sbc hl, de
                ld de, (ix + F_HL)
                or a
                sbc hl, de
                jp nc, dev_ok_z
                jr dp_forever
dp_arm:
                ld hl, bc
                ld a, h
                or 80h
                ld d, a
                ld e, l
                ld a, (CUR)
                add a, a
                add a, T_ARG & 0FFh
                ld l, a
                ld h, T_ARG >> 8
                ld (hl), e
                inc l
                ld (hl), d
dp_forever:
                ld a, CH_TICK
                jp block_retry

dev_ok_a:
                ld l, a
                ld h, 0
                jp dev_ok
dev_ok_z:
                xor a
                ld h, a
                ld l, a
                jp dev_ok

poll_one:
                cp FD_SLOTS
                jp nc, po_nval
                ld e, a
                ld d, 0
                ld hl, TASK + TASK_FD
                add hl, de
                ld a, (hl)
                cp 0FFh
                jp z, po_nval
                call ofile_of
                ld a, (hl)
                cp KIND_FREE
                jp z, po_nval
                cp KIND_CON_IN
                jp z, po_con_in
                cp KIND_CON_OUT
                jp z, po_out
                cp KIND_FILE
                jp z, po_both
                cp KIND_DIR
                jp z, po_both
                cp KIND_PIPE_R
                jp z, po_pr
                cp KIND_PIPE_W
                jp z, po_pw
                cp KIND_DEV
                jp nc, po_dev
                xor a
                ret
po_nval:
                ld a, POLLNVAL
                ret
po_out:
                ld a, POLLOUT
                ret
po_both:
                ld a, POLLIN | POLLOUT
                ret
po_con_in:
                inc hl
                inc hl
                ld b, (hl)
                ld a, (CON_ACTIVE)
                cp b
                jr nz, po_cin0
                ld hl, KBD_HEAD
                ld a, (hl)
                ld hl, KBD_TAIL
                cp (hl)
                jr z, po_cin0
                ld a, POLLIN
                ret
po_cin0:
                xor a
                ret
po_pr:
                call pipe_of
                push hl
                inc l
                ld d, (hl)
                inc l
                ld e, (hl)
                inc l
                ld a, (hl)
                sub e
                pop hl
                ld a, POLLIN
                jr nz, po_prh
                bit 1, (hl)
                jr nz, po_pr0
                ld a, POLLIN | POLLHUP
                ret
po_prh:
                ret
po_pr0:
                xor a
                ret
po_pw:
                call pipe_of
                bit 0, (hl)
                jr nz, po_pwr
                ld a, POLLOUT | POLLERR
                ret
po_pwr:
                inc l
                ld d, (hl)
                inc l
                ld a, (hl)
                inc l
                ld e, (hl)
                scf
                sbc a, e
                jr nz, po_pwok
                xor a
                ret
po_pwok:
                ld a, POLLOUT
                ret
po_dev:
                call ofile_of
                jp ser_revents

dev_ok:
                call dev_clear_targ
                jp syscall_ok
dev_err:
                push af
                call dev_clear_targ
                pop af
                ld hl, 0
                scf
                jp syscall_err
dev_err_einval:
                ld a, EINVAL
                jp dev_err
dev_clear_targ:
                ld a, (CUR)
                add a, a
                add a, T_ARG & 0FFh
                ld l, a
                ld h, T_ARG >> 8
                xor a
                ld (hl), a
                inc l
                ld (hl), a
                ret

rw_short:
                push af
                ld hl, (T_ARG)
                ld de, (io_got)
                add hl, de
                push hl
                ld a, (CUR)
                add a, a
                add a, T_ARG & 0FFh
                ld l, a
                ld h, T_ARG >> 8
                ld e, (hl)
                inc l
                ld d, (hl)
                ld ix, (SC_FRAME)
                ld l, (ix + F_IX)
                ld h, (ix + F_IX + 1)
                add hl, de
                ld (ix + F_IX), l
                ld (ix + F_IX + 1), h
                xor a
                ld (hl), a
                dec l
                ld (hl), a
                pop hl
                pop af
                ld a, h
                or l
                jr z, rw_fail
                xor a
                jp syscall_ok
rw_fail:
                scf
                jp syscall_err

                include "ser.asm"
                assert $ <= SER_REC
                org SER_REC
                ds SER_SIZE, 0
                assert $ <= DEV_BASE + DEV_PAGES * 256
