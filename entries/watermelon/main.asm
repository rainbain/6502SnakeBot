; -----------------------------------------------------------------------------
; 6502SnakeBot - 6502 snake robot competition
; File: watermelon.asm
;
; Part of the 6502SnakeBot project (https://github.com/rainbain/6502SnakeBot)
;
; Copyright (c) 2026 Samuel Fitzsimons
;
; This file is licensed under the MIT License.
; See the LICENSE file in the project root for full license terms.
;
; Watermelon Snake Bot
; -----------------------------------------------------------------------------

; Memory Map
BOARD                 = $4000
STATE_CONTROL         = $5000
STATE_SNAKE_DIRECTION = $5001
STATE_DEBUG           = $5002

ISR_IRQ_L = $FFFE
ISR_IRQ_H = $FFFF

; Game Parameters
BOARD_WIDTH = 17
BOARD_HEIGHT = 17

SNAKE_START_X = (BOARD_WIDTH / 2)
SNAKE_START_Y = (BOARD_HEIGHT / 2)

BOARD_SNAKE_START = (BOARD + (SNAKE_START_X + SNAKE_START_Y * BOARD_WIDTH))

; Tiles
TILE_TYPE_EMPTY      = (0<<4)
TILE_TYPE_SNAKE_HEAD = (1<<4)
TILE_TYPE_SNAKE_BODY = (2<<4)
TILE_TYPE_SNAKE_TAIL = (3<<4)
TILE_TYPE_FOOD       = (4<<4)

DIR_LEFT             = (1<<0)
DIR_RIGHT            = (1<<1)
DIR_UP               = (1<<2)
DIR_DOWN             = (1<<3)

; We will use our internal direction enum to save space
; These are lookups into the direction addend table!
INT_DIR_LEFT       = 2
INT_DIR_RIGHT      = 6
INT_DIR_UP         = 10
INT_DIR_DOWN       = 14

ZP_SNAKE_CTL_SIZE = $8

; Zero Page Layout
MOVE_HEAD = $0
MOVE_SET_START = $1
MOVE_SET_REPEAT_COUNT = $2
MOVE_REPEAT_COUNT = $3
SNAKE_MEM_LO = $4
SNAKE_MEM_HI = $5
SNAKE_DIRECTION = $6
SNAKE_X = $7

ZP_TMP_0 = $8

SNAKE_CTL_BEST = (ZP_SNAKE_CTL_SIZE + 1)
SNAKE_CTL_CURRENT = (ZP_SNAKE_CTL_SIZE * 2 + 1)
SNAKE_DIRECTION_ADDENDS = (ZP_SNAKE_CTL_SIZE * 3 + 1)
TAPE = (ZP_SNAKE_CTL_SIZE * 3 + 16)

init:
    ; Load IRQ
    ; We can skip setting high, it defaults to 0x80--
    ;LDA #>IRQ
    ;STA ISR_IRQ_H
    LDA #<IRQ
    STA ISR_IRQ_L

    ; Copy RAM image into RAM
    LDX #40
s3:
    LDA RAM_IMAGE, X
    STA SNAKE_CTL_CURRENT, X
    DEX
    BPL s3

    ; Get the movement copy
    LDX #19
s4:
    LDA RAM_COPY_START, X
    STA TAPE+17, X
    DEX
    BPL s4

    ; Zero out movements to run alternate
    LDA #$0
    STA TAPE+17+14
    STA TAPE+17+15
    LDA #(6<<4)
    STA TAPE+17+8

    ; Enable interrupts
    CLI
LOOP:
    ;JMP LOOP
    ; Appears to work without loop!

CYCLE:
    ; Subtract 1 move
    DEC MOVE_REPEAT_COUNT
    BPL done ; No underflow, your good
    
    ; Get next move
    LDX MOVE_HEAD
    INX

    ; Wrap around when it reaches tape size
    CPX #TAPE_SIZE
    BNE skip_wrap_around
    LDX #$0
skip_wrap_around:
    STX MOVE_HEAD
    LDA TAPE, X
    ; Get move
    TAX
    LSR A
    LSR A
    LSR A
    LSR A
    TAY
    TXA
    AND #$0F

    ; If its zero, repeat move set
    BNE skip_repeat

    ; If repeat count just underflowed, load next move set
    DEC MOVE_SET_REPEAT_COUNT
    BPL skip_next_move_set

    ; Upper nibble repeat count
    STY MOVE_SET_REPEAT_COUNT

    ; Current move head becomes start of move set
    LDX MOVE_HEAD
    STX MOVE_SET_START
skip_next_move_set:
    ; Refresh and go to top
    LDX MOVE_SET_START
    STX MOVE_HEAD

    ; JMP replaced with BPL to save a byte
    ; Zero flag cleared by load move head start, never exceeds 127
    BPL CYCLE

skip_repeat:
    STA SNAKE_DIRECTION ; Lower nibble, new direction
    STY MOVE_REPEAT_COUNT ; Upper nibble, repeat count

done:
    LDX SNAKE_DIRECTION

    ; Use it to lookup the addend to the memory address to apply the direction
    CLC
    LDA SNAKE_DIRECTION_ADDENDS-2, X
    ADC SNAKE_MEM_LO
    STA SNAKE_MEM_LO
    LDA SNAKE_DIRECTION_ADDENDS-1, X
    ADC SNAKE_MEM_HI
    STA SNAKE_MEM_HI
    LDA SNAKE_DIRECTION_ADDENDS+1, X
    CLC
    ADC SNAKE_X
    STA SNAKE_X

    ; Clear LDY so that functions after this, dont need to clear LDY
    LDY #$0

    RTS

IRQ:
    ; So first copy the current to the path controller
    ; state
    LDX #(ZP_SNAKE_CTL_SIZE - 1)
s0:
    LDA SNAKE_CTL_CURRENT, X
    STA $0, X
    DEX
    BPL s0

    ; Step the snake 1 move forward, and save it, fallback
    JSR CYCLE
    JSR SAVE_BEST

    ; Save the new direction
    LDX SNAKE_DIRECTION
    LDA SNAKE_DIRECTION_ADDENDS, X
    STA STATE_SNAKE_DIRECTION

    ; Get the current tile of the new snake position
    ; If its not empty, no shortcuts, its food!
    LDA (SNAKE_MEM_LO), Y
    BNE shortcut_break

    ; Weird bugfix, dont shortcut on the X walls
    ; to prevent path finding through them
    LDA SNAKE_X + SNAKE_CTL_CURRENT
    BEQ shortcut_break
    CMP #(BOARD_WIDTH-1)
    BEQ shortcut_break

    ; Now attempt to find paths that connect
    ; But break if that path hits something, and we cant
    ; take shortcuts anymore
shortcut_loop:
    JSR CYCLE

    ; Get the current tile of the new snake position
    ; If its not empty, we cant skip farther anymore
    LDA (SNAKE_MEM_LO), Y
    BNE shortcut_break

    ; Test each direction
    ; See if we can move to it
    LDX #16
test_dir_loop:
    DEX
    DEX
    DEX
    DEX

    ; IF no connection was found, move on
    BMI shortcut_loop

    CLC
    LDA SNAKE_MEM_LO + SNAKE_CTL_CURRENT
    ADC SNAKE_DIRECTION_ADDENDS+0, X
    TAY
    LDA SNAKE_MEM_HI + SNAKE_CTL_CURRENT
    ADC SNAKE_DIRECTION_ADDENDS+1, X
    CMP SNAKE_MEM_HI
    BNE test_dir_loop
    CPY SNAKE_MEM_LO
    BNE test_dir_loop

    ; Looks like we have a connection, save it!
    LDA SNAKE_DIRECTION_ADDENDS+2, X
    STA STATE_SNAKE_DIRECTION
    JSR SAVE_BEST
    ; Keep looking
    ; JMP Replaced with BMI, SAVE_BEST always sets negative flag, saves a byte
    BMI shortcut_loop
shortcut_break:
    ; Take the best option into the new state
    LDX #(ZP_SNAKE_CTL_SIZE - 1)
s2:
    LDA SNAKE_CTL_BEST, X
    STA SNAKE_CTL_CURRENT, X
    DEX
    BPL s2

    ; Acknowledge interrupts and mark done
    LDA #$02
    STA STATE_CONTROL
    RTI

    ; Saves the current snake state to the best tracker
SAVE_BEST:
    LDX #(ZP_SNAKE_CTL_SIZE - 1)
s1:
    LDA $0, X
    STA SNAKE_CTL_BEST, X
    DEX
    BPL s1
    RTS

TAPE_SIZE = 37

; This is copied to RAM
RAM_IMAGE:
    .byte 2 ; Default move head
    .byte 1 ; Default move set start
    .byte 2 ; Default move set repeat count
    .byte 8 ; Default move repeat count
    .byte $90 ; Default board low
    .byte $40 ; Default board hight
    .byte INT_DIR_DOWN ; Default snake direction
    .byte 8 ; Default snake direction

    ; Direction addend lookup table.
    .word (-1 & $FFFF) ; Left
    .byte DIR_LEFT
    .byte -1 & $FF
    .word (1 & $FFFF) ; Right
    .byte DIR_RIGHT
    .byte 1 & $FF
    .word (-BOARD_WIDTH & $FFFF) ; Up
    .byte DIR_UP
    .byte 0
    .word (BOARD_WIDTH & $FFFF) ; Down
    .byte DIR_DOWN

    ; Beginning of movement tape
    .byte 0 ; Used to init movement tape, also part of before hand lookup table
RAM_COPY_START:
    ; Initial zig-zag pattern
    .byte (6<<4)
    .byte (INT_DIR_DOWN) | (14 << 4)
    .byte (INT_DIR_RIGHT) | (0 << 4)
    .byte (INT_DIR_UP) | (14 << 4)
    .byte (INT_DIR_RIGHT) | (0 << 4)

    ; Go off to right
    .byte (0<<4)
    .byte (INT_DIR_DOWN) | (14 << 4)
    .byte (INT_DIR_RIGHT) | (0 << 4)

    ; Looping wiggle pattern at bottom of board
    .byte (7<<4)
    .byte (INT_DIR_RIGHT) | (0 << 4)
    .byte (INT_DIR_UP) | (0 << 4)
    .byte (INT_DIR_LEFT) | (0 << 4)
    .byte (INT_DIR_UP) | (0 << 4)

    ; Go back to top
    .byte (0<<4)
    .byte (INT_DIR_LEFT) | (14 << 4)
    .byte (INT_DIR_DOWN) | (0 << 4)


    .byte (INT_DIR_RIGHT) | (0 << 4)
    .byte (INT_DIR_UP)   | (1 << 4)
    .byte (INT_DIR_LEFT) | (15 << 4)
    .byte (INT_DIR_DOWN) | (0 << 4)


; The ROM is exactly
; 255 bytes, so we have one to spare and
; Stay in the 256 byte range. Lets be silly
    .byte $69