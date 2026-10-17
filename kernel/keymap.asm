; /sys/keymap. The kernel loads it to KEYMAP at mount. 0 is no key.

                include "cp500.inc"

                org KEYMAP

                db '@', 'a', 'b', 'c', 'd', 'e', 'f', 'g'
                db 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o'
                db 'p', 'q', 'r', 's', 't', 'u', 'v', 'w'
                db 'x', 'y', 'z', 0, 0, 0, 0, 0
                db '0', '1', '2', '3', '4', '5', '6', '7'
                db '8', '9', ':', ';', ',', '-', '.', '/'
                db 0Dh, K_CLEAR, K_BREAK, '[', K_DOWN, K_LEFT, K_RIGHT, ' '
                db 0, 0, 0, 0, 0, 0, 0, 0

                assert $ == KBD_SHIFTED
                db '@', 'A', 'B', 'C', 'D', 'E', 'F', 'G'
                db 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O'
                db 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W'
                db 'X', 'Y', 'Z', 0, 0, 0, 0, 0
                db 0, '!', '"', '#', '$', '%', '&', "'"
                db '(', ')', '*', '+', '<', '=', '>', '?'
                db 0Dh, K_CLEAR, K_BREAK, 0, K_DOWN, K_LEFT, K_RIGHT, ' '
                db 0, 0, 0, 0, 0, 0, 0, 0

                assert $ - KEYMAP <= 256
