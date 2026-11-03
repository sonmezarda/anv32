    # UART bootloader. anv32_soc_top (HAS_BOOTLOADER) puts it in the top 1 KiB
    # of the BRAM, resets the core into it and drops data writes to it, so a
    # program cannot overwrite it.
    #
    # After a power-on or button reset SYSCTRL STATUS.BOOT_REQ is clear and it
    # jumps straight to the program at 0. A host resets the SoC with BOOT_REQ
    # set by sending the boot trigger (anv32_boot_trigger) over UART0; then:
    #
    #   board -> host   "anv32 boot\r\n"
    #   host  -> board  'L', length (4 bytes, little endian, a multiple of 4,
    #                   at most the bootloader address), CRC-32 of the image
    #                   (4 bytes, little endian, zlib/IEEE), the image
    #   board -> host   'K' and runs the image from 0, or
    #                   'S' bad length, 'E' CRC mismatch, 'T' byte timeout,
    #                   then waits for the next 'L'
    #
    # Without an 'L' for about 2 s it runs the old program, unless a failed
    # load has already overwritten part of it. tools/uart_load.py is the host
    # side. RV32I only, no stack and position independent (it finds its own
    # address with la), so it runs on every core and BRAM size; registers:
    #   s0 UART0 base, s1 SYSCTRL base, s2 length, s3 expected CRC,
    #   s4 write address, s5 running CRC, s6 image overwritten,
    #   s7 word being assembled, s8 byte shift, a3 CRC polynomial
    #   getc returns through t6, the other helpers through ra

#define UART0_BASE      0x10002000
#define SYSCTRL_BASE    0x10000000
#define UART_TXDATA     0x00
#define UART_STATUS     0x04
#define UART_ERROR      0x0C
#define UART_RXDATA     0x10
#define TX_READY        (1 << 0)
#define TX_EMPTY        (1 << 1)
#define RX_VALID        (1 << 4)
#define SYSCTRL_STATUS  0x04
#define BOOT_REQ        (1 << 0)

    # Polling loop iterations, about 8 cycles each at 27 MHz
#define CMD_TIMEOUT     0x00670000      # ~2 s
#define BYTE_TIMEOUT    0x00053000      # ~100 ms

    .section .text.init
    .globl _start
_start:
    li    s0, UART0_BASE
    li    s1, SYSCTRL_BASE
    lw    t0, SYSCTRL_STATUS(s1)
    andi  t0, t0, BOOT_REQ
    beqz  t0, run_image
    li    t0, BOOT_REQ
    sw    t0, SYSCTRL_STATUS(s1)

    # Drop whatever the receiver caught around the trigger
flush:
    lw    t0, UART_STATUS(s0)
    andi  t0, t0, RX_VALID
    beqz  t0, 1f
    lw    t0, UART_RXDATA(s0)
    j     flush
1:
    li    t0, 1
    sw    t0, UART_ERROR(s0)

    li    s6, 0
    li    a3, 0xEDB88320
    la    a0, hello
    jal   puts

wait_cmd:
    li    a1, CMD_TIMEOUT
    jal   t6, getc
    bgez  a0, 1f
    beqz  s6, run_image         # timed out: run the old program if it is intact
    j     wait_cmd
1:
    li    t0, 'L'
    bne   a0, t0, wait_cmd

    jal   get_word
    bltz  a1, timeout
    mv    s2, a0
    jal   get_word
    bltz  a1, timeout
    mv    s3, a0

    andi  t0, s2, 3
    bnez  t0, bad_size
    beqz  s2, bad_size
    la    t0, _start
    bgtu  s2, t0, bad_size

    li    s4, 0
    li    s5, -1
    li    s6, 1
next_word:
    li    s7, 0
    li    s8, 0
next_byte:
    li    a1, BYTE_TIMEOUT
    jal   t6, getc
    bltz  a0, timeout
    xor   s5, s5, a0            # CRC-32, one bit at a time
    li    t1, 8
2:
    andi  t2, s5, 1
    srli  s5, s5, 1
    beqz  t2, 3f
    xor   s5, s5, a3
3:
    addi  t1, t1, -1
    bnez  t1, 2b
    sll   a0, a0, s8
    or    s7, s7, a0
    addi  s8, s8, 8
    li    t0, 32
    bne   s8, t0, next_byte
    sw    s7, 0(s4)
    addi  s4, s4, 4
    bltu  s4, s2, next_word

    not   s5, s5
    bne   s5, s3, bad_crc
    li    a0, 'K'
    jal   putc
1:
    lw    t0, UART_STATUS(s0)   # let the 'K' out before the program takes the UART
    andi  t0, t0, TX_EMPTY
    beqz  t0, 1b
run_image:
    jr    zero

bad_size:
    li    a0, 'S'
    j     reply
bad_crc:
    li    a0, 'E'
    j     reply
timeout:
    li    a0, 'T'
reply:
    jal   putc
    j     wait_cmd

    # a0 = next byte, or -1 after a1 polls with nothing received
getc:
    lw    t0, UART_STATUS(s0)
    andi  t0, t0, RX_VALID
    bnez  t0, 1f
    addi  a1, a1, -1
    bnez  a1, getc
    li    a0, -1
    jr    t6
1:
    lw    a0, UART_RXDATA(s0)
    andi  a0, a0, 0xFF
    jr    t6

    # a0 = next 4 bytes, little endian; a1 < 0 on timeout
get_word:
    li    t3, 0
    li    t4, 0
1:
    li    a1, BYTE_TIMEOUT
    jal   t6, getc
    bltz  a0, 2f
    sll   a0, a0, t4
    or    t3, t3, a0
    addi  t4, t4, 8
    li    t0, 32
    bne   t4, t0, 1b
    mv    a0, t3
    li    a1, 0
    ret
2:
    li    a1, -1
    ret

putc:
    lw    t0, UART_STATUS(s0)
    andi  t0, t0, TX_READY
    beqz  t0, putc
    sw    a0, UART_TXDATA(s0)
    ret

    # Prints the string at a0
puts:
    lbu   t1, 0(a0)
    beqz  t1, 2f
1:
    lw    t0, UART_STATUS(s0)
    andi  t0, t0, TX_READY
    beqz  t0, 1b
    sw    t1, UART_TXDATA(s0)
    addi  a0, a0, 1
    j     puts
2:
    ret

    .section .rodata
hello:
    .asciz "anv32 boot\r\n"
