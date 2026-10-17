; Serial driver — sole writer of SER and ports E8h–EBh (and E0h after boot).

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
S_SPLICE            equ 31
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

ser_defaults:   db 0Eh, 8, 0, 1, CFG_F_RTSCTS, 0

                MACRO D2C rate_x2
                dw (2 * 24 * CPU_HZ) / (26 * rate_x2) + 1
                ENDM
delay2_table:
                D2C 100
                D2C 150
                D2C 220
                D2C 269
                D2C 300
                D2C 600
                D2C 1200
                D2C 2400
                D2C 3600
                D2C 4800
                D2C 7200
                D2C 9600
                D2C 14400
                D2C 19200
                D2C 38400

ser_open:
                ld a, (open_flags)
                and O_CREATE | O_TRUNC | O_APPEND | O_EXCL
                jp nz, dev_err_einval
                ld a, (SER + S_PHASE)
                cp PH_OPEN
                jp z, dev_err_ebusy
                di
                ld a, (SER + S_PHASE)
                or a
                jr nz, so_gap
                ld a, (SER + S_GAP)
                or a
                jr z, so_probe
so_gap:
                ei
                ld a, CH_TICK
                jp block_retry
so_probe:
                ei
                xor a
                out (PORT_SER_RESET), a
                in a, (PORT_SER_STATUS)
                and SER_ST_DR | SER_ST_THRE
                cp SER_ST_THRE
                jp nz, dev_err_enodev
                call ring_take
                jp c, dev_err_enomem
                ld (SER + S_RXPG), a
                call ring_take
                jp c, so_give_rx
                ld (SER + S_TXPG), a
                ld a, KIND_SER
                ld (open_kind), a
                xor a
                ld (open_ino), a
                ld (open_ino + 1), a
                call fd_alloc
                jp c, so_free_rings
                di
                xor a
                ld (SER + S_RXH), a
                ld (SER + S_RXT), a
                ld (SER + S_TXH), a
                ld (SER + S_TXT), a
                ld (SER + S_HI_SET), a
                ld (SER + S_HI_CLR), a
                ld (SER + S_ERR_SET), a
                ld (SER + S_ERR_SEEN), a
                ld (SER + S_BRK), a
                ld hl, ser_defaults
                ld de, SER + S_CFG
                ld bc, CFG_SIZE
                ldir
                ld hl, SER + S_STATS
                ld bc, STATS_SIZE
                xor a
                ld (hl), a
                inc hl
                dec bc
                jr so_stat_z
so_stat_z:
                ld (hl), a
                inc hl
                dec bc
                ld a, b
                or c
                jr nz, so_stat_z
                in a, (PORT_SER_MODEM)
                bit SER_MS_DCD_BIT, a
                ld a, LN_DTR
                jr z, so_dcd
                or LN_DCD
so_dcd:
                ld (SER + S_LINE), a
                ld a, PH_OPEN
                ld (SER + S_PHASE), a
                call cfg_apply
                ei
                jp dev_ok
so_give_rx:
                ld a, (SER + S_RXPG)
                call ring_give
dev_err_enomem:
                ld a, ENOMEM
                jp dev_err
dev_err_enodev:
                ld a, ENODEV
                jp dev_err
dev_err_ebusy:
                ld a, EBUSY
                jp dev_err
so_free_rings:
                push af
                ld a, (SER + S_RXPG)
                call ring_give
                ld a, (SER + S_TXPG)
                call ring_give
                pop af
                jp dev_err

ser_read:
                call io_empty
                ld hl, 0
                ld (io_got), hl
sr_loop:
                ei
                ld a, (SER + S_RXH)
                ld c, a
                ld a, (SER + S_RXT)
                sub c
                jr z, sr_wait
                ld b, a
                ld hl, (io_len)
                or a
                sbc hl, bc
                jr nc, sr_n
                ld b, l
sr_n:
                ld a, (SER + S_RXPG)
                ld h, a
                ld l, c
                ld de, (io_buf)
                push bc
sr_copy:
                ld a, (hl)
                inc hl
                ld (de), a
                inc de
                djnz sr_copy
                pop bc
                ld a, (SER + S_RXH)
                add a, b
                ld (SER + S_RXH), a
                ld hl, (io_buf)
                add hl, bc
                ld (io_buf), hl
                ld hl, (io_got)
                add hl, bc
                ld (io_got), hl
                ld hl, (io_len)
                or a
                sbc hl, bc
                ld (io_len), hl
                ld a, (SER + S_HI_SET)
                ld c, a
                ld a, (SER + S_HI_CLR)
                cp c
                jr nz, sr_hi
                ld a, (SER + S_RXH)
                sub (SER + S_RXT)
                cp SER_RX_LOW + 1
                jr nc, sr_wait
                ld hl, SER + S_HI_CLR
                ld (hl), c
                di
                call ctl_out
sr_hi:
                di
                ld hl, (io_len)
                ld a, h
                or l
                jr z, sr_done
                ld a, (SER + S_RXH)
                sub (SER + S_RXT)
                jr nz, sr_loop
sr_wait:
                call hung
                jr nz, sr_hung
                ld a, CH_SER
                jp io_round
sr_hung:
                xor a
                jp rw_short
sr_done:
                ld a, CH_SER
                jp io_round

ser_write:
                call io_empty
                call hung
                jp nz, sw_hung
sw_loop:
                di
                ld a, (SER + S_TXH)
                ld c, a
                ld a, (SER + S_TXT)
                sub c
                ld a, 255
                sub a
                ld b, a
                or a
                jr z, sw_full
                ei
                ld hl, (io_len)
                or a
                sbc hl, bc
                jr nc, sw_m
                ld b, l
sw_m:
                ld a, (SER + S_TXPG)
                ld h, a
                ld l, c
                ld de, (io_buf)
sw_copy:
                ld a, (de)
                inc de
                ld (hl), a
                inc hl
                djnz sw_copy
                ld a, (SER + S_TXH)
                add a, b
                ld (SER + S_TXH), a
                ld hl, (io_buf)
                add hl, bc
                ld (io_buf), hl
                ld hl, (io_got)
                add hl, bc
                ld (io_got), hl
                ld hl, (io_len)
                or a
                sbc hl, bc
                ld (io_len), hl
                di
                call mask_out
                ld hl, (io_len)
                ld a, h
                or l
                jr nz, sw_loop
                ld a, CH_SER
                jp io_round
sw_full:
                ei
                ld a, CH_SER
                jp block_retry
sw_hung:
                ld a, EIO
                jp rw_short

ser_ioctl:
                ld a, b
                cp SER_CLASS
                jp nz, dev_err_einval
                ld a, c
                cp 1
                jp z, si_getcfg
                cp 2
                jp z, si_setcfg
                cp 3
                jp z, si_lines
                cp 4
                jp z, si_dtr
                cp 5
                jp z, si_break
                cp 6
                jp z, si_stats
                jp dev_err_einval
si_getcfg:
                ld hl, SER + S_CFG
                ld de, ix
                ld bc, CFG_SIZE
                ldir
                xor a
                ld hl, 0
                jp dev_ok
si_setcfg:
                call cfg_check
                jp c, dev_err_einval
                di
                ld a, (SER + S_TXH)
                cp (SER + S_TXT)
                jr z, si_set_go
                ei
                ld a, CH_SER
                jp block_retry
si_set_go:
                ld hl, ix
                ld de, SER + S_CFG
                ld bc, CFG_SIZE
                ldir
                call cfg_apply
                ei
                xor a
                ld hl, 0
                jp dev_ok
si_lines:
                call lines_now
                jp dev_ok
si_dtr:
                ld a, (ix + 0)
                or a
                jr z, si_dtr0
                ld a, (ix + 1)
                dec a
                jp nz, dev_err_einval
                di
                ld a, (SER + S_GAP)
                or a
                jr nz, si_dtr_wait
                ld a, (SER + S_LINE)
                or LN_DTR
                ld (SER + S_LINE), a
                call ctl_out
                ei
                xor a
                ld hl, 0
                jp dev_ok
si_dtr_wait:
                ei
                ld a, CH_TICK
                jp block_retry
si_dtr0:
                di
                ld a, (SER + S_LINE)
                bit 0, a
                jr z, si_dtr_done
                res 0, a
                ld (SER + S_LINE), a
                ld a, DTR_GAP_TICKS
                ld (SER + S_GAP), a
                call ctl_out
si_dtr_done:
                ei
                xor a
                ld hl, 0
                jp dev_ok
si_break:
                ld a, (ix + 0)
                dec a
                cp BREAK_MAX
                jp nc, dev_err_einval
                ld b, a
                inc b
                ld a, (CUR)
                add a, a
                add a, T_ARG & 0FFh
                ld l, a
                ld h, T_ARG >> 8
                ld a, (hl)
                or a
                jr nz, si_brk_wait
                di
                ld hl, SER + S_BRK
                ld (hl), b
                call ctl_out
                call mask_out
                ld a, 1
                ld (hl), a
                ei
                ld a, CH_TICK
                jp block_retry
si_brk_wait:
                di
                ld a, (SER + S_BRK)
                or a
                jr nz, si_brk_wait2
                ei
                xor a
                ld hl, 0
                jp dev_ok
si_brk_wait2:
                ei
                ld a, CH_TICK
                jp block_retry
si_stats:
                di
                ld hl, SER + S_STATS
                ld de, ix
                ld bc, STATS_SIZE
                ldir
                ld hl, SER + S_STATS
                xor a
                ld bc, STATS_SIZE
                ld (hl), a
                inc hl
                dec bc
                jr si_stz
si_stz:
                ld (hl), a
                inc hl
                dec bc
                ld a, b
                or c
                jr nz, si_stz
                ei
                xor a
                ld hl, 0
                jp dev_ok

ser_close:
                ld a, (SER + S_PHASE)
                cp PH_OPEN
                ret nz
                ld a, i
                push af
                di
                ld a, PH_LINGER
                ld (SER + S_PHASE), a
                ld a, LINGER_TICKS
                ld (SER + S_LINGER), a
                xor a
                ld (SER + S_BRK), a
                call ctl_out
                call mask_out
                pop af
                ret po
                ei
                ret
ser_close_po:
                ret

ser_revents:
                xor a
                ld c, a
                ld a, (SER + S_RXH)
                sub (SER + S_RXT)
                jr z, sr_ev1
                ld c, POLLIN
sr_ev1:
                call hung
                jr z, sr_ev2
                ld a, c
                or POLLIN | POLLHUP
                ld c, a
sr_ev2:
                call hung
                jr nz, sr_ev3
                ld a, (SER + S_TXH)
                sub (SER + S_TXT)
                cp 255
                jr z, sr_ev3
                ld a, c
                or POLLOUT
                ld c, a
sr_ev3:
                ld a, (SER + S_ERR_SET)
                ld b, a
                ld a, (SER + S_ERR_SEEN)
                cp b
                jr z, sr_ev4
                ld hl, SER + S_ERR_SEEN
                ld (hl), b
                ld a, c
                or POLLERR
                ld c, a
sr_ev4:
                ld a, c
                ret

ser_irq:
                bit IRQ_SER_RX_BIT, a
                jr nz, si_done
                call ser_rx
si_done:
                bit IRQ_SER_TX_BIT, a
                ret nz
                jp ser_tx

ser_rx:
                in a, (PORT_SER_STATUS)
                ld b, a
                in a, (PORT_SER_DATA)
                ld c, a
                bit SER_ST_DR_BIT, b
                ret z
                bit SER_ST_OE_BIT, b
                call nz, stat_inc0
                bit SER_ST_FE_BIT, b
                call nz, stat_inc1
                bit SER_ST_PE_BIT, b
                call nz, stat_inc2
                bit SER_ST_OE_BIT, b
                jr z, srx_ok
                bit SER_ST_FE_BIT, b
                jr z, srx_ok
                bit SER_ST_PE_BIT, b
                jr z, srx_ok
                call err_bump
srx_ok:
                ld a, (SER + S_RXH)
                sub (SER + S_RXT)
                cp 255
                jr z, srx_drop
                push bc
                ld a, (SER + S_RXH)
                sub (SER + S_RXT)
                ld b, a
                ld a, (SER + S_RXPG)
                ld h, a
                ld l, (SER + S_RXH)
                pop af
                ld (hl), a
                ld hl, SER + S_RXH
                inc (hl)
                ld a, b
                or a
                jr nz, srx_wake
                ld a, CH_SER
                call wake
srx_wake:
                ld a, (SER + S_CFG + CFG_FLAGS)
                and CFG_F_RTSCTS
                jr z, srx_ret
                ld a, (SER + S_RXH)
                sub (SER + S_RXT)
                cp SER_RX_HIGH
                jr c, srx_ret
                ld a, (SER + S_HI_SET)
                ld b, a
                ld a, (SER + S_HI_CLR)
                cp b
                jr nz, srx_ret
                inc a
                ld (SER + S_HI_SET), a
                call ctl_out
srx_ret:
                ret
srx_drop:
                call err_bump
                call stat_inc3
                ret

ser_tx:
                ld a, (SER + S_TXH)
                cp (SER + S_TXT)
                jr z, st_empty
                ld a, (SER + S_BRK)
                or a
                jr nz, st_empty
                ld a, (SER + S_CFG + CFG_FLAGS)
                and CFG_F_RTSCTS
                jr z, st_send
                in a, (PORT_SER_MODEM)
                bit SER_MS_CTS_BIT, a
                jr z, st_empty
st_send:
                ld a, (SER + S_TXPG)
                ld h, a
                ld l, (SER + S_TXT)
                ld a, (hl)
                out (PORT_SER_DATA), a
                ld hl, SER + S_TXT
                inc (hl)
                ld a, (SER + S_TXH)
                sub (SER + S_TXT)
                cp SER_TX_WAKE
                jr nz, st_w0
                ld a, CH_SER
                call wake
                jr st_mask
st_w0:
                or a
                jr nz, st_mask
                ld a, CH_SER
                call wake
st_mask:
                call mask_out
                ret
st_empty:
                call mask_out
                ret

ser_tick:
                ld a, (SER + S_GAP)
                or a
                jr z, st_ph
                dec a
                ld (SER + S_GAP), a
st_ph:
                ld a, (SER + S_PHASE)
                or a
                ret z
                ld a, (SER + S_BRK)
                or a
                jr z, st_brk
                dec a
                ld (SER + S_BRK), a
                jr nz, st_brk
                call ctl_out
                call mask_out
st_brk:
                ld a, (SER + S_PHASE)
                cp PH_LINGER
                jr nz, st_open
                ld a, (SER + S_LINGER)
                dec a
                ld (SER + S_LINGER), a
                jr z, st_drop
                ld a, (SER + S_TXH)
                cp (SER + S_TXT)
                jr nz, st_lmask
                ld a, 1
                ld (SER + S_LINGER), a
st_lmask:
                call mask_out
                ret
st_drop:
                jp ser_drop
st_open:
                in a, (PORT_SER_MODEM)
                bit SER_MS_DCD_BIT, a
                ld b, a
                ld a, (SER + S_LINE)
                bit 3, a
                ld c, a
                ld a, b
                jr z, st_dcd1
                bit 0, c
                jr nz, st_cts
                ld a, (SER + S_LINE)
                or LN_DCD
                ld (SER + S_LINE), a
                jr st_cts
st_dcd1:
                bit 0, c
                jr z, st_cts
                ld a, (SER + S_LINE)
                res 3, a
                ld (SER + S_LINE), a
                ld a, (SER + S_CFG + CFG_FLAGS)
                and CFG_F_DCD
                jr z, st_cts
                ld a, (SER + S_LINE)
                or LN_HUNG
                ld (SER + S_LINE), a
                ld a, CH_SER
                call wake
st_cts:
                ld a, (SER + S_TXH)
                cp (SER + S_TXT)
                ret z
                call mask_out
                ret

ser_drop:
                di
                ld a, PH_CLOSED
                ld (SER + S_PHASE), a
                ld a, (SER + S_LINE)
                and ~LN_DTR
                ld (SER + S_LINE), a
                call mask_out
                call ctl_out
                ld a, DTR_GAP_TICKS
                ld (SER + S_GAP), a
                ld a, (SER + S_RXPG)
                call ring_give
                ld a, (SER + S_TXPG)
                call ring_give
                xor a
                ld (SER + S_RXPG), a
                ld (SER + S_TXPG), a
                ret

mask_out:
                ld a, IRQ_TIMER
                ld b, a
                ld a, (SER + S_PHASE)
                cp PH_OPEN
                jr nz, mo_tx
                ld a, b
                or IRQ_SER_RX
                ld b, a
mo_tx:
                ld a, (SER + S_PHASE)
                cp PH_CLOSED
                jr z, mo_out
                ld a, (SER + S_TXH)
                cp (SER + S_TXT)
                jr z, mo_out
                ld a, (SER + S_BRK)
                or a
                jr nz, mo_out
                ld a, (SER + S_CFG + CFG_FLAGS)
                and CFG_F_RTSCTS
                jr z, mo_en_tx
                in a, (PORT_SER_MODEM)
                bit SER_MS_CTS_BIT, a
                jr z, mo_out
mo_en_tx:
                ld a, b
                or IRQ_SER_TX
                ld b, a
mo_out:
                ld a, b
                out (PORT_IRQ), a
                ret

ctl_out:
                call cfg_bits
                ld b, a
                ld a, (SER + S_LINE)
                bit 0, a
                jr z, co_dtr
                ld a, b
                or SER_CT_DTR
                ld b, a
co_dtr:
                ld a, (SER + S_PHASE)
                cp PH_OPEN
                jr nz, co_brk
                ld a, (SER + S_LINE)
                bit 1, a
                jr nz, co_brk
                ld a, (SER + S_CFG + CFG_FLAGS)
                and CFG_F_RTSCTS
                jr z, co_rts
                ld a, (SER + S_HI_SET)
                ld c, a
                ld a, (SER + S_HI_CLR)
                cp c
                jr nz, co_brk
co_rts:
                ld a, b
                or SER_CT_RTS
                ld b, a
co_brk:
                ld a, (SER + S_BRK)
                or a
                jr z, co_out
                ld a, b
                or SER_CT_BREAK
                ld b, a
co_out:
                ld a, b
                out (PORT_SER_CTL), a
                ret

cfg_apply:
                ld a, (SER + S_CFG + CFG_BAUD)
                ld c, a
                ld b, a
                add a, a
                add a, a
                add a, a
                add a, a
                or b
                out (PORT_SER_BAUD), a
                ld l, c
                ld h, 0
                add hl, hl
                ld de, delay2_table
                add hl, de
                ld e, (hl)
                inc hl
                ld d, (hl)
                ld (SER + S_DELAY), de
                call ctl_out
                call mask_out
                ret

cfg_check:
                ld a, (ix + CFG_BAUD)
                cp 10h
                ret nc
                ld a, (ix + CFG_DATA)
                cp 5
                ret c
                cp 9
                ret nc
                ld a, (ix + CFG_PARITY)
                cp 3
                ret nc
                ld a, (ix + CFG_STOP)
                dec a
                cp 2
                ret nc
                ld a, (ix + CFG_FLAGS)
                and ~(CFG_F_RTSCTS | CFG_F_DCD)
                ret nz
                ld a, (ix + CFG_RESERVED)
                ret

cfg_bits:
                ld a, (SER + S_CFG + CFG_DATA)
                sub 5
                ld c, a
                ld a, (SER + S_CFG + CFG_STOP)
                dec a
                rlca
                or c
                ld c, a
                ld a, (SER + S_CFG + CFG_PARITY)
                or a
                jr z, cb_p0
                dec a
                jr z, cb_p1
                ld a, c
                or SER_CT_EVEN
                ld c, a
cb_p1:
                ld a, c
                or SER_CT_NOPARITY
                ld c, a
cb_p0:
                ld a, c
                ret

lines_now:
                in a, (PORT_SER_MODEM)
                ld c, a
                xor a
                bit SER_MS_CTS_BIT, c
                jr z, ln0
                or 1
ln0:
                bit SER_MS_DSR_BIT, c
                jr z, ln1
                or 2
ln1:
                bit SER_MS_DCD_BIT, c
                jr z, ln2
                or 4
ln2:
                bit SER_MS_RI_BIT, c
                jr z, ln3
                or 8
ln3:
                ld h, 0
                ld l, a
                ret

hung:
                ld a, (SER + S_LINE)
                bit LN_HUNG, a
                ret z
                ld a, (SER + S_CFG + CFG_FLAGS)
                and CFG_F_DCD
                ret

ring_take:
                call largest_run
                ret c
                ld a, (RUN_END)
                dec a
                call owner_of
                ld (hl), 0FFh
                ret

ring_give:
                call owner_of
                ld (hl), 0
                ret

ser_disk:
                push af
                ld a, (KBUSY)
                dec a
                jr nz, sd_ret
                ld a, (SER + S_PHASE)
                cp PH_OPEN
                jr nz, sd_ret
                ld a, (SER + S_CFG + CFG_FLAGS)
                and CFG_F_RTSCTS
                jr z, sd_ret
                ld a, i
                jp po, sd_ret
                di
                ld a, (SER + S_LINE)
                or LN_DISK
                ld (SER + S_LINE), a
                call ctl_out
                ei
                call delay2
                pop af
                pop hl
                ex (sp), hl
                ld de, ser_disk_post
                push de
                ret
sd_ret:
                pop af
                ret

ser_disk_post:
                push af
                di
                ld a, (SER + S_LINE)
                and ~LN_DISK
                ld (SER + S_LINE), a
                call ctl_out
                ei
                pop af
                ret

delay2:
                ld hl, (SER + S_DELAY)
                ld bc, hl
d2_loop:
                dec bc
                ld a, b
                or c
                jr nz, d2_loop
                ret

stat_inc0:
                ld hl, SER + S_STATS
                call inc16
                ret
stat_inc1:
                ld hl, SER + S_STATS + 2
                call inc16
                ret
stat_inc2:
                ld hl, SER + S_STATS + 4
                call inc16
                ret
stat_inc3:
                ld hl, SER + S_STATS + 6
                call inc16
                ret
err_bump:
                ld hl, SER + S_ERR_SET
                inc (hl)
                ret
inc16:
                inc (hl)
                ret nz
                inc hl
                inc (hl)
                ret
