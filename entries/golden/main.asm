; -----------------------------------------------------------------------------
; 6502SnakeBot - 6502 snake robot competition
; File: main.asm
;
; Part of the 6502SnakeBot project (https://github.com/rainbain/6502SnakeBot)
;
; Copyright (c) 2026 Samuel Fitzsimons
;
; This file is licensed under the MIT License.
; See the LICENSE file in the project root for full license terms.
;
; Golden implementation example.
; -----------------------------------------------------------------------------

BOARD                 = $4000
STATE_CONTROL         = $5000
STATE_SNAKE_DIRECTION = $5001
STATE_DEBUG           = $5002

ISR_IRQ_L = $FFFE
ISR_IRQ_H = $FFFF

BOARD_WIDTH = 17
BOARD_HEIGHT = 17

; Tile Defines
TILE_TYPE_EMPTY      = (0<<4)
TILE_TYPE_SNAKE_HEAD = (1<<4)
TILE_TYPE_SNAKE_BODY = (2<<4)
TILE_TYPE_SNAKE_TAIL = (3<<4)
TILE_TYPE_FOOD       = (4<<4)

DIR_LEFT             = (1<<0)
DIR_RIGHT            = (1<<1)
DIR_UP               = (1<<2)
DIR_DOWN             = (1<<3)

; Zero Page
ZP_TMP0 = $0
ZP_TMP1 = $1
ZP_FOOD_X = $2 ; Food position
ZP_FOOD_Y = $3
ZP_HEAD_X = $4 ; Snake head position
ZP_HEAD_Y = $5
ZP_LAST_DIRECTION = $6


; Calling Convention Used
; This example uses a specific calling convention
;
; Little Endian
; Assume callee may destroy X/Y/A
; Arguments are in the order A, X, Y, STACK
; Return Value: A, or X/Y pair
; 
; When passing a 16 bit argument, X/Y is used, over A, X

; Lets store tables low in memory for easy addressing
    JMP init

; Table containing base address of each
; row in board
BOARD_ROW_TABLE:
    .repeat BOARD_HEIGHT, I
        .word BOARD + I * BOARD_WIDTH
    .endrepeat


init:
    ; Load IRQ
    LDA #>IRQ
    STA ISR_IRQ_H
    LDA #<IRQ
    STA ISR_IRQ_L

    ; Stack Pointer
    ; We will just use the default, placed at 0x01FD

    ; Last direction, snake faces right
    ; At beginning
    LDA #DIR_RIGHT
    STA ZP_LAST_DIRECTION

    ; Enable interrupts
    CLI
LOOP:
    JMP LOOP

; Get a tile from board.
; arg 1 = Y position of tile
; arg 2 = X position of tile
; ret = tile value
GET_TILE:
    ; Calculate base row offset
    ASL ; Multiply address by 2
    TAY ; Into Y

    ; Board row address into ZP
    LDA BOARD_ROW_TABLE, Y
    STA ZP_TMP0
    INY
    LDA BOARD_ROW_TABLE, Y
    STA ZP_TMP1

    ; Load A with tile value
    TXA
    TAY
    LDA (ZP_TMP0), Y
    RTS

; Find a tile of type on the board
; arg 1 = Tile Type
; ret = X, Y position
FIND_TILE:
    LDX #(BOARD_WIDTH - 1)
    
xloop:
    LDY #(BOARD_HEIGHT - 1)

yloop:
    PHA
    TXA
    PHA
    TYA
    PHA

    TYA
    JSR GET_TILE
    
    ; Save return value, only upper nibble (tile type)
    AND #$F0
    STA ZP_TMP0

    ; Restore X, Y
    PLA
    TAY
    PLA
    TAX

    PLA         ; Restore A (expected tile type)
    CMP ZP_TMP0 ; Compare expected with actual

    ; End if this is the tile, returning the X, Y pair
    BEQ end

    ; Decrement Y
    DEY
    BPL yloop
        
    ; Decrement X
    DEX
    BPL xloop
        
end:
    RTS

IRQ:
    ; Find snake food position
    LDA #TILE_TYPE_FOOD
    JSR FIND_TILE
    STX ZP_FOOD_X
    STY ZP_FOOD_Y

    ; Find snake head position
    LDA #TILE_TYPE_SNAKE_HEAD
    JSR FIND_TILE
    STX ZP_HEAD_X
    STY ZP_HEAD_Y

    ; If head.x < food.x, turn right, otherwise left
    LDA #DIR_LEFT
    CPX ZP_FOOD_X
    BCS s1
    LDA #DIR_RIGHT
s1:
    ; If food.y == head.y, dont bother with turning up or down too
    CPY ZP_FOOD_Y
    BEQ s2

    ; If head.y < food.y, turn up, otherwise down
    LDA #DIR_UP
    CPY ZP_FOOD_Y
    BCS s2
    LDA #DIR_DOWN
s2:

    ; Current direction
    LDX ZP_LAST_DIRECTION

    ; 180 degree turn conditions
    CPX #DIR_LEFT
    BNE s3
    CMP #DIR_RIGHT
    BNE s3
    LDA #DIR_UP
s3:
    CPX #DIR_RIGHT
    BNE s4
    CMP #DIR_LEFT
    BNE s4
    LDA #DIR_DOWN
s4:
    CPX #DIR_UP
    BNE s5
    CMP #DIR_DOWN
    BNE s5
    LDA #DIR_LEFT
s5:
    CPX #DIR_DOWN
    BNE s6
    CMP #DIR_UP
    BNE s6
    LDA #DIR_RIGHT
s6:

    ; Save new direction
    STA STATE_SNAKE_DIRECTION
    STA ZP_LAST_DIRECTION

    ; Acknowledge interrupts and mark done
    LDA #$02
    STA STATE_CONTROL
    RTI