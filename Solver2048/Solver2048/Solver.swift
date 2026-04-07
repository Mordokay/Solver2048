import Foundation

// MARK: - Direction

enum Direction: String, CaseIterable, Sendable {
    case up = "UP"
    case down = "DOWN"
    case left = "LEFT"
    case right = "RIGHT"
}

// MARK: - Solver (Expectimax with Snake Weight Heuristic)

/// Port of the Expectimax algorithm from index.html.
/// Uses snake weight heuristic with 4 rotations + empty/merge/smoothness bonuses.
enum Solver {
    static let N = 4
    typealias Board = [[Int]]

    // MARK: - Public API

    /// Max cache entries to prevent OOM in the broadcast extension (50MB limit).
    /// Each entry is ~120 bytes, so 300K entries ≈ 36MB.
    private static let maxCacheSize = 300_000

    /// Returns all valid moves sorted by score (best first). Empty if no valid moves.
    nonisolated static func findBestMove(
        board: Board,
        depth: Int = 3,
        spawnMain: Int = 1
    ) -> [(direction: Direction, score: Double)] {
        var cache: [UInt64: Double] = [:]
        var results: [(direction: Direction, score: Double)] = []

        for dir in Direction.allCases {
            let nb = applyMove(board, dir)
            if equal(board, nb) { continue }
            let score = expectimax(nb, depth: depth - 1, isPlayer: false,
                                   cache: &cache, prob: 1.0, spawnMain: spawnMain)
            results.append((dir, score))
        }

        results.sort { $0.score > $1.score }
        return results
    }

    // MARK: - Board Utilities

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

    // MARK: - Move Mechanics

    nonisolated static func applyMove(_ b: Board, _ dir: Direction) -> Board {
        switch dir {
        case .left:  return b.map { slideRow($0) }
        case .right: return b.map { slideRow($0.reversed()).reversed() }
        case .up:    return transpose(applyMove(transpose(b), .left))
        case .down:  return transpose(applyMove(transpose(b), .right))
        }
    }

    private nonisolated static func slideRow(_ row: [Int]) -> [Int] {
        var f = row.filter { $0 > 0 }
        var i = 0
        while i < f.count - 1 {
            if f[i] == f[i + 1] {
                f[i] += 1 // level merges up
                f.remove(at: i + 1)
            }
            i += 1
        }
        while f.count < N { f.append(0) }
        return f
    }

    private nonisolated static func transpose(_ b: Board) -> Board {
        var t = newBoard()
        for r in 0..<N {
            for c in 0..<N {
                t[c][r] = b[r][c]
            }
        }
        return t
    }

    // MARK: - Heuristic Evaluation

    // Precomputed pow(2, n) lookup — cell values are small integers (0..~20)
    private static let pow2: [Double] = (0...24).map { pow(2.0, Double($0)) }

    // Snake weight position indices (zig-zag from top-left corner)
    private static let snakeIdx: [[Int]] = [
        [15, 14, 13, 12],
        [ 8,  9, 10, 11],
        [ 7,  6,  5,  4],
        [ 0,  1,  2,  3]
    ]

    // Precomputed 4 rotations of weight matrix (4^index values)
    private static let weightMats: [[[Double]]] = {
        func rot90(_ m: [[Double]]) -> [[Double]] {
            var o = Array(repeating: Array(repeating: 0.0, count: N), count: N)
            for r in 0..<N {
                for c in 0..<N {
                    o[c][N - 1 - r] = m[r][c]
                }
            }
            return o
        }
        var base = snakeIdx.map { row in row.map { pow(4.0, Double($0)) } }
        var mats: [[[Double]]] = []
        for _ in 0..<4 {
            mats.append(base)
            base = rot90(base)
        }
        return mats
    }()

    nonisolated static func evaluate(_ b: Board) -> Double {
        // 1. Best snake weight across 4 corner orientations
        var best = -Double.infinity
        for W in weightMats {
            var s = 0.0
            for r in 0..<N {
                for c in 0..<N {
                    let v = b[r][c]
                    if v > 0 {
                        s += pow2[v] * W[r][c]
                    }
                }
            }
            best = max(best, s)
        }

        // 2. Secondary factors
        var empty = 0.0, merges = 0.0, smooth = 0.0
        for r in 0..<N {
            for c in 0..<N {
                if b[r][c] == 0 { empty += 1; continue }
                if c < N - 1 && b[r][c] == b[r][c + 1] { merges += 1 }
                if r < N - 1 && b[r][c] == b[r + 1][c] { merges += 1 }
                if c < N - 1 && b[r][c + 1] > 0 {
                    smooth -= abs(Double(b[r][c] - b[r][c + 1]))
                }
                if r < N - 1 && b[r + 1][c] > 0 {
                    smooth -= abs(Double(b[r][c] - b[r + 1][c]))
                }
            }
        }

        best += empty * 1e8
        best += merges * 5e7
        best += smooth * 1e7
        return best
    }

    // MARK: - Expectimax Search

    private nonisolated static func boardHash(_ b: Board, depth: Int, isPlayer: Bool) -> UInt64 {
        var h: UInt64 = 14695981039346656037 // FNV-1a offset basis
        for r in 0..<N {
            for c in 0..<N {
                h ^= UInt64(b[r][c])
                h &*= 1099511628211 // FNV-1a prime
            }
        }
        h ^= UInt64(depth) << 5
        h &*= 1099511628211
        h ^= isPlayer ? 1 : 0
        h &*= 1099511628211
        return h
    }

    private nonisolated static func expectimax(
        _ b: Board,
        depth: Int,
        isPlayer: Bool,
        cache: inout [UInt64: Double],
        prob: Double,
        spawnMain: Int
    ) -> Double {
        if depth <= 0 || prob < 0.0001 { return evaluate(b) }

        let key = boardHash(b, depth: depth, isPlayer: isPlayer)
        if let cached = cache[key] { return cached }

        // Stop caching if we're near the memory limit (prevents OOM in extension)
        let cacheIsFull = cache.count >= maxCacheSize

        let result: Double

        if isPlayer {
            // MAX node: pick the best move
            var bestVal = -Double.infinity
            for dir in Direction.allCases {
                let nb = applyMove(b, dir)
                if equal(b, nb) { continue }
                let val = expectimax(nb, depth: depth - 1, isPlayer: false,
                                     cache: &cache, prob: prob, spawnMain: spawnMain)
                bestVal = max(bestVal, val)
            }
            result = bestVal == -Double.infinity ? evaluate(b) : bestVal
        } else {
            // CHANCE node: average over all random tile placements
            let ec = emptyCells(b)
            if ec.isEmpty {
                result = evaluate(b)
            } else {
                let spawnAlt = spawnMain == 1 ? 2 : 1
                var total = 0.0
                let cellProb = prob / Double(ec.count)
                for (r, c) in ec {
                    for (piece, p) in [(spawnMain, 0.9), (spawnAlt, 0.1)] {
                        var nb = b
                        nb[r][c] = piece
                        total += p * expectimax(nb, depth: depth - 1, isPlayer: true,
                                                cache: &cache, prob: cellProb * p, spawnMain: spawnMain)
                    }
                }
                result = total / Double(ec.count)
            }
        }

        if !cacheIsFull {
            cache[key] = result
        }
        return result
    }
}
