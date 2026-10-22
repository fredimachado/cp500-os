; W5100 socket driver for /sys/dev.

Sn_MR           equ 0
Sn_CR           equ 1
Sn_IR           equ 2
Sn_SR           equ 3
Sn_PORT         equ 4
Sn_DIPR         equ 0Ch
Sn_DPORT        equ 10h
Sn_TX_FSR       equ 20h
Sn_TX_WR        equ 24h
Sn_RX_RSR       equ 26h
Sn_RX_RD        equ 28h

W5_OPEN         equ 01h
W5_LISTEN       equ 02h
W5_CONNECT      equ 04h
W5_CLOSE        equ 10h
W5_SEND         equ 20h
W5_RECV         equ 40h
W5_TCP          equ 01h
W5_UDP          equ 02h

SR_CLOSED       equ 00h
SR_INIT         equ 13h
SR_LISTEN       equ 14h
SR_EST          equ 17h
SR_CLOSE_WAIT   equ 1Ch

W5_SOCK0        equ 0400h
W5_STRIDE       equ 0100h
W5_TX0          equ 4000h
W5_RX0          equ 6000h
W5_STEP         equ 0800h
W5_MASK         equ 07FFh

net_vec:
                dw n_socket, n_connect, n_listen, n_accept
                dw n_send, n_recv, n_sockclose, n_resolve
net_ok:         db 0
net_s:          db 0
net_lport:      dw 4000h
net_shift:      db 0

net_call:
                ld ix, (SC_FRAME)
                ld a, (ix + F_C)
                sub SYS_SOCKET
                jp nc, net_go
                ld a, EINVAL
                jp dev_err
net_go:
                cp 8
                jp nc, dev_err_einval
                add a, a
                ld hl, net_vec
                add a, l
                ld l, a
                adc a, h
                sub l
                ld h, a
                ld e, (hl)
                inc hl
                ld d, (hl)
                ex de, hl
                jp (hl)

net_sock_close:
                inc hl
                inc hl
                ld a, (hl)
                ld (net_s), a
                call net_up
                ld a, W5_CLOSE
                call w5_cmd
                ret

net_up:
                call w5_up
                jp c, dev_err

; Carry ENODEV.
w5_up:
                ld a, (net_ok)
                or a
                ret nz
                in a, (PORT_W5_MR)
                inc a
                jr nz, w5_bad
                ld a, W5_MR_IND
                out (PORT_W5_MR), a
                in a, (PORT_W5_MR)
                cp W5_MR_IND
                jr nz, w5_bad
                call w5_cfg_write
                ld a, 1
                ld (net_ok), a
                xor a
                ret
w5_bad:
                ld a, ENODEV
                scf
                ret

w5_cfg_write:
                ld hl, w5_cfg
                ld bc, w5_cfg_end - w5_cfg
w5cw:
                ld e, (hl)
                inc hl
                ld d, (hl)
                inc hl
                ld a, (hl)
                inc hl
                push hl
                push bc
                call w5_wa
                pop bc
                pop hl
                dec bc
                ld a, b
                or c
                jr nz, w5cw
                ret

w5_cfg:
                db 01h, 00h, 0Ah, 02h, 00h, 00h, 03h, 00h, 02h, 04h, 00h, 02h
                db 05h, 00h, 0FFh, 06h, 00h, 0FFh, 07h, 00h, 0FFh, 08h, 00h, 00h
                db 09h, 00h, 02h, 0Ah, 00h, 43h, 0Bh, 00h, 50h, 0Ch, 00h, 35h
                db 0Dh, 00h, 30h, 0Eh, 00h, 30h, 0Fh, 00h, 0Ah, 10h, 00h, 00h
                db 11h, 00h, 02h, 12h, 00h, 0Fh, 1Ah, 00h, 55h, 1Bh, 00h, 55h
w5_cfg_end:

; HL addr, A data.
w5_wa:
                push af
                ld a, h
                out (PORT_W5_AR0), a
                ld a, l
                out (PORT_W5_AR1), a
                pop af
                out (PORT_W5_DR), a
                ret

; HL addr -> A.
w5_ra:
                ld a, h
                out (PORT_W5_AR0), a
                ld a, l
                out (PORT_W5_AR1), a
                in a, (PORT_W5_DR)
                ret

; A socket, E reg -> HL addr. 0400h + n<<8 + reg.
w5_sa:
                add a, W5_SOCK0 >> 8
                ld h, a
                ld l, e
                ret

; A socket in (net_s), E reg.
w5_sx:
                ld a, (net_s)
                jp w5_sa

w5_cmd:
                push af
                ld e, Sn_CR
                call w5_sx
                pop af
                call w5_wa
w5_cmd_w:
                ld e, Sn_CR
                call w5_sx
                call w5_ra
                or a
                jr nz, w5_cmd_w
                ret

w5_r16:
                ld a, h
                out (PORT_W5_AR0), a
                ld a, l
                out (PORT_W5_AR1), a
                in a, (PORT_W5_DR)
                ld b, a
                in a, (PORT_W5_DR)
                ld h, b
                ld l, a
                ret

w5_r16s:
                call w5_r16
                push hl
                call w5_r16
                pop de
                or a
                sbc hl, de
                ret nz
                ex de, hl
                ret

; E fd -> socket in A, carry EBADF.
net_sockfd:
                call fd_get
                ret c
                cp KIND_NET
                jr nz, nsf_bad
                inc hl
                inc hl
                ld a, (hl)
                ld (net_s), a
                xor a
                ret
nsf_bad:
                ld a, EBADF
                scf
                ret

n_socket:
                ld a, (ix + F_B)
                dec a
                jp nz, dev_err_einval
                call net_up
                call net_pick_sock
                jp c, dev_err
                ld a, (net_s)
                ld e, Sn_MR
                call w5_sa
                ld a, W5_TCP
                call w5_wa
                ld hl, (net_lport)
                inc hl
                ld (net_lport), hl
                ld e, Sn_PORT
                call w5_sx
                ld a, h
                call w5_wa
                ld a, l
                call w5_wa
                ld a, W5_OPEN
                call w5_cmd
                ld a, KIND_NET
                ld (open_kind), a
                ld a, (net_s)
                ld (open_ino), a
                xor a
                ld (open_ino + 1), a
                ld (open_flags), a
                call fd_alloc
                jp c, dev_err
                jp dev_ok

; Marks chip sockets 0-2 that are already open in OF_INO. Returns one in net_s.
; H holds the in-use bitmap; ofile_of clears H, so the bitmap is saved across the call.
net_pick_sock:
                ld hl, 0
                ld b, OFILE_SLOTS
nps_mark:
                ld a, l
                push hl
                call ofile_of
                ld a, (hl)
                cp KIND_NET
                jr nz, nps_mark_miss
                inc hl
                inc hl
                ld a, (hl)
                pop hl
                cp 3
                jr nc, nps_mark_next
                or a
                jr z, nps_mark_b0
                dec a
                jr z, nps_mark_b1
                set 2, h
                jr nps_mark_next
nps_mark_b0:
                set 0, h
                jr nps_mark_next
nps_mark_b1:
                set 1, h
                jr nps_mark_next
nps_mark_miss:
                pop hl
nps_mark_next:
                inc l
                djnz nps_mark
                ld a, h
                cp 7
                jp z, nps_full
                bit 0, h
                jr z, nps_got0
                bit 1, h
                jr z, nps_got1
                ld a, 2
                jr nps_got
nps_got0:
                xor a
                jr nps_got
nps_got1:
                ld a, 1
nps_got:
                ld (net_s), a
                xor a
                ret
nps_full:
                ld a, EMFILE
                scf
                ret

n_connect:
                call net_up
                jp c, dev_err
                ld ix, (SC_FRAME)
                ld a, (ix + F_DE)
                ld e, a
                call net_sockfd
                jp c, dev_err
                ld hl, (ix + F_HL)
                push hl
                ld e, Sn_DIPR
                call w5_sx
                pop de
                ld b, 4
nc_ip:
                ld a, (de)
                inc de
                call w5_wa
                inc hl
                djnz nc_ip
                ld a, (de)
                ld b, a
                inc de
                ld a, (de)
                ld c, a
                push bc
                ld e, Sn_DPORT
                call w5_sx
                pop bc
                ld a, b
                call w5_wa
                ld a, c
                call w5_wa
                ld a, W5_CONNECT
                call w5_cmd
nc_wait:
                ld e, Sn_RX_RSR
                call w5_sx
                call w5_r16
                ld e, Sn_SR
                call w5_sx
                call w5_ra
                cp SR_EST
                jp z, dev_ok_z
                cp SR_CLOSED
                jp z, nc_die
                cp SR_INIT
                jr nc, nc_tick
                ld a, W5_OPEN
                call w5_cmd
nc_tick:
                ld a, CH_TICK
                jp block_retry
nc_die:
                ld a, W5_CLOSE
                call w5_cmd
                ld a, EIO
                jp dev_err

n_listen:
                call net_up
                ld a, (ix + F_DE)
                ld e, a
                call net_sockfd
                jp c, dev_err
                ld hl, (ix + F_HL)
                ld a, h
                or l
                jp z, dev_err_einval
                ld e, Sn_MR
                call w5_sx
                ld a, W5_TCP
                call w5_wa
                ld e, Sn_PORT
                call w5_sx
                ld a, h
                call w5_wa
                ld a, l
                call w5_wa
                ld a, W5_OPEN
                call w5_cmd
                ld a, W5_LISTEN
                call w5_cmd
                jp dev_ok_z

n_accept:
                call net_up
                ld a, (ix + F_DE)
                ld e, a
                call net_sockfd
                jp c, dev_err
na_wait:
                ld e, Sn_SR
                call w5_sx
                call w5_ra
                cp SR_EST
                jp z, na_ok
                cp SR_CLOSE_WAIT
                jp z, na_ok
                cp SR_LISTEN
                jr z, na_tick
                ld a, EIO
                jp dev_err
na_tick:
                ld a, CH_TICK
                jp block_retry
na_ok:
                ld a, (ix + F_DE)
                ld l, a
                ld h, 0
                jp dev_ok

n_send:
                call net_up
                ld a, (ix + F_DE)
                ld e, a
                call net_sockfd
                jp c, dev_err
                ld hl, (ix + F_HL)
                ld (io_buf), hl
                ld hl, (ix + F_IX)
                ld (io_len), hl
                xor a
                ld (io_got), a
                ld (io_got + 1), a
ns_loop:
                ld e, Sn_SR
                call w5_sx
                call w5_ra
                cp SR_EST
                jp nz, ns_eio
                ld e, Sn_TX_FSR
                call w5_sx
                call w5_r16s
                ld a, h
                or l
                jr z, ns_tick
                ld de, (io_len)
                ld bc, hl
                or a
                sbc hl, de
                ld hl, bc
                jr c, ns_take
                ld hl, de
ns_take:
                push hl
                ld e, Sn_TX_WR
                call w5_sx
                call w5_r16
                pop bc
                push hl
                push bc
                ld a, (net_s)
                add a, a
                add a, a
                add a, a
                add a, h
                add a, W5_TX0 >> 8
                ld h, a
                ld de, (io_buf)
                call w5_buf_tx
                pop bc
                pop hl
                add hl, bc
                ld a, h
                and W5_MASK >> 8
                ld h, a
                push bc
                push hl
                ld e, Sn_TX_WR
                call w5_sx
                pop bc
                ld a, b
                call w5_wa
                ld a, c
                call w5_wa
                pop bc
                ld hl, (io_got)
                add hl, bc
                ld (io_got), hl
                push bc
                ld a, W5_SEND
                call w5_cmd
                pop bc
                ld hl, (io_len)
                or a
                sbc hl, bc
                ld (io_len), hl
                ld a, h
                or l
                jr nz, ns_tick
                ld hl, (io_got)
                jp dev_ok
ns_tick:
                ld a, CH_TICK
                jp block_retry
ns_eio:
                ld a, EIO
                jp dev_err

; HL chip ptr, DE host buf, BC len.
; Chip address is not wrapped here; callers send at most one TX bank from TX_WR 0.
w5_buf_tx:
                push bc
w5btx:
                ld a, b
                or c
                jr z, w5btx_done
                ld a, (de)
                call w5_wa
                inc de
                inc hl
                dec bc
                jr w5btx
w5btx_done:
                pop bc
                ret

n_recv:
                call net_up
                jp c, dev_err
                ld ix, (SC_FRAME)
                ld a, (ix + F_DE)
                ld e, a
                call net_sockfd
                jp c, dev_err
                ld hl, (ix + F_HL)
                ld (io_buf), hl
                ld hl, (ix + F_IX)
                ld (io_len), hl
nr_loop:
                ld e, Sn_RX_RSR
                call w5_sx
                call w5_r16
                ld a, h
                or l
                jr nz, nr_copy
                ld e, Sn_SR
                call w5_sx
                call w5_ra
                cp SR_EST
                jr nz, nr_eof
                ld a, (ix + F_B)
                and SOCK_NONBLOCK
                jp nz, nr_eagain
                ld a, CH_TICK
                jp block_retry
nr_eof:
                jp dev_ok_z
nr_eagain:
                ld a, EAGAIN
                jp dev_err
nr_copy:
                ld de, (io_len)
                ld bc, hl
                or a
                sbc hl, de
                ld hl, bc
                jr c, nr_take
                ld hl, de
nr_take:
                ld b, h
                ld c, l
                push bc
                ld e, Sn_RX_RD
                call w5_sx
                ld a, h
                sub W5_SOCK0 >> 8
                push af
                call w5_r16
                ld a, h
                and W5_MASK >> 8
                ld h, a
                pop af
                push af
                add a, a
                add a, a
                add a, a
                add a, h
                add a, W5_RX0 >> 8
                ld h, a
                pop af
                pop bc
                push af
                ld de, (io_buf)
                call w5_buf_rx
                pop af
                push bc
                add a, W5_SOCK0 >> 8
                ld h, a
                ld l, Sn_RX_RSR
                pop bc
                push bc
                ld a, b
                call w5_wa
                ld a, c
                call w5_wa
                ld l, Sn_CR
                pop bc
                push bc
                ld a, W5_RECV
                call w5_wa
                pop hl
                jp dev_ok

; HL absolute chip address, DE host, BC len. BC is preserved.
w5_buf_rx:
                push bc
w5brx:
                ld a, b
                or c
                jr z, w5brx_done
                push bc
                call w5_ra
                ld (de), a
                inc de
                inc hl
                ld a, l
                and W5_MASK & 0FFh
                ld l, a
                pop bc
                dec bc
                jr w5brx
w5brx_done:
                pop bc
                ret

net_revents:
                inc hl
                inc hl
                ld a, (hl)
                ld (net_s), a
                ld e, Sn_RX_RSR
                call w5_sx
                call w5_r16
                ld a, h
                or l
                jr z, nrv_sr
                ld a, POLLIN
                ret
nrv_sr:
                ld e, Sn_SR
                call w5_sx
                call w5_ra
                cp SR_EST
                jr z, nrv_none
                ld a, POLLIN | POLLHUP
                ret
nrv_none:
                xor a
                ret

n_sockclose:
                call net_up
                ld a, (ix + F_DE)
                ld e, a
                ld d, 0
                cp FD_SLOTS
                ld a, EBADF
                jp nc, dev_err
                ld hl, TASK + TASK_FD
                add hl, de
                call fd_drop
                jp dev_ok_z

n_resolve:
                ld hl, (ix + F_DE)
                ex de, hl
                call dns_dot
                jr c, nr_done
                call net_up
                ld a, 3
                ld (net_s), a
                ld e, Sn_MR
                call w5_sx
                ld a, W5_UDP
                call w5_wa
                ld hl, (net_lport)
                inc hl
                ld (net_lport), hl
                ld e, Sn_PORT
                call w5_sx
                ld a, h
                call w5_wa
                ld a, l
                call w5_wa
                ld a, W5_OPEN
                call w5_cmd
                ld hl, w5_gw
                push hl
                ld e, Sn_DIPR
                call w5_sx
                pop de
                ld b, 4
nr_gw:
                ld a, (de)
                inc de
                call w5_wa
                inc hl
                djnz nr_gw
                xor a
                ld e, Sn_DPORT
                call w5_sx
                xor a
                call w5_wa
                ld a, 53
                call w5_wa
                call dns_query
                ld a, W5_SEND
                call w5_cmd
nr_poll:
                ld e, Sn_RX_RSR
                call w5_sx
                call w5_r16s
                ld a, h
                or l
                jr z, nr_wait
                call dns_answer
                ld a, W5_CLOSE
                call w5_cmd
                jp c, dev_err
                jp dev_ok_z
nr_wait:
                ld a, CH_TICK
                jp block_retry
nr_done:
                ld hl, (ix + F_HL)
                ex de, hl
                ld bc, 4
                ldir
                jp dev_ok_z

w5_gw:          db 0Ah, 0, 2, 2

dns_dot:
                push ix
                ld hl, (ix + F_HL)
                push hl
                ex de, hl
                ld b, 4
dd_oct:
                ld c, 0
dd_dig:
                ld a, (hl)
                cp '0'
                jr c, dd_fail
                cp '9' + 1
                jr nc, dd_fail
                sub '0'
                add a, c
                add a, a
                ld c, a
                add a, a
                add a, c
                ld c, a
                inc hl
                ld a, (hl)
                cp '.'
                jr z, dd_dot
                dec b
                jr z, dd_last
                jr dd_dig
dd_dot:
                inc hl
                pop de
                push de
                ld a, c
                ld (de), a
                inc de
                djnz dd_oct
                scf
                jr dd_out
dd_last:
                ld a, c
                pop de
                ld (de), a
                scf
dd_out:
                pop ix
                ret
dd_fail:
                pop hl
                pop ix
                or a
                ret

; Builds a UDP DNS query in the chip TX buffer for socket 3.
dns_query:
                ld e, Sn_TX_WR
                call w5_sx
                call w5_r16
                ex de, hl
                ld bc, dns_q_end - dns_q
                ld a, (net_s)
                call w5_buf_tx
                ret

dns_q:
                db 12h, 34h, 01h, 00h, 00h, 01h, 00h, 00h, 00h, 00h, 00h, 00h
                db 03h, 'w', 'w', 'w', 07h, 'e', 'x', 'a', 'm', 'p', 'l', 'e'
                db 03h, 'c', 'o', 'm', 00h, 00h, 01h, 00h, 01h
dns_q_end:

dns_answer:
                ld a, (net_s)
                ld (net_shift), a
                ld hl, (ix + F_HL)
                push hl
                ld e, Sn_RX_RD
                call w5_sx
                call w5_r16
                ld bc, 28
                add hl, bc
                ld a, (net_shift)
                add a, a
                add a, a
                add a, a
                add a, h
                add a, W5_RX0 >> 8
                ld h, a
                pop de
                ld bc, 4
                call w5_buf_rx
                xor a
                ret
dns_no:
                ld a, ENOENT
                scf
                ret
