/**
 * 2048 AI solver — adapted from nneonneo/2048-ai.
 * Original: https://github.com/nneonneo/2048-ai
 *
 * Pure C port for iOS with configurable spawn pieces.
 * Uses bitboard representation, precomputed lookup tables,
 * expectimax search with adaptive depth and transposition table.
 */

#include "solver_core.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ── Board constants ── */

#define ROW_MASK 0xFFFFULL
#define COL_MASK 0x000F000F000F000FULL

#define MAX(a, b) ((a) > (b) ? (a) : (b))
#define MIN(a, b) ((a) < (b) ? (a) : (b))

/* ── Precomputed tables ── */

static uint16_t row_left_table[65536];
static uint16_t row_right_table[65536];
static board_t  col_up_table[65536];
static board_t  col_down_table[65536];
static float    heur_score_table[65536];

/* ── Heuristic weights (CMA-ES optimized) ── */

static const float SCORE_LOST_PENALTY        = 200000.0f;
static const float SCORE_MONOTONICITY_POWER  = 4.0f;
static const float SCORE_MONOTONICITY_WEIGHT = 47.0f;
static const float SCORE_SUM_POWER           = 3.5f;
static const float SCORE_SUM_WEIGHT          = 11.0f;
static const float SCORE_MERGES_WEIGHT       = 700.0f;
static const float SCORE_EMPTY_WEIGHT        = 270.0f;

/* ── Board operations ── */

static inline board_t transpose(board_t x) {
    board_t a1 = x & 0xF0F00F0FF0F00F0FULL;
    board_t a2 = x & 0x0000F0F00000F0F0ULL;
    board_t a3 = x & 0x0F0F00000F0F0000ULL;
    board_t a = a1 | (a2 << 12) | (a3 >> 12);
    board_t b1 = a & 0xFF00FF0000FF00FFULL;
    board_t b2 = a & 0x00FF00FF00000000ULL;
    board_t b3 = a & 0x00000000FF00FF00ULL;
    return b1 | (b2 >> 24) | (b3 << 24);
}

int solver_count_empty(board_t x) {
    if (x == 0) return 16;
    x |= (x >> 2) & 0x3333333333333333ULL;
    x |= (x >> 1);
    x = ~x & 0x1111111111111111ULL;
    x += x >> 32;
    x += x >> 16;
    x += x >>  8;
    x += x >>  4;
    return x & 0xf;
}

static inline board_t unpack_col(uint16_t row) {
    board_t tmp = row;
    return (tmp | (tmp << 12ULL) | (tmp << 24ULL) | (tmp << 36ULL)) & COL_MASK;
}

static inline uint16_t reverse_row(uint16_t row) {
    return (row >> 12) | ((row >> 4) & 0x00F0) | ((row << 4) & 0x0F00) | (row << 12);
}

static int count_distinct_tiles(board_t board) {
    uint16_t bitset = 0;
    while (board) {
        bitset |= 1 << (board & 0xf);
        board >>= 4;
    }
    bitset >>= 1; /* don't count empty */
    int count = 0;
    while (bitset) {
        bitset &= bitset - 1;
        count++;
    }
    return count;
}

/* ── Table initialization ── */

void solver_init(void) {
    for (unsigned row = 0; row < 65536; ++row) {
        unsigned line[4] = {
            (row >>  0) & 0xf,
            (row >>  4) & 0xf,
            (row >>  8) & 0xf,
            (row >> 12) & 0xf
        };

        /* Heuristic score */
        float sum = 0;
        int empty = 0;
        int merges = 0;
        int prev = 0;
        int counter = 0;

        for (int i = 0; i < 4; ++i) {
            int rank = line[i];
            sum += powf(rank, SCORE_SUM_POWER);
            if (rank == 0) {
                empty++;
            } else {
                if (prev == rank) {
                    counter++;
                } else if (counter > 0) {
                    merges += 1 + counter;
                    counter = 0;
                }
                prev = rank;
            }
        }
        if (counter > 0) {
            merges += 1 + counter;
        }

        float monotonicity_left = 0;
        float monotonicity_right = 0;
        for (int i = 1; i < 4; ++i) {
            if (line[i-1] > line[i]) {
                monotonicity_left  += powf(line[i-1], SCORE_MONOTONICITY_POWER)
                                    - powf(line[i],   SCORE_MONOTONICITY_POWER);
            } else {
                monotonicity_right += powf(line[i],   SCORE_MONOTONICITY_POWER)
                                    - powf(line[i-1], SCORE_MONOTONICITY_POWER);
            }
        }

        heur_score_table[row] = SCORE_LOST_PENALTY
            + SCORE_EMPTY_WEIGHT * empty
            + SCORE_MERGES_WEIGHT * merges
            - SCORE_MONOTONICITY_WEIGHT * MIN(monotonicity_left, monotonicity_right)
            - SCORE_SUM_WEIGHT * sum;

        /* Execute a move to the left */
        for (int i = 0; i < 3; ++i) {
            int j;
            for (j = i + 1; j < 4; ++j) {
                if (line[j] != 0) break;
            }
            if (j == 4) break;

            if (line[i] == 0) {
                line[i] = line[j];
                line[j] = 0;
                i--;
            } else if (line[i] == line[j]) {
                if (line[i] != 0xf) {
                    line[i]++;
                }
                line[j] = 0;
            }
        }

        uint16_t result = (line[0] << 0) | (line[1] << 4) | (line[2] << 8) | (line[3] << 12);
        uint16_t rev_result = reverse_row(result);
        unsigned rev_row = reverse_row(row);

        row_left_table [    row] =                 row  ^                result;
        row_right_table[rev_row] =             rev_row  ^            rev_result;
        col_up_table   [    row] = unpack_col(     row) ^ unpack_col(    result);
        col_down_table [rev_row] = unpack_col( rev_row) ^ unpack_col(rev_result);
    }
}

/* ── Move execution ── */

static inline board_t execute_move_up(board_t board) {
    board_t ret = board;
    board_t t = transpose(board);
    ret ^= col_up_table[(t >>  0) & ROW_MASK] <<  0;
    ret ^= col_up_table[(t >> 16) & ROW_MASK] <<  4;
    ret ^= col_up_table[(t >> 32) & ROW_MASK] <<  8;
    ret ^= col_up_table[(t >> 48) & ROW_MASK] << 12;
    return ret;
}

static inline board_t execute_move_down(board_t board) {
    board_t ret = board;
    board_t t = transpose(board);
    ret ^= col_down_table[(t >>  0) & ROW_MASK] <<  0;
    ret ^= col_down_table[(t >> 16) & ROW_MASK] <<  4;
    ret ^= col_down_table[(t >> 32) & ROW_MASK] <<  8;
    ret ^= col_down_table[(t >> 48) & ROW_MASK] << 12;
    return ret;
}

static inline board_t execute_move_left(board_t board) {
    board_t ret = board;
    ret ^= (board_t)(row_left_table[(board >>  0) & ROW_MASK]) <<  0;
    ret ^= (board_t)(row_left_table[(board >> 16) & ROW_MASK]) << 16;
    ret ^= (board_t)(row_left_table[(board >> 32) & ROW_MASK]) << 32;
    ret ^= (board_t)(row_left_table[(board >> 48) & ROW_MASK]) << 48;
    return ret;
}

static inline board_t execute_move_right(board_t board) {
    board_t ret = board;
    ret ^= (board_t)(row_right_table[(board >>  0) & ROW_MASK]) <<  0;
    ret ^= (board_t)(row_right_table[(board >> 16) & ROW_MASK]) << 16;
    ret ^= (board_t)(row_right_table[(board >> 32) & ROW_MASK]) << 32;
    ret ^= (board_t)(row_right_table[(board >> 48) & ROW_MASK]) << 48;
    return ret;
}

board_t solver_execute_move(int move, board_t board) {
    switch (move) {
        case 0: return execute_move_up(board);
        case 1: return execute_move_down(board);
        case 2: return execute_move_left(board);
        case 3: return execute_move_right(board);
        default: return board;
    }
}

/* ── Heuristic evaluation ── */

static inline float score_heur_board(board_t board) {
    board_t t = transpose(board);
    return heur_score_table[(board >>  0) & ROW_MASK]
         + heur_score_table[(board >> 16) & ROW_MASK]
         + heur_score_table[(board >> 32) & ROW_MASK]
         + heur_score_table[(board >> 48) & ROW_MASK]
         + heur_score_table[(t >>  0) & ROW_MASK]
         + heur_score_table[(t >> 16) & ROW_MASK]
         + heur_score_table[(t >> 32) & ROW_MASK]
         + heur_score_table[(t >> 48) & ROW_MASK];
}

/* ── Transposition table (open-addressing, depth-aware) ── */

#define TRANS_TABLE_SIZE (1 << 20)  /* 1M entries, ~13MB */
#define TRANS_TABLE_MASK (TRANS_TABLE_SIZE - 1)

typedef struct {
    board_t key;
    uint8_t depth;
    float   heuristic;
} trans_entry_t;

typedef struct {
    trans_entry_t *entries;
} trans_table_t;

static void trans_table_init(trans_table_t *tt) {
    tt->entries = (trans_entry_t *)calloc(TRANS_TABLE_SIZE, sizeof(trans_entry_t));
}

static void trans_table_free(trans_table_t *tt) {
    free(tt->entries);
    tt->entries = NULL;
}

static inline uint32_t trans_hash(board_t key) {
    /* splitmix64 finalizer */
    key ^= key >> 30;
    key *= 0xbf58476d1ce4e5b9ULL;
    key ^= key >> 27;
    key *= 0x94d049bb133111ebULL;
    key ^= key >> 31;
    return (uint32_t)key & TRANS_TABLE_MASK;
}

static inline int trans_table_get(trans_table_t *tt, board_t key, int curdepth, float *out) {
    uint32_t idx = trans_hash(key);
    trans_entry_t *e = &tt->entries[idx];
    if (e->key == key && e->depth <= curdepth) {
        *out = e->heuristic;
        return 1;
    }
    return 0;
}

static inline void trans_table_set(trans_table_t *tt, board_t key, int depth, float heur) {
    uint32_t idx = trans_hash(key);
    trans_entry_t *e = &tt->entries[idx];
    /* Replace if: empty, same key, or shallower entry (deeper entries are more valuable) */
    if (e->key == 0 || e->key == key || e->depth >= depth) {
        e->key = key;
        e->depth = (uint8_t)depth;
        e->heuristic = heur;
    }
}

/* ── Expectimax search ── */

typedef struct {
    trans_table_t trans_table;
    int maxdepth;
    int curdepth;
    int depth_limit;
    int spawn_main;  /* piece that spawns 90% (1 or 2) */
    int spawn_alt;   /* piece that spawns 10% */
} eval_state_t;

static const float CPROB_THRESH_BASE = 0.0001f;

static float score_move_node(eval_state_t *state, board_t board, float cprob);

static float score_tilechoose_node(eval_state_t *state, board_t board, float cprob) {
    if (cprob < CPROB_THRESH_BASE || state->curdepth >= state->depth_limit) {
        if (state->curdepth > state->maxdepth)
            state->maxdepth = state->curdepth;
        return score_heur_board(board);
    }

    /* Check transposition table */
    float cached;
    if (trans_table_get(&state->trans_table, board, state->curdepth, &cached)) {
        return cached;
    }

    int num_open = solver_count_empty(board);
    if (num_open == 0) {
        return score_heur_board(board);
    }

    float cprob_cell = cprob / num_open;
    float res = 0.0f;

    board_t tmp = board;
    board_t tile_bit = 1;
    while (tile_bit) {
        if ((tmp & 0xf) == 0) {
            /* Try spawning main piece (90%) and alt piece (10%) */
            res += score_move_node(state, board | (tile_bit * state->spawn_main), cprob_cell * 0.9f) * 0.9f;
            res += score_move_node(state, board | (tile_bit * state->spawn_alt),  cprob_cell * 0.1f) * 0.1f;
        }
        tmp >>= 4;
        tile_bit <<= 4;
    }
    res /= num_open;

    /* Store in transposition table */
    trans_table_set(&state->trans_table, board, state->curdepth, res);

    return res;
}

static float score_move_node(eval_state_t *state, board_t board, float cprob) {
    float best = 0.0f;
    state->curdepth++;
    for (int move = 0; move < 4; ++move) {
        board_t newboard = solver_execute_move(move, board);
        if (board != newboard) {
            float score = score_tilechoose_node(state, newboard, cprob);
            if (score > best) best = score;
        }
    }
    state->curdepth--;
    return best;
}

static float score_toplevel_move(eval_state_t *state, board_t board, int move) {
    board_t newboard = solver_execute_move(move, board);
    if (board == newboard)
        return 0;
    return score_tilechoose_node(state, newboard, 1.0f) + 1e-6f;
}

/* ── Public API ── */

float solver_score_move(board_t board, int move, int spawn_main) {
    eval_state_t state;
    memset(&state, 0, sizeof(state));
    trans_table_init(&state.trans_table);

    state.depth_limit = MAX(3, count_distinct_tiles(board) - 2);
    state.spawn_main = (spawn_main >= 1 && spawn_main <= 2) ? spawn_main : 1;
    state.spawn_alt = (state.spawn_main == 1) ? 2 : 1;

    float res = score_toplevel_move(&state, board, move);

    trans_table_free(&state.trans_table);
    return res;
}

/* Persistent state for real-time play (avoids alloc/free per move) */
static eval_state_t *persistent_state = NULL;

int solver_find_best_move(board_t board, int spawn_main) {
    /* Lazy-init persistent state */
    if (!persistent_state) {
        persistent_state = (eval_state_t *)calloc(1, sizeof(eval_state_t));
        trans_table_init(&persistent_state->trans_table);
    }

    /* Clear table for new search (much faster than free+calloc) */
    memset(persistent_state->trans_table.entries, 0,
           TRANS_TABLE_SIZE * sizeof(trans_entry_t));

    persistent_state->maxdepth = 0;
    persistent_state->curdepth = 0;
    persistent_state->depth_limit = MAX(3, count_distinct_tiles(board) - 2);
    persistent_state->spawn_main = (spawn_main >= 1 && spawn_main <= 2) ? spawn_main : 1;
    persistent_state->spawn_alt = (persistent_state->spawn_main == 1) ? 2 : 1;

    float best = 0;
    int bestmove = -1;

    for (int move = 0; move < 4; move++) {
        float res = score_toplevel_move(persistent_state, board, move);
        if (res > best) {
            best = res;
            bestmove = move;
        }
    }

    return bestmove;
}

/* ── Board packing (for Swift interop) ── */

board_t solver_pack_board(const int board_arr[4][4]) {
    board_t b = 0;
    for (int r = 0; r < 4; r++) {
        for (int c = 0; c < 4; c++) {
            int val = board_arr[r][c];
            if (val > 15) val = 15;
            if (val < 0)  val = 0;
            b |= ((board_t)val) << (4 * (4 * r + c));
        }
    }
    return b;
}

void solver_unpack_board(board_t board, int board_arr[4][4]) {
    for (int r = 0; r < 4; r++) {
        for (int c = 0; c < 4; c++) {
            board_arr[r][c] = (int)((board >> (4 * (4 * r + c))) & 0xf);
        }
    }
}

/* ── Full game simulation in C (no Swift overhead) ── */

static inline board_t insert_random_tile(board_t board, int spawn_main, int spawn_alt) {
    int num_open = solver_count_empty(board);
    if (num_open == 0) return board;

    int target = arc4random_uniform(num_open);
    int tile_val = (arc4random_uniform(10) < 9) ? spawn_main : spawn_alt;

    board_t tmp = board;
    board_t tile_bit = 1;
    int idx = 0;
    while (tile_bit) {
        if ((tmp & 0xf) == 0) {
            if (idx == target) {
                return board | ((board_t)tile_val * tile_bit);
            }
            idx++;
        }
        tmp >>= 4;
        tile_bit <<= 4;
    }
    return board; /* shouldn't reach here */
}

static int get_max_rank(board_t board) {
    int maxrank = 0;
    while (board) {
        int r = (int)(board & 0xf);
        if (r > maxrank) maxrank = r;
        board >>= 4;
    }
    return maxrank;
}

int solver_simulate_game(int spawn_main, int *result_moves) {
    int sp_main = (spawn_main >= 1 && spawn_main <= 2) ? spawn_main : 1;
    int sp_alt = (sp_main == 1) ? 2 : 1;

    /* Start with empty board + 2 tiles */
    board_t board = 0;
    board = insert_random_tile(board, sp_main, sp_alt);
    board = insert_random_tile(board, sp_main, sp_alt);

    /* Allocate trans table ONCE, reuse across all moves */
    eval_state_t state;
    memset(&state, 0, sizeof(state));
    trans_table_init(&state.trans_table);
    state.spawn_main = sp_main;
    state.spawn_alt = sp_alt;

    int moves = 0;

    while (1) {
        /* Clear trans table for new search (memset is much faster than free+calloc) */
        memset(state.trans_table.entries, 0,
               TRANS_TABLE_SIZE * sizeof(trans_entry_t));
        state.maxdepth = 0;
        state.curdepth = 0;
        state.depth_limit = MAX(3, count_distinct_tiles(board) - 2);

        /* Find best move */
        float best_score = 0;
        int best_move = -1;
        for (int move = 0; move < 4; move++) {
            float res = score_toplevel_move(&state, board, move);
            if (res > best_score) {
                best_score = res;
                best_move = move;
            }
        }

        if (best_move < 0) break; /* no valid moves — game over */

        board = solver_execute_move(best_move, board);
        board = insert_random_tile(board, sp_main, sp_alt);
        moves++;

        if (moves % 100 == 0) {
            static const char *dirs[] = {"UP", "DOWN", "LEFT", "RIGHT"};
            printf("  [move %d] maxTile=P%d empty=%d dir=%s\n",
                   moves, get_max_rank(board), solver_count_empty(board),
                   dirs[best_move]);
        }
    }

    trans_table_free(&state.trans_table);

    if (result_moves) *result_moves = moves;
    return get_max_rank(board);
}
