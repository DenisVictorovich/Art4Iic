
; -------------------------------------------------------------------------------------------------------------------------------- ;
;                          КОНВЕРТЕР ПОСЛЕДОВАТЕЛЬНОГО АСИНХРОННОГО КАНАЛА В СИНХРОНИЗОВАННЫЙ ТИПА  «I2C»                          ;
;                                   (линии SCL и SDA должны быть «подтянуты вверх» через 10 кОм)                                   ;
; -------------------------------------------------------------------------------------------------------------------------------- ;

.include "tn45def.asm"
.include "macro.asm"

;-------------------------------------------------;
; ___           ------                            ;
; rst / PB5 ===|      |=== 3.0 V ---------------| ;
;  --== PB3 ===| tiny |=== PB2 - SDA ---|10к|---| ;
;  --== PB4 ===|  45  |=== PB1 - SCL ---|10к|---| ;
;       gnd ===|      |=== PB0 - R/T ---|10к|---| ;
;               ------                            ;
;-------------------------------------------------;

; ----------------------------------------------------------------------------------------------------------------------------------

; АСИНХРОННЫЙ ПРИЁМНИК - ПЕРЕДАТЧИК :

.equ   art_DDR    = DDRB
.equ   art_PORT   = PORTB
.equ   art_PIN    = PINB

.equ   art_R      = 0
.equ   art_T      = 0

; ЭМПИРИЧЕСКИЕ ПОСТОЯННЫЕ :
; 115,2 кГц при частоте кварцевого резонатора 11,0592 МГц
.equ   art_R_pause_value        =  30
.equ   art_R_shift_pause_value  =  10
.equ   art_T_pause_value        =  28

; ----------------------------------------------------------------------------------------------------------------------------------

; ДВУХПРОВОДНЫЙ ДВУНАПРАВЛЕННЫЙ СИНРОНИЗОВАННЫЙ КАНАЛ СВЯЗИ :

.equ   i2c_DDR    = DDRB
.equ   i2c_PORT   = PORTB
.equ   i2c_PIN    = PINB

.equ   i2c_SCL    = 1
.equ   i2c_SDA    = 2

; ----------------------------------------------------------------------------------------------------------------------------------

.equ   SRAM_START = 0x0100
.equ   SRAM_SIZE  = 0x0060

; -----------------
; r13,r14,r15 ЗАНЯТЫ !
; -----------------
.def  t_0     = r16 ; temporary # 0
; -----------------
.def  t_1     = r17 ; temporary # 1
.def  t_2     = r18 ; temporary # 2
; -----------------
.def  delay_c = r20
; -----------------
.def  data_c  = r21
; -----------------
.def  action  = r22
.def  nibble  = r23
; -----------------
.def  cnt_1   = r24
.def  cnt_2   = r25
; -----------------

.equ  r_buffer = SRAM_START ; начало приемного буфера порта в оперативной памяти контроллера - ОБЯЗАТЕЛЬНО "МЛАДШИЕ" 8 РАЗРЯДОВ Д.Б. "0"

.ORG 0x000 ; начнём с начала

; `interrupts links`

rjmp   RESET ; reset handler

reti
reti
reti
reti
reti
reti
reti
reti
reti
reti
reti
reti
reti
reti
reti
reti
reti
reti
reti
reti
reti
reti
reti
reti
reti
reti
reti
reti
reti
reti
reti
reti
reti
reti
reti
reti
reti
reti
reti
reti
reti
reti
reti
reti
reti
reti
reti
reti
reti
reti

RESET:

  cli

  ; hw init
  ; set stack pointer to top of ram
  out_i  SPH, high(RAMEND)
  out_i  SPL, low (RAMEND)

  out_i  ACSR, 1 << ACD ; analog comparator disable

  out_i  WDTCR, 24
  out_i  WDTCR, 15
  wdr

  rcall  i2c_init
  rcall  port_configure

  rcall  pack_begin
  ldi_Z  welcome_text
  rcall  sndstr
  rcall  pack_end

  ; sw init
  ; r_buffer  := 00|00|00 ...
  ; стираем SRAM_SIZE байтов с r_buffer байта
  rcall  r_buffer_init
  clr    t_0
  ldi    cnt_2, high(SRAM_SIZE)
  ldi    cnt_1, low (SRAM_SIZE)
  clear_memory_loop:
     wdr
     st    Y+, t_0
     sbiw  cnt_2:cnt_1, 1
     brne  clear_memory_loop
  rcall  r_buffer_init
  clr    t_0
  clr    t_1
  clr    t_2
  clr    delay_c
  clr    data_c
  clr    action
  clr    nibble
  clr    cnt_1
  clr    cnt_2

 LOOP: ; основной цикл
    wdr

    rcall  check_receive
    brts   LOOP

       ; селектор захвата принятого байта, находящегося в ячейке `t_0`

          ; начать принимать данные
          cpi   t_0, '>'
            breq  init_receiving

          ; завершить приём данных
          cpi   t_0, 13 ; [CR]
            breq  LOOP ; игнорируем
          cpi   t_0, 10 ; [LF]
            breq  action_do ; ПРИНЯЛИ ПАКЕТ ...
          cpi   t_0, '\' ; альтернативный признак конца пакета
            breq  action_do ; ПРИНЯЛИ ПАКЕТ ...

          st     Y+, t_0
          rjmp   LOOP

       init_receiving:
          rcall  r_buffer_init
          rjmp   LOOP

; ----------------------------------------------------------------------------------------------------------------------------------

       action_do:
          tst     YL
          breq    LOOP ; если данных в буфере нету ...
          mov     cnt_1, YL
          rcall   r_buffer_init
          clr     data_c

       symbols_capture_loop:
          wdr
          ld      t_0, Y+
          cpi     t_0, 's' ; start condition
          breq    i2c_start_condition
          cpi     t_0, 'r' ; read data
          breq    begin_to_read_data
          cpi     t_0, 'c' ; wait for `SCL`
          breq    wait_for_SCL
          cpi     t_0, 'e' ; debug mode <<echo>>
          breq    debug_send_data
          ; <...>
          rcall   byte_capture
          rjmp    get_next_symbol

       i2c_start_condition:
          rcall   i2c_start
          rjmp    get_next_symbol

       begin_to_read_data:
          ldi     action, 1 ; `read mode`
          rjmp    get_next_symbol

       wait_for_SCL:
          rcall   i2c_SCL_1 ; чтобы "отпустить" линию `SCL`
          ; Generated by delay loop calculator
          ; at http://www.bretmulvey.com/avrdelay.html
          ; Delay 11 059 200 cycles
          ; 1s at 11.0592 MHz {без дополнительных действий}
          ldi     t_0, 57
          mov     r13, t_0
          ldi     t_0, 27
          mov     r14, t_0
          ldi     t_0, 114
          mov     r15, t_0
         wait_for_SCL_lbl:
          wdr
          sbic    i2c_PIN, i2c_SCL
          rjmp    wait_for_SCL_end ; переход только когда `SCL` "отпущена" ведомым
          dec     r15
          brne    wait_for_SCL_lbl
          dec     r14
          brne    wait_for_SCL_lbl
          dec     r13
          brne    wait_for_SCL_lbl
         wait_for_SCL_end:
          rcall   i2c_SCL_0 ; чтобы вновь передавать и принимать данные ...
          rjmp  get_next_symbol

       debug_send_data:
          dec     cnt_1 ; ???
          rcall   pack_begin
         debug_send_loop:
          tst     cnt_1
          breq    debug_send_end
          ld      t_1, Y+
          rcall   send
          dec     cnt_1
          rjmp    debug_send_loop
         debug_send_end:
          rcall   pack_end
          rjmp    LOOP

       get_next_symbol:
          dec     cnt_1
          brne    symbols_capture_loop
       i2c_stop_condition:
          rcall   i2c_stop
          cpi     action, 1 ; `read mode`
          breq    is_read_action
          rcall   pack_begin
          mov     t_2, data_c
          rcall   send2
          rcall   pack_end
       is_read_action:
          rcall   r_buffer_init
          rjmp    LOOP

; ----------------------------------------------------------------------------------------------------------------------------------

       ; захват принятого байта (HI,LO)
       byte_capture:
             sbrc   nibble, 0
             rjmp   byte_receive ; nibble.0 = 1 (LO)
             mov    t_1, t_0
             rcall  s2d
             swap   t_1 ; move to the HI nibble
             mov    t_2, t_1 ; capture the HI nibble
             inc    nibble
             ret

       ; захват принятого байта (LO)
       byte_receive:
             mov    t_1, t_0 ; capture the LO nibble
             rcall  s2d
             inc    nibble
             or     t_2, t_1
             ; байт принят в символьной форме и находится в `t_2`
             cpi    action, 1 ; `read mode`
             brne   write_mode_action
             mov    cnt_2, t_2
             clr    t_2
             ; ПОЛУЧИЛИ КОЛИЧЕСТВО ЧИТАЕМЫХ БАЙТОВ,
             ; ТЕПЕРЬ ЧИТАЕМ ЗАПРАШИВАЕМЫЕ ДАННЫЕ:
             rcall  pack_begin
          i2c_read_data_loop:
             wdr
             rcall   i2c_read
             ; send the data
             rcall   send2
             dec     cnt_2
             brne    i2c_read_data_loop
             rcall   pack_end
             ret
          write_mode_action:
             mov    t_1, t_2
             clr    t_2
             rcall  i2c_write
             inc    data_c
             ret

; ----------------------------------------------------------------------------------------------------------------------------------

r_buffer_init:
          ldi_Y   r_buffer
          ldi     action, 0 ; `write mode`
          clr     nibble
          ret

; ----------------------------------------------------------------------------------------------------------------------------------

pack_begin:
          rcall   transmitt
          ldi     t_1, '<'
          rcall   send
          ret

; ----------------------------------------------------------------------------------------------------------------------------------

pack_end:
          ldi     t_1, 13 ; [CR]
          rcall   send
          ldi     t_1, 10 ; [LF]
          rcall   send
          rcall   wait_end_of_sending
          rcall   receive
          ret

; ----------------------------------------------------------------------------------------------------------------------------------

receive: ; (void)
          rcall  i2c_delay
          cbi    art_DDR,  art_R
          cbi    art_PORT, art_R
          ret

; ----------------------------------------------------------------------------------------------------------------------------------

transmitt: ; (void)
          rcall  i2c_delay
          sbi    art_PORT, art_R
          sbi    art_DDR,  art_R
          rcall  i2c_delay
          ret

; ----------------------------------------------------------------------------------------------------------------------------------

.include "ART.asm"  ; asynchronous receiver / transmitter
.include "I2C.asm"  ; I2C functions

; ----------------------------------------------------------------------------------------------------------------------------------

welcome_text: .db "`ART4IIC` - welcome",0

; ----------------------------------------------------------------------------------------------------------------------------------

