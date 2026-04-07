import Foundation

// MARK: - Direction

enum Direction: String, CaseIterable, Sendable {
    case up = "UP"
    case down = "DOWN"
    case left = "LEFT"
    case right = "RIGHT"

    /// Map to C solver move index: 0=up, 1=down, 2=left, 3=right
    var moveIndex: Int32 {
        switch self {
        case .up:    return 0
        case .down:  return 1
        case .left:  return 2
        case .right: return 3
        }
    }

    static func from(moveIndex: Int32) -> Direction? {
        switch moveIndex {
        case 0: return .up
        case 1: return .down
        case 2: return .left
        case 3: return .right
        default: return nil
        }
    }
}

// MARK: - Solver (thin wrapper around nneonneo C solver)

enum Solver {
    static let N = 4
    typealias Board = [[Int]]

    /// Call once at startup. Already called by Solver2048App.init().
    nonisolated static func initTables() {
        solver_init()
    }

    /// Convert [[Int]] board to C board_t. Inline packing — no C call needed.
    private nonisolated static func packBoard(_ board: Board) -> board_t {
        var b: board_t = 0
        for r in 0..<4 {
            for c in 0..<4 {
                let val = UInt64(min(max(board[r][c], 0), 15))
                b |= val << (4 * (4 * r + c))
            }
        }
        return b
    }

    /// Convert C board_t to [[Int]]. Inline unpacking — no C call needed.
    private nonisolated static func unpackBoard(_ b: board_t) -> Board {
        var board = Array(repeating: Array(repeating: 0, count: 4), count: 4)
        for r in 0..<4 {
            for c in 0..<4 {
                board[r][c] = Int((b >> (4 * (4 * r + c))) & 0xF)
            }
        }
        return board
    }

    // MARK: - Public API

    nonisolated static func findBestMove(
        board: Board,
        depth: Int = 3,
        spawnMain: Int = 1
    ) -> [(direction: Direction, score: Double)] {
        let bb = packBoard(board)
        let moveIdx = solver_find_best_move(bb, Int32(spawnMain))
        guard let dir = Direction.from(moveIndex: moveIdx) else { return [] }
        return [(dir, 1.0)]
    }

    nonisolated static func newBoard() -> Board {
        Array(repeating: Array(repeating: 0, count: N), count: N)
    }

    nonisolated static func equal(_ a: Board, _ b: Board) -> Bool {
        for r in 0..<N {
            for c in 0..<N {
                if a[r][c] != b[r][c] { return false }
            }
        }
        return true
    }

    nonisolated static func emptyCells(_ b: Board) -> [(Int, Int)] {
        var cells: [(Int, Int)] = []
        for r in 0..<N {
            for c in 0..<N {
                if b[r][c] == 0 { cells.append((r, c)) }
            }
        }
        return cells
    }

    nonisolated static func applyMove(_ board: Board, _ dir: Direction) -> Board {
        let bb = packBoard(board)
        let moved = solver_execute_move(dir.moveIndex, bb)
        return unpackBoard(moved)
    }
}
