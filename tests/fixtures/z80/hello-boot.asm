; Minimal boot sector for end-to-end boot tests: shows BOOT OK and spins.

    include "cp500.inc"

    org BOOT_SECTOR

    di
    ld hl, message
    ld de, VIDEO_BASE
    ld bc, message_end - message
    ldir
    jr $

message:
    db "BOOT OK"
message_end:

    assert $ - BOOT_SECTOR <= BOOT_SECTOR_SIZE, "boot sector is larger than one sector"
