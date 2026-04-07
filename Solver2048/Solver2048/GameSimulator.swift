import Foundation

/// Runs automated 2048 games using the C solver (adaptive depth).
enum GameSimulator {

    struct GameResult {
        let maxTile: Int
        let moves: Int
    }

    static func runAll(spawnMain: Int = 1, numGames: Int = 20) {
        print("\n" + String(repeating: "=", count: 60))
        print("[Simulator] Starting \(numGames) games (adaptive depth, spawn=\(spawnMain))")
        print(String(repeating: "=", count: 60))

        var results: [GameResult] = []

        for g in 1...numGames {
            let result = playGame(spawnMain: spawnMain)
            results.append(result)
            print("[Simulator] [\(g)/\(numGames)] → maxTile=P\(result.maxTile) moves=\(result.moves)")
        }

        // Summary
        let avgMax = results.map { Double($0.maxTile) }.reduce(0, +) / Double(results.count)
        let bestMax = results.map(\.maxTile).max() ?? 0
        let avgMoves = results.map { Double($0.moves) }.reduce(0, +) / Double(results.count)
        let reached11 = results.filter { $0.maxTile >= 11 }.count
        let reached12 = results.filter { $0.maxTile >= 12 }.count
        let reached13 = results.filter { $0.maxTile >= 13 }.count

        print("\n" + String(repeating: "=", count: 60))
        print("[Simulator] RESULTS (\(numGames) games)")
        print("  Avg max tile:  \(String(format: "%.1f", avgMax))")
        print("  Best max tile: P\(bestMax)")
        print("  Avg moves:     \(String(format: "%.0f", avgMoves))")
        print("  Reached P11:   \(reached11)/\(numGames)")
        print("  Reached P12:   \(reached12)/\(numGames)")
        print("  Reached P13:   \(reached13)/\(numGames)")
        print(String(repeating: "=", count: 60) + "\n")
    }

    private static func playGame(spawnMain: Int) -> GameResult {
        var board = Solver.newBoard()
        let spawnAlt = spawnMain == 1 ? 2 : 1

        board = spawnPiece(board, main: spawnMain, alt: spawnAlt)
        board = spawnPiece(board, main: spawnMain, alt: spawnAlt)

        var moves = 0
        var lastLog = 0

        while true {
            let results = Solver.findBestMove(board: board, spawnMain: spawnMain)
            guard let best = results.first else { break }

            board = Solver.applyMove(board, best.direction)
            board = spawnPiece(board, main: spawnMain, alt: spawnAlt)
            moves += 1

            if moves - lastLog >= 100 {
                let maxSoFar = board.flatMap { $0 }.max() ?? 0
                let empty = board.flatMap { $0 }.filter { $0 == 0 }.count
                print("  [move \(moves)] maxTile=P\(maxSoFar) empty=\(empty) dir=\(best.direction.rawValue)")
                lastLog = moves
            }
        }

        let maxTile = board.flatMap { $0 }.max() ?? 0
        return GameResult(maxTile: maxTile, moves: moves)
    }

    private static func spawnPiece(_ board: Solver.Board, main: Int, alt: Int) -> Solver.Board {
        let empty = Solver.emptyCells(board)
        guard !empty.isEmpty else { return board }

        let (r, c) = empty[Int.random(in: 0..<empty.count)]
        var b = board
        b[r][c] = Double.random(in: 0..<1) < 0.9 ? main : alt
        return b
    }
}
