; /bin/sh. Linked at ORIGIN and packed by mkreloc. The line buffer is bss.

                include "cp500.inc"

                org ORIGIN

shell:
                ld c, SYS_WRITE
                ld de, 1
                ld hl, prompt_seq
                ld ix, prompt_end - prompt_seq
                rst 08h
                ld iy, line

read_loop:
                dec sp
                ld hl, 0
                add hl, sp
                push hl
                ld c, SYS_READ
                ld de, 0
                ld ix, 1
                rst 08h
                pop hl
                push hl
                ld c, SYS_WRITE
                ld de, 1
                ld ix, 1
                rst 08h
                pop hl
                ld a, (hl)
                inc sp
                cp 0Dh
                jr z, got_line
                push af
                push iy
                pop hl
                ld de, line + 127
                or a
                sbc hl, de
                jr c, store_byte
                pop af
                jp read_loop
store_byte:
                pop af
                ld (iy + 0), a
                inc iy
                jp read_loop

got_line:
                xor a
                ld (iy + 0), a
                ld a, (line)
                or a
                jp z, shell
                cp '>'
                jr nz, try_query
                ld a, (line + 1)
                cp ' '
                jr nz, run_path
                ld c, SYS_OPEN
                ld de, line + 2
                ld b, O_WRITE
                rst 08h
                jp c, show_err
                ld e, l
                ld d, 0
                ld c, SYS_CLOSE
                rst 08h
                jp shell

try_query:
                cp '?'
                jr nz, run_path
                ld a, (line + 1)
                cp ' '
                jr nz, run_path
                ld c, SYS_SPAWN
                ld de, line + 2
                ld hl, empty
                ld ix, 0
                rst 08h
                jp c, show_err
                ld hl, ok_text
                call write_str
                jp shell

run_path:
                ld c, SYS_SPAWN
                ld de, line
                ld hl, empty
                ld ix, 0
                rst 08h
                jp c, show_err
                ld c, SYS_WAIT
                ld de, 0FFh
                rst 08h
                jp c, show_err
                ld a, l
                or a
                jp z, shell
                push af
                ld hl, exit_text
                call write_str
                pop af
                call write_dec
                ld a, 0Dh
                call write_byte
                jp shell

show_err:
                ld c, a
                ld hl, err_table
err_find:
                ld a, (hl)
                or a
                jr z, err_other
                cp c
                jr z, err_hit
                inc hl
                inc hl
                inc hl
                jr err_find
err_hit:
                inc hl
                ld e, (hl)
                inc hl
                ld d, (hl)
                ex de, hl
                call write_str
                jr err_cr
err_other:
                ld hl, err_text
                call write_str
err_cr:
                ld a, 0Dh
                call write_byte
                jp shell

write_str:
                ld a, (hl)
                or a
                ret z
                push hl
                call write_byte
                pop hl
                inc hl
                jr write_str

write_dec:
                ld c, a
                xor a
                ld (line), a
                ld d, 100
                call dec_digit
                ld d, 10
                call dec_digit
                ld a, 1
                ld (line), a
                ld d, 1
dec_digit:
                ld e, 0
dec_sub:
                ld a, c
                cp d
                jr c, dec_out
                sub d
                ld c, a
                inc e
                jr dec_sub
dec_out:
                ld a, (line)
                or e
                ret z
                ld a, 1
                ld (line), a
                push bc
                ld a, e
                add a, '0'
                call write_byte
                pop bc
                ret

write_byte:
                dec sp
                ld hl, 0
                add hl, sp
                ld (hl), a
                push hl
                ld c, SYS_WRITE
                ld de, 1
                ld ix, 1
                rst 08h
                pop hl
                inc sp
                ret

prompt_seq:
                db 1Bh, "[4;1H"
                db "sh>"
                db 1Bh, "[5;1H"
prompt_end:
                assert prompt_end - prompt_seq == 15

empty:          db 0, 0
ok_text:        db "ok", 0Dh, 0
exit_text:      db "exit ", 0
err_text:       db "ERR", 0

err_table:
                db ENOENT
                dw e_enoent
                db EEXIST
                dw e_eexist
                db ENOMEM
                dw e_enomem
                db EBADF
                dw e_ebadf
                db EINVAL
                dw e_einval
                db EIO
                dw e_eio
                db ENOTDIR
                dw e_enotdir
                db EISDIR
                dw e_eisdir
                db ENOEXEC
                dw e_enoexec
                db EMFILE
                dw e_emfile
                db ECHILD
                dw e_echild
                db EROFS
                dw e_erofs
                db EBUSY
                dw e_ebusy
                db 0

e_enoent:       db "ENOENT", 0
e_eexist:       db "EEXIST", 0
e_enomem:       db "ENOMEM", 0
e_ebadf:        db "EBADF", 0
e_einval:       db "EINVAL", 0
e_eio:          db "EIO", 0
e_enotdir:      db "ENOTDIR", 0
e_eisdir:       db "EISDIR", 0
e_enoexec:      db "ENOEXEC", 0
e_emfile:       db "EMFILE", 0
e_echild:       db "ECHILD", 0
e_erofs:        db "EROFS", 0
e_ebusy:        db "EBUSY", 0

line:
