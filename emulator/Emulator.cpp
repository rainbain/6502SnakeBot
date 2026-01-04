/*
 * 6502SnakeBot - 6502 snake robot competition
 * File: Emulator.cpp
 *
 * Part of the 6502SnakeBot project (https://github.com/rainbain/6502SnakeBot)
 *
 * Copyright (c) 2026 Samuel Fitzsimons
 *
 * This file is licensed under the MIT License.
 * See the LICENSE file in the project root for full license terms.
 *
 * The 6502 Emulator.
 */

#include "Emulator.h"

#include <stdexcept>
#include <iostream>
#include <fstream>
#include <cstdint>

#define TILE_TYPE_EMPTY      (0 << 4)
#define TILE_TYPE_SNAKE_HEAD (1 << 4)
#define TILE_TYPE_SNAKE_BODY (2 << 4)
#define TILE_TYPE_SNAKE_TAIL (3 << 4)
#define TILE_TYPE_FOOD       (4 << 4)

#define TILE_DIRECTIN_LEFT     (1 << 0)
#define TILE_DIRECTIN_RIGHT    (1 << 1)
#define TILE_DIRECTIN_UP       (1 << 2)
#define TILE_DIRECTIN_DOWN     (1 << 3)

#define STATE_CONTROL          0
#define STATE_SNAKE_DIRECTION  1

#define STATE_IRQ          (1<<0)
#define STATE_DONE         (1<<1)

Emulator::Emulator(std::shared_ptr<Game> game, uint64_t max_clock_cycles)
    : m_game(game)
    , core(this, BusRead, BusWrite) {
    this->max_clock_cycles = max_clock_cycles;

    // Board Memory
    uint32_t board_size = game->board_width * game->board_height;
    if(board_size > 0x1000) {
        throw std::runtime_error("Board memory size exceeds 0x1000.");
    }

    // Configure memory
    RAM.resize(0x4000, 0);
    BOARD.resize(board_size, 0);
    STATE.resize(3, 0);
    ISR.resize(0x10, 0);

    // Default ISR
    ISR[0xB] = 0x80; ISR[0xA] = 0x00;
    ISR[0xD] = 0x80; ISR[0xC] = 0x00;
    ISR[0xF] = 0x80; ISR[0xE] = 0x00;

    // Setup CPU
    core.Reset();
}

void Emulator::load_rom(const std::string& path) {
    constexpr size_t MAX_SIZE = 32752;

    std::ifstream file(path, std::ios::binary | std::ios::ate);
    if (!file) {
        throw std::runtime_error("Failed to open file: " + path);
    }

    // Get the file size
    std::streamsize fileSize = file.tellg();
    if (fileSize > static_cast<std::streamsize>(MAX_SIZE)) {
        throw std::runtime_error("File too large. Max size is 32,752 bytes");
    }

    file.seekg(0, std::ios::beg);

    ROM.resize(fileSize);
    if (!file.read(reinterpret_cast<char*>(ROM.data()), fileSize)) {
        throw std::runtime_error("Failed to read file: " + path);
    }
}

bool Emulator::cycle() {
    GameState state = m_game->getState();

    // First Setup a new state
    setup_state(state);

    // Not ready, IRQ for the cpu to process.
    STATE[STATE_CONTROL] = STATE_IRQ;

    state.iteration_clock_cycles = 0;
    while(state.iteration_clock_cycles < max_clock_cycles) {
        core.Run(1, state.iteration_clock_cycles, mos6502::CYCLE_COUNT);

        core.IRQ(!(STATE[STATE_CONTROL] & STATE_IRQ));

        // If Done flag is set, then its done
        if(STATE[STATE_CONTROL] & STATE_DONE) {
            break;
        }
    }

    state.total_clock_cycles += state.iteration_clock_cycles;

    m_game->setState(state);

    // Decode direction
    uint8_t dir = STATE[STATE_SNAKE_DIRECTION];
    Direction new_dir = DIR_RIGHT;
    if(dir & TILE_DIRECTIN_LEFT) {
        new_dir = DIR_LEFT;
    } else if(dir & TILE_DIRECTIN_UP) {
        new_dir = DIR_UP;
    } else if(dir & TILE_DIRECTIN_DOWN) {
        new_dir = DIR_DOWN;
    }

    return m_game->tick(new_dir);
}

void Emulator::setup_state(const GameState& state) {
    // Clear out the board
    for(size_t i = 0; i < BOARD.size(); i++) {
        BOARD[i] = 0;
    }

    // Place the food
    int index = state.food.x + state.food.y * m_game->board_width;
    BOARD[index] = TILE_TYPE_FOOD;

    // Place snake tile types
    size_t end = state.snake.size() - 1;
    index = state.snake[0].x + state.snake[0].y * m_game->board_width;
    BOARD[index] = TILE_TYPE_SNAKE_HEAD;
    index = state.snake[end].x + state.snake[end].y * m_game->board_width;
    BOARD[index] = TILE_TYPE_SNAKE_TAIL;
    for(size_t i = 1; i < state.snake.size() - 1; i++) {
        index = state.snake[i].x + state.snake[i].y * m_game->board_width;
        BOARD[index] = TILE_TYPE_SNAKE_BODY;
    }

    // Place snake tile directions
    uint8_t head_dir;
    switch(state.snakeDirection) {
        case DIR_UP:
            head_dir = TILE_DIRECTIN_UP;
            break;
        case DIR_DOWN:
            head_dir = TILE_DIRECTIN_DOWN;
            break;
        case DIR_LEFT:
            head_dir = TILE_DIRECTIN_LEFT;
            break;
        case DIR_RIGHT:
            head_dir = TILE_DIRECTIN_RIGHT;
            break;
        default:
            head_dir = 0;
            break;
    }
    index = state.snake[0].x + state.snake[0].y * m_game->board_width;
    BOARD[index] |= head_dir;

    for(size_t i = 1; i < state.snake.size(); i++) {
        index = state.snake[i].x + state.snake[i].y * m_game->board_width;
        int dx = state.snake[i].x - state.snake[i-1].x;
        int dy = state.snake[i].y - state.snake[i-1].y;

        if(dx < 0) {
            BOARD[index] |= TILE_DIRECTIN_RIGHT;
        }
        if(dx > 0) {
            BOARD[index] |= TILE_DIRECTIN_LEFT;
        }
        if(dy < 0) {
            BOARD[index] |= TILE_DIRECTIN_DOWN;
        }
        if(dy > 0) {
            BOARD[index] |= TILE_DIRECTIN_UP;
        }
    }

    // Place State
    STATE[STATE_CONTROL] = 0;
}

void Emulator::BusWrite(void* user, uint16_t addr, uint8_t value) {
    Emulator* th = (Emulator*)user;

    if(addr < th->RAM.size() + 0x0000) {
        th->RAM[addr - 0x0000] = value;
    } else if(addr >= 0x5000 && addr < th->STATE.size() + 0x5000) {
        th->STATE[addr - 0x5000] = value;
        if(addr == 0x5002) {
            // Debug Print
            std::printf("DBG: %02X\n", value);
        }
    } else if(addr >= 0xFFF0 && addr < th->ISR.size() + 0xFFF0) {
        th->ISR[addr - 0xFFF0] = value;
    } else {
        std::printf("Out of bounds memory write to %04X:%02X!\n", addr, value);
    }
}

uint8_t Emulator::BusRead(void* user, uint16_t addr) {
    Emulator* th = (Emulator*)user;
    if(addr < th->RAM.size() + 0x0000) {
        return th->RAM[addr - 0x0000];
    }
    if(addr >= 0x4000 && addr < th->BOARD.size() + 0x4000) {
        return th->BOARD[addr - 0x4000];
    }
    if(addr >= 0x5000 && addr < th->STATE.size() + 0x5000) {
        return th->STATE[addr - 0x5000];
    }
    if(addr >= 0x8000 && addr < th->ROM.size() + 0x8000) {
        return th->ROM[addr - 0x8000];
    }
    if(addr >= 0xFFF0 && addr < th->ISR.size() + 0xFFF0) {
        return th->ISR[addr - 0xFFF0];
    }

    std::printf("Out of bounds memory read to %04X!\n", addr);
    return 0;
}