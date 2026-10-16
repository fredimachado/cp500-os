; /bin/hi. Linked at ORIGIN. Prints one sample of each milestone 3 result, then exits 3.

                include "cp500.inc"

                org ORIGIN

hi:
                ld c, SYS_WRITE
                ld de, 1
                ld hl, hello
                ld ix, hello_end - hello
                rst 08h

                ld c, SYS_OPEN
                ld de, path_msg
                ld b, O_READ
                rst 08h
                ld a, l
                ld (fd), a
                ld c, SYS_READ
                ld e, a
                ld d, 0
                ld hl, rbuf
                ld ix, 7
                rst 08h
                ld c, SYS_WRITE
                ld de, 1
                ld hl, rbuf
                ld ix, 7
                rst 08h
                call cr

                ld c, SYS_OPEN
                ld de, path_root
                ld b, O_READ
                rst 08h
                ld a, l
                ld (fd), a
dir_loop:
                ld c, SYS_READDIR
                ld a, (fd)
                ld e, a
                ld d, 0
                ld hl, ent
                rst 08h
                jr c, dir_missing
                ld a, h
                or l
                jr z, dir_missing
                ld hl, ent + 2
                ld de, name_bin
                call name_is_bin
                jr nz, dir_loop
                ld hl, name_bin
                call puts
                jr dir_done
dir_missing:
                ld hl, missing_text
                call puts
dir_done:
                ld c, SYS_OPEN
                ld de, path_msg
                ld b, O_WRITE
                rst 08h
                jr nc, wrote
                cp EROFS
                jr nz, wrote
                ld hl, erofs_text
                call puts
wrote:
                ld c, SYS_GETCWD
                ld de, pathbuf
                ld hl, 16
                rst 08h
                ld hl, pathbuf
                call puts

                ld c, SYS_CHDIR
                ld de, path_bin
                rst 08h
                ld c, SYS_GETCWD
                ld de, pathbuf
                ld hl, 16
                rst 08h
                ld hl, pathbuf
                call puts

                ld c, SYS_CHDIR
                ld de, path_msg
                rst 08h
                cp ENOTDIR
                jr nz, seek_msg
                ld hl, enotdir_text
                call puts

seek_msg:
                ld c, SYS_OPEN
                ld de, path_msg
                ld b, O_READ
                rst 08h
                ld a, l
                ld (fd), a
                ld c, SYS_SEEK
                ld e, a
                ld d, 0
                ld hl, seek_at
                ld b, 0
                rst 08h
                ld c, SYS_READ
                ld a, (fd)
                ld e, a
                ld d, 0
                ld hl, rbuf
                ld ix, 2
                rst 08h
                ld c, SYS_WRITE
                ld de, 1
                ld hl, rbuf
                ld ix, 2
                rst 08h
                call cr

                ld c, SYS_EXIT
                ld de, 3
                rst 08h

puts:
                ld a, (hl)
                or a
                jr z, cr
                push hl
                call one
                pop hl
                inc hl
                jr puts

cr:
                ld a, 0Dh
one:
                ld (byte1), a
                ld c, SYS_WRITE
                ld de, 1
                ld hl, byte1
                ld ix, 1
                rst 08h
                ret

name_is_bin:
                ld b, 3
name_cmp:
                ld a, (de)
                cp (hl)
                ret nz
                inc hl
                inc de
                djnz name_cmp
                ld a, (hl)
                or a
                ret

hello:          db "hello", 0Dh
hello_end:
path_msg:       db "/msg", 0
path_root:      db "/", 0
path_bin:       db "/bin", 0
name_bin:       db "bin", 0
missing_text:   db "MISSING", 0
erofs_text:     db "EROFS", 0
enotdir_text:   db "ENOTDIR", 0
seek_at:        db 5, 0, 0, 0
fd:             db 0
byte1:          db 0
rbuf:           ds 8, 0
ent:            ds 32, 0
pathbuf:        ds 16, 0
