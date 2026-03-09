
  ; `i2c.asm`

  ; --------------------------------------------------------------------------------------------------------------------------------

  i2c_delay:  var_delay_3_clc  40
              ret

  i2c_init:
            cbi    i2c_PORT, i2c_SDA
            cbi    i2c_PORT, i2c_SCL
            rcall  i2c_SDA_1 ; "отпускаем" линию
            rcall  i2c_SCL_1 ; "отпускаем" линию
            ret

  i2c_SCL_0:
            ; притянуть к "земле"
            sbi    i2c_DDR, i2c_SCL
            ret

  i2c_SCL_1:
            ; "третье состояние"
            cbi    i2c_DDR, i2c_SCL
            ret

  i2c_SDA_0:
            ; притянуть к "земле"
            sbi    i2c_DDR, i2c_SDA
            ret

  i2c_SDA_1:
            ; "третье состояние"
            cbi    i2c_DDR, i2c_SDA
            ret

  i2c_start:
            rcall  i2c_SDA_1 ; SCL: -----|------  |
            rcall  i2c_SCL_1 ;           |      \ |
            rcall  i2c_delay ;           |       \|
            rcall  i2c_SDA_0 ;           |        ------
            rcall  i2c_delay ; SDA: ------        |
            rcall  i2c_SCL_0 ;           |\       |
            rcall  i2c_delay ;           | \      |
            ret              ;           |  ------|-----

  i2c_stop:
            rcall  i2c_SCL_0 ;           |  ------|-----
            rcall  i2c_SDA_0 ;           | /      |
            rcall  i2c_delay ;           |/       |
            rcall  i2c_SCL_1 ; SCL: -----|        |
            rcall  i2c_delay ;           |        |-----
            rcall  i2c_SDA_1 ;           |       /|
            rcall  i2c_delay ;           |      / |
            ret              ; SDA: -----|------  |

  i2c_SCL_pulse:
            rcall  i2c_delay ;           |  ----  |
            rcall  i2c_SCL_1 ;           | /    \ |
            rcall  i2c_delay ;           |/      \|
            rcall  i2c_SCL_0 ; SCL: -----|        |-----
            ret

  i2c_rd_bit: ; return `t_1`
            rcall  i2c_SCL_1
            rcall  i2c_delay
            rcall  i2c_delay
            rcall  i2c_delay
            in     t_1, i2c_PIN ; read in `t_1` . bit # `i2c_SDA`
            rcall  i2c_delay
            rcall  i2c_SCL_0
            rcall  i2c_delay
            ret

  i2c_write: ; (t_1)
            ; MSB .. LSB
            ldi    t_0, 0x80
       i2c_write_loop:
            mov    t_2, t_1
            and    t_2, t_0
            breq   i2c_write_0
            rcall  i2c_SDA_1
            rjmp   i2c_write_1_
       i2c_write_0:
            rcall  i2c_SDA_0
       i2c_write_1_:
            rcall  i2c_SCL_pulse
            LSR    t_0
            brne   i2c_write_loop
            rcall  i2c_SDA_1  ; "отпускаем" линию
            rcall  i2c_rd_bit ; БИТ ПОДТВЕРЖДЕНИЯ.
            ret

  i2c_read: ; return `t_2`
            ; MSB .. LSB
            ldi    t_0, 0x80
            clr    t_2
            rcall  i2c_SDA_1 ; "отпускаем" линию
       i2c_read_loop:
            rcall  i2c_rd_bit
            sbrc   t_1, i2c_SDA
            or     t_2, t_0
            LSR    t_0
            brne   i2c_read_loop
            ; БИТ ПОДТВЕРЖДЕНИЯ (`0` или `1`)
            cpi    cnt_2, 1 ; последний байт с "высоким" подтверждением, остальные - с "низким"
            breq   i2c_read_ack_1
            rcall  i2c_SDA_0
            rjmp   i2c_read_ack_send
       i2c_read_ack_1:
            rcall  i2c_SDA_1
       i2c_read_ack_send:
            rcall  i2c_SCL_pulse
            ret

  ; --------------------------------------------------------------------------------------------------------------------------------

