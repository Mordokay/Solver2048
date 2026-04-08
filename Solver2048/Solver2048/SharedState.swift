import Foundation

/// Communication bridge between the main app and broadcast extension via App Group UserDefaults + Darwin notifications.
enum SharedState: Sendable {
    static let appGroupID = "group.com.greenSphereStudios.Solver2048"
    static let extensionBundleID = "com.greenSphereStudios.Solver2048.SolverBroadcast"

    // MARK: - UserDefaults Keys
    private static let kDirection = "bestDirection"
    private static let kDirectionTimestamp = "directionTimestamp"
    private static let kCalibrationTLX = "calTLX"
    private static let kCalibrationTLY = "calTLY"
    private static let kCalibrationBRX = "calBRX"
    private static let kCalibrationBRY = "calBRY"
    private static let kPieceFeatures = "pieceFeatures"
    private static let kExtensionActive = "extensionActive"
    private static let kSpawnMain = "spawnMainPiece"
    private static let kTurboMode = "turboMode"
    private static let kBoardState = "boardState"
    private static let kBoardTimestamp = "boardTimestamp"

    // Darwin notification name
    private static let darwinNotifName = CFNotificationName("com.greenSphereStudios.Solver2048.newDir" as CFString)

    // MARK: - Shared Defaults

    nonisolated static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID)!
    }

    // MARK: - Direction

    nonisolated static func writeDirection(_ direction: String) {
        defaults.set(direction, forKey: kDirection)
        defaults.set(Date().timeIntervalSince1970, forKey: kDirectionTimestamp)
        defaults.synchronize()
        postDarwinNotification()
    }

    nonisolated static func readDirection() -> (direction: String, timestamp: Double)? {
        guard let dir = defaults.string(forKey: kDirection), !dir.isEmpty else { return nil }
        let ts = defaults.double(forKey: kDirectionTimestamp)
        return (dir, ts)
    }

    // MARK: - Calibration

    nonisolated static func writeCalibration(topLeft: CGPoint, bottomRight: CGPoint) {
        defaults.set(Double(topLeft.x), forKey: kCalibrationTLX)
        defaults.set(Double(topLeft.y), forKey: kCalibrationTLY)
        defaults.set(Double(bottomRight.x), forKey: kCalibrationBRX)
        defaults.set(Double(bottomRight.y), forKey: kCalibrationBRY)
        defaults.synchronize()
    }

    nonisolated static func readCalibration() -> (topLeft: CGPoint, bottomRight: CGPoint)? {
        let tlx = defaults.double(forKey: kCalibrationTLX)
        let tly = defaults.double(forKey: kCalibrationTLY)
        let brx = defaults.double(forKey: kCalibrationBRX)
        let bry = defaults.double(forKey: kCalibrationBRY)
        guard brx > tlx && bry > tly else { return nil }
        return (CGPoint(x: tlx, y: tly), CGPoint(x: brx, y: bry))
    }

    nonisolated static var isCalibrated: Bool {
        readCalibration() != nil
    }

    // MARK: - Piece Feature Vectors (precomputed in main app, read by extension)

    nonisolated static func writePieceFeatures(_ features: [Int: [Double]]) {
        // Encode as JSON: {"1": [r,g,b,...], "2": [...], ...}
        let stringKeyed = Dictionary(uniqueKeysWithValues: features.map { ("\($0.key)", $0.value) })
        if let data = try? JSONEncoder().encode(stringKeyed) {
            defaults.set(data, forKey: kPieceFeatures)
            defaults.synchronize()
        }
    }

    nonisolated static func readPieceFeatures() -> [Int: [Double]]? {
        guard let data = defaults.data(forKey: kPieceFeatures) else { return nil }
        guard let stringKeyed = try? JSONDecoder().decode([String: [Double]].self, from: data) else { return nil }
        return Dictionary(uniqueKeysWithValues: stringKeyed.compactMap { key, val in
            guard let intKey = Int(key) else { return nil }
            return (intKey, val)
        })
    }

    // MARK: - Board State (extension writes, main app reads & solves)

    nonisolated static func writeBoardState(_ board: [[Int]]) {
        // Encode as flat hex string: "00010302..." (2 hex chars per cell, 32 chars total)
        var hex = ""
        hex.reserveCapacity(32)
        for row in board {
            for cell in row {
                hex += String(format: "%02x", cell)
            }
        }
        defaults.set(hex, forKey: kBoardState)
        defaults.set(Date().timeIntervalSince1970, forKey: kBoardTimestamp)
        defaults.synchronize()
        postDarwinNotification()
    }

    nonisolated static func readBoardState() -> (board: [[Int]], timestamp: Double)? {
        guard let hex = defaults.string(forKey: kBoardState), hex.count == 32 else { return nil }
        let ts = defaults.double(forKey: kBoardTimestamp)
        var board: [[Int]] = []
        let chars = Array(hex)
        for r in 0..<4 {
            var row: [Int] = []
            for c in 0..<4 {
                let i = (r * 4 + c) * 2
                let s = String(chars[i]) + String(chars[i + 1])
                row.append(Int(s, radix: 16) ?? 0)
            }
            board.append(row)
        }
        return (board, ts)
    }

    // MARK: - Extension Active State

    nonisolated static func writeExtensionActive(_ active: Bool) {
        defaults.set(active, forKey: kExtensionActive)
        defaults.synchronize()
        postDarwinNotification()
    }

    nonisolated static var isExtensionActive: Bool {
        defaults.bool(forKey: kExtensionActive)
    }

    // MARK: - Turbo Mode (PiP only, no voice delays)

    nonisolated static var turboMode: Bool {
        get { defaults.bool(forKey: kTurboMode) }
        set { defaults.set(newValue, forKey: kTurboMode); defaults.synchronize() }
    }

    // MARK: - Settings

    nonisolated static var spawnMain: Int {
        get {
            let v = defaults.integer(forKey: kSpawnMain)
            return v > 0 ? v : 1
        }
        set { defaults.set(newValue, forKey: kSpawnMain); defaults.synchronize() }
    }

    // MARK: - Darwin Notifications

    nonisolated static func postDarwinNotification() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            darwinNotifName, nil, nil, true
        )
    }

    /// Stored callback for Darwin notification (must be static for C callback bridge)
    nonisolated(unsafe) private static var _darwinCallback: (() -> Void)?

    nonisolated static func observeDarwinNotification(callback: @escaping @Sendable () -> Void) {
        _darwinCallback = callback
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            { _, _, _, _, _ in
                SharedState._darwinCallback?()
            },
            darwinNotifName.rawValue,
            nil,
            .deliverImmediately
        )
    }

    nonisolated static func stopObservingDarwinNotification() {
        CFNotificationCenterRemoveEveryObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil
        )
        _darwinCallback = nil
    }
}
