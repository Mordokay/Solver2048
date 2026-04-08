#ifndef SOLVER_CORE_H
#define SOLVER_CORE_H

#include <stdint.h>

typedef uint64_t board_t;

/// Call once at app startup to precompute lookup tables.
void solver_init(void);

/// Find the best move for a board. Returns 0=up, 1=down, 2=left, 3=right, -1=no move.
/// spawn_main: which piece spawns 90% of the time (1 or 2). spawn_alt is the other.
int solver_find_best_move(board_t board, int spawn_main);

/// Score a specific move. Returns 0 if the move is invalid.
float solver_score_move(board_t board, int move, int spawn_main);

/// Execute a move on a board. move: 0=up, 1=down, 2=left, 3=right.
board_t solver_execute_move(int move, board_t board);

/// Count empty cells on a board.
int solver_count_empty(board_t board);

/// Pack a 4x4 int array into a board_t. board_arr[row][col], row-major.
board_t solver_pack_board(const int board_arr[4][4]);

/// Unpack a board_t into a 4x4 int array.
void solver_unpack_board(board_t board, int board_arr[4][4]);

/// Simulate a complete game in C. Returns max tile reached.
/// result_moves: if non-NULL, receives the total number of moves played.
int solver_simulate_game(int spawn_main, int *result_moves);

#endif
