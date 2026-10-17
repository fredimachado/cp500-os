; Shared command routines. HL on entry is the argv block; store it in argv.

argv:           dw 0

; A = string index, including the program path at 0. Carry when it is missing.
arg_ptr:
                ld hl, (argv)
                ld b, (hl)
                cp b
                ccf
                ret c
                inc hl
                inc hl
                ld b, a
                inc b
ap_skip:
                dec b
                ret z
ap_ch:
                ld a, (hl)
                inc hl
                or a
                jr nz, ap_ch
                jr ap_skip

puts:
                ld a, (hl)
                or a
                ret z
                push hl
                call putc
                pop hl
                inc hl
                jr puts

putc:
                ld (ch), a
                ld c, SYS_WRITE
                ld de, 1
                ld hl, ch
                ld ix, 1
                rst 08h
                ret

cr:
                ld a, 0Dh
                jr putc

; A = error code. Prints its name and exits with it.
fail:
                ld c, a
                push bc
                ld hl, err_tab
fail_find:
                ld a, (hl)
                or a
                jr z, fail_exit
                cp c
                jr z, fail_hit
                inc hl
                inc hl
                inc hl
                jr fail_find
fail_hit:
                inc hl
                ld e, (hl)
                inc hl
                ld d, (hl)
                ex de, hl
                call puts
                call cr
fail_exit:
                pop de
                ld d, 0
                ld c, SYS_EXIT
                rst 08h

exit0:
                ld c, SYS_EXIT
                ld de, 0
                rst 08h

err_tab:
                db ENOENT
                dw e_enoent
                db EEXIST
                dw e_eexist
                db EINVAL
                dw e_einval
                db ENOSPC
                dw e_enospc
                db EIO
                dw e_eio
                db ENOTDIR
                dw e_enotdir
                db EISDIR
                dw e_eisdir
                db EROFS
                dw e_erofs
                db ENOTEMPTY
                dw e_enotempty
                db EBUSY
                dw e_ebusy
                db 0

e_enoent:       db "ENOENT", 0
e_eexist:       db "EEXIST", 0
e_einval:       db "EINVAL", 0
e_enospc:       db "ENOSPC", 0
e_eio:          db "EIO", 0
e_enotdir:      db "ENOTDIR", 0
e_eisdir:       db "EISDIR", 0
e_erofs:        db "EROFS", 0
e_enotempty:    db "ENOTEMPTY", 0
e_ebusy:        db "EBUSY", 0
ch:             db 0
