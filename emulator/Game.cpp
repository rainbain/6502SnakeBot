/*
 * 6502SnakeBot - 6502 snake robot competition
 * File: Game.cpp
 *
 * Part of the 6502SnakeBot project (https://github.com/rainbain/6502SnakeBot)
 *
 * Copyright (c) 2026 Samuel Fitzsimons
 *
 * This file is licensed under the MIT License.
 * See the LICENSE file in the project root for full license terms.
 *
 * Snake Game logic.
 */

#include "Game.h"

#include <stdexcept>

Game::Game(int board_width, int board_height, unsigned int seed) : rng(seed) {
    this->board_width = board_width;
    this->board_height = board_height;

    newState();
}

void Game::newState() {
    GameState new_state;

    // Place Snake
    GameVec2 pos = (GameVec2){this->board_width / 2, this->board_height / 2};
    for(int i = 0; i < 4; i++) {
        new_state.snake.push_back(pos);
        pos.x--;
    }

    new_state.snakeDirection = DIR_RIGHT;

    // Place the first food
    spawnFood(new_state);

    state.score = 0.0;
    state.food_value = 0.0;
    state.total_ticks = 0;
    state.total_clock_cycles = 0;
    state.iteration_clock_cycles = 0;
    
    setState(new_state);
}

GameState Game::getState() {
    std::lock_guard<std::mutex> lock(state_lock);
    return this->state;
}

void Game::setState(const GameState& new_state) {
    std::lock_guard<std::mutex> lock(state_lock);
    this->state = new_state;
}

bool Game::tick(Direction player_control) {
    // New state
    GameState state = getState();

    state.total_ticks++;

    // Weird condition
    // If you try and 180 degree turn, the game
    // Will just ignore it
    if(player_control == flipDirection(state.snakeDirection)) {
        player_control = state.snakeDirection;
    } else {
        state.snakeDirection = player_control;
    }

    GameVec2 head_pos = state.snake[0];
    GameVec2 tail_pos = state.snake[state.snake.size() - 1];

    // Move every bit of body forward
    if (state.snake.size() >= 2) {
        for (size_t i = state.snake.size() - 1; i > 0; --i) {
            state.snake[i] = state.snake[i - 1];
        }
    }

    // Move head
    if(player_control == DIR_LEFT) {
        head_pos.x--;
    } else if(player_control == DIR_RIGHT) {
        head_pos.x++;
    } else if(player_control == DIR_UP) {
        head_pos.y--;
    } else {
        head_pos.y++;
    }

    // Is new head out of bounds, game over
    if(head_pos.x < 0 || head_pos.x >= board_width || head_pos.y < 0 || head_pos.y >= board_height) {
        return false;
    }

    // Is new head inside of snake, game over
    for(size_t i = 1; i < state.snake.size(); i++) {
        if(state.snake[i].x == head_pos.x && state.snake[i].y == head_pos.y) {
            return false;
        }
    }

    state.snake[0] = head_pos;

    // Is new head inside of apple? then it grows
    if(head_pos.x == state.food.x && head_pos.y == state.food.y) {
        state.snake.push_back(tail_pos);
        state.score += state.food_value;
        spawnFood(state);
    } else {
        // Food goes down in value at a rate of
        // Half for each Manhattan distance
        double w = board_width;
        double h = board_height;

        // Manhattan distance
        double mhat_dist = w + h; 
        state.food_value *= std::pow(0.5, 1.0 / mhat_dist);
    }

    setState(state);

    return true;
}

void Game::spawnFood(GameState& state) {
    // Make a list of every open tile
    std::vector<GameVec2> open_tiles;
    for(int x = 0; x < board_width; x++) {
        for(int y = 0; y < board_height; y++) {
            bool found = false;
            for(size_t i = 0; i < state.snake.size(); i++) {
                if(state.snake[i].x == x && state.snake[i].y == y) {
                    found = true;
                    break;
                }
            }

            if(!found) {
                open_tiles.push_back((GameVec2){x, y});
            }
        }
    }

    // No spots, dont spawn
    if(open_tiles.size() == 0)
        return;
    
    // Get random spot
    std::uniform_int_distribution<size_t> dist(0, open_tiles.size() - 1);

    GameVec2 pos = open_tiles[dist(rng)];
    state.food = pos;
    state.food_value = 1.0;
}

Direction Game::flipDirection(Direction d) {
    switch (d)
    {
    case DIR_DOWN:
        return DIR_UP;
    case DIR_LEFT:
        return DIR_RIGHT;
    case DIR_RIGHT:
        return DIR_LEFT;
    case DIR_UP:
        return DIR_DOWN;
    default:
        return DIR_RIGHT;
    }
}