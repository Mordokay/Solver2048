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
    private static let kSolverDepth = "solverDepth"
    private static let kSpawnMain = "spawnMainPiece"

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

    // MARK: - Extension Active State

    nonisolated static func writeExtensionActive(_ active: Bool) {
        defaults.set(active, forKey: kExtensionActive)
        defaults.synchronize()
        postDarwinNotification()
    }

    nonisolated static var isExtensionActive: Bool {
        defaults.bool(forKey: kExtensionActive)
    }

    // MARK: - Settings

    nonisolated static var solverDepth: Int {
        get { max(defaults.integer(forKey: kSolverDepth), 2) }
        set { defaults.set(newValue, forKey: kSolverDepth); defaults.synchronize() }
    }

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
