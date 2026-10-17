; Full-screen editor. Printable keys overwrite. :w ENTER saves, :q ENTER quits.
; Arrows are ESC [ A/B/C/D.

                include "cp500.inc"

                org ORIGIN

                ld (argv), hl
                ld a, 1
                call arg_ptr
                ld a, EINVAL
                jp c, fail
                ld (path), hl
                ld c, SYS_OPEN
                ex de, hl
                ld b, O_READ
                rst 08h
                jp c, fail
                ld a, l
                ld (fd), a
                ld c, SYS_READ
                ld e, a
                ld d, 0
                ld hl, text
                ld ix, 512
                rst 08h
                jp c, fail
                ld (len), hl
                ld hl, 0
                ld (cur), hl
                call draw
ed_key:
                call getc
                cp 1Bh
                jr z, ed_esc
                cp ':'
                jr z, ed_cmd
                cp 20h
                jr c, ed_key
                ld hl, (cur)
                ld de, (len)
                or a
                sbc hl, de
                jr nc, ed_key
                add hl, de
                ld de, text
                add hl, de
                ld (hl), a
                ld hl, (cur)
                inc hl
                ld (cur), hl
                call draw
                jr ed_key
ed_esc:
                call getc
                cp '['
                jr nz, ed_key
                call getc
                cp 'D'
                jr z, ed_left
                cp 'C'
                jr z, ed_right
                cp 'A'
                jr z, ed_up
                cp 'B'
                jr z, ed_down
                jr ed_key
ed_left:
                ld hl, (cur)
                ld a, h
                or l
                jr z, ed_key
                dec hl
                ld (cur), hl
                call draw
                jr ed_key
ed_right:
                ld hl, (cur)
                ld de, (len)
                inc hl
                or a
                sbc hl, de
                jr nc, ed_key
                ld hl, (cur)
                inc hl
                ld (cur), hl
                call draw
                jr ed_key
ed_up:
                call prev_line
                call draw
                jp ed_key
ed_down:
                call next_line
                call draw
                jp ed_key
ed_cmd:
                call getc
                cp 'w'
                jr z, ed_save
                cp 'q'
                jp z, exit0
                jp ed_key
ed_save:
                call getc
                cp 0Dh
                jp nz, ed_key
                ld c, SYS_OPEN
                ld hl, (path)
                ex de, hl
                ld b, O_WRITE | O_TRUNC
                rst 08h
                jp c, fail
                ld a, l
                ld (fd), a
                ld hl, text
                ld (ptr), hl
                ld hl, (len)
                ld (left), hl
ed_chunk:
                ld hl, (left)
                ld a, h
                or l
                jp z, exit0
                ld a, h
                or a
                jr z, ed_short
                ld bc, 256
                jr ed_n
ed_short:
                ld c, l
                ld b, 0
ed_n:
                push bc
                ld c, SYS_WRITE
                ld a, (fd)
                ld e, a
                ld d, 0
                ld hl, (ptr)
                pop ix
                push ix
                rst 08h
                jp c, fail
                pop bc
                ld hl, (ptr)
                add hl, bc
                ld (ptr), hl
                ld hl, (left)
                or a
                sbc hl, bc
                ld (left), hl
                jr ed_chunk

draw:
                ld hl, cls
                call puts
                ld hl, text
                ld bc, (len)
draw_ch:
                ld a, b
                or c
                jr z, draw_cur
                ld a, (hl)
                push hl
                push bc
                call putc
                pop bc
                pop hl
                inc hl
                dec bc
                jr draw_ch
draw_cur:
                ret

getc:
                ld c, SYS_READ
                ld de, 0
                ld hl, ch
                ld ix, 1
                rst 08h
                ld a, (ch)
                ret

next_line:
                ld hl, (cur)
                ld de, text
                add hl, de
                ld bc, (len)
                ld de, (cur)
nl:
                ld a, b
                or c
                ret z
                ld a, e
                cp l
                jr nz, nl_adv
                ld a, d
                cp h
                jr nz, nl_adv
nl_adv:
                ld a, (hl)
                inc hl
                inc de
                dec bc
                cp 0Dh
                jr nz, nl
                ld (cur), de
                ret

prev_line:
                ld hl, (cur)
                ld a, h
                or l
                ret z
                dec hl
                ld (cur), hl
                ld a, h
                or l
                ret z
                dec hl
                ld de, text
                add hl, de
                ld a, (hl)
                cp 0Dh
                ret nz
                ret

cls:            db 1Bh, "[2J", 1Bh, "[H", 0
path:           dw 0
fd:             db 0
len:            dw 0
cur:            dw 0
ptr:            dw 0
left:           dw 0

                include "run.inc"

text:
