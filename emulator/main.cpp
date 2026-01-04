/*
 * 6502SnakeBot - 6502 snake robot competition
 * File: main.cpp
 *
 * Part of the 6502SnakeBot project (https://github.com/rainbain/6502SnakeBot)
 *
 * Copyright (c) 2026 Samuel Fitzsimons
 *
 * This file is licensed under the MIT License.
 * See the LICENSE file in the project root for full license terms.
 *
 * Command line cli interface.
 */

#include <SDL.h>
#include <cstdio>
#include <cstring>
#include <memory>
#include <string>

#include "Game.h"
#include "GameRender.h"
#include "Emulator.h"

int main(int argc, char** argv) {
    std::string rom_file;
    int board_width = 17;
    int board_height = 17;
    int initial_seed = 69;
    int fps = 5;
    bool play_mode = false;
    uint64_t max_cycles_per_tick = 0xFFFFFFFFFFFFFFFFULL;

    for(int i = 1; i < argc; ++i) {
        if(std::strcmp(argv[i], "--rom") == 0 && i + 1 < argc) {
            rom_file = argv[++i];
        } else if(std::strcmp(argv[i], "--width") == 0 && i + 1 < argc) {
            board_width = std::atoi(argv[++i]);
        } else if(std::strcmp(argv[i], "--height") == 0 && i + 1 < argc) {
            board_height = std::atoi(argv[++i]);
        } else if(std::strcmp(argv[i], "--fps") == 0 && i + 1 < argc) {
            fps = std::atoi(argv[++i]);
        } else if(std::strcmp(argv[i], "--play") == 0) {
            play_mode = true;
        } else if(std::strcmp(argv[i], "--max-cycles") == 0 && i + 1 < argc) {
            max_cycles_per_tick = std::strtoull(argv[++i], nullptr, 0);
        } else if(std::strcmp(argv[i], "--help") == 0) {
            std::printf("Usage:\n");
            std::printf("  --rom <file>          Specify ROM binary file (required unless --play)\n");
            std::printf("  --width <num>         Board width\n");
            std::printf("  --height <num>        Board height\n");
            std::printf("  --fps <num>           Frames per second\n");
            std::printf("  --max-cycles <num>    Maximum clock cycles per iteration for emulator\n");
            std::printf("  --play                Play mode (no ROM needed)\n");
            return 0;
        } else {
            std::printf("Unknown argument: %s\n", argv[i]);
            return 1;
        }
    }

    if(!play_mode && rom_file.empty()) {
        std::fprintf(stderr, "Error: No ROM file specified.\nUse --help for usage.\n");
        return 1;
    }

    auto game = std::make_shared<Game>(board_width, board_height, initial_seed);
    GameRender renderer(game);

    Emulator emulator(game, max_cycles_per_tick);
    if(!play_mode) {
        emulator.load_rom(rom_file);
    }


    bool running = true;
    bool game_over = false;
    const int frame_delay = 1000 / fps; // ms per frame
    Direction controls = DIR_RIGHT;

    Uint32 frame_start;
    int frame_time;
    while(running) {
        frame_start = SDL_GetTicks();

        SDL_Event e;
        while (SDL_PollEvent(&e)) {
            if(e.type == SDL_QUIT) running = false;
            else if(e.type == SDL_KEYDOWN) {
                switch (e.key.keysym.sym) {
                    case SDLK_UP:    controls = DIR_UP;    break;
                    case SDLK_DOWN:  controls = DIR_DOWN;  break;
                    case SDLK_LEFT:  controls = DIR_LEFT;  break;
                    case SDLK_RIGHT: controls = DIR_RIGHT; break;
                    case SDLK_ESCAPE: running = false;     break;
                }
            }
        }

        if(!game_over) {
            if(play_mode) {
                game_over = !game->tick(controls);
            } else {
                game_over = !emulator.cycle();
            }
        }

        renderer.render(game_over);

        // --- Frame timing ---
        frame_time = SDL_GetTicks() - frame_start;
        if(frame_delay > frame_time)
            SDL_Delay(frame_delay - frame_time);
    }

    // --- End state ---
    GameState end_state = game->getState();
    if(game_over) std::printf("Game Over!\n");
    std::printf("  Score:                       %f\n", end_state.score);
    std::printf("  Total Ticks:                 %llu\n", end_state.total_ticks);
    std::printf("  Last Iteration Clock Cycles: %llu\n", end_state.iteration_clock_cycles);
    std::printf("  Total Clock Cycles:          %llu\n", end_state.total_clock_cycles);

    return 0;
}
