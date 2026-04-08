import Foundation

/// Runs automated 2048 games using the C solver (entire game loop in C).
enum GameSimulator {

    static func runAll(spawnMain: Int = 1, numGames: Int = 5) {
        print("\n" + String(repeating: "=", count: 60))
        print("[Simulator] Starting \(numGames) games (C solver, adaptive depth)")
        print("[Simulator] Spawn main: piece \(spawnMain)")
        print(String(repeating: "=", count: 60))

        var maxTiles: [Int] = []
        var allMoves: [Int] = []

        for g in 1...numGames {
            var moves: Int32 = 0
            let t0 = CFAbsoluteTimeGetCurrent()
            let maxTile = Int(solver_simulate_game(Int32(spawnMain), &moves))
            let elapsed = CFAbsoluteTimeGetCurrent() - t0

            maxTiles.append(maxTile)
            allMoves.append(Int(moves))
            print("[Simulator] [\(g)/\(numGames)] → P\(maxTile) in \(moves) moves (\(String(format: "%.1f", elapsed))s)")
        }

        // Summary
        let avgMax = maxTiles.map { Double($0) }.reduce(0, +) / Double(numGames)
        let bestMax = maxTiles.max() ?? 0
        let avgMoves = allMoves.map { Double($0) }.reduce(0, +) / Double(numGames)

        print("\n" + String(repeating: "=", count: 60))
        print("[Simulator] RESULTS (\(numGames) games)")
        print("  Avg max tile:  \(String(format: "%.1f", avgMax))")
        print("  Best max tile: P\(bestMax)")
        print("  Avg moves:     \(String(format: "%.0f", avgMoves))")
        for p in 11...15 {
            let count = maxTiles.filter { $0 >= p }.count
            print("  Reached P\(p):   \(count)/\(numGames)")
        }
        print(String(repeating: "=", count: 60) + "\n")
    }
}
