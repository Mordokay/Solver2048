import AVFoundation
import ActivityKit

/// Manages direction announcements via voice (MP3), Dynamic Island, and/or floating PiP arrow.
/// Receives board state from the broadcast extension and runs the solver in the main app process
/// (no memory limit → depth 7 works as fast as the browser version).
@Observable
@MainActor
final class SpeechManager {
    private var audioPlayer: AVAudioPlayer?
    private var pollingTimer: Timer?
    private var lastBoardTimestamp: Double = 0
    private var lastSolvedBoard: [[Int]] = Solver.newBoard()
    private var currentActivity: Activity<SolverActivityAttributes>?
    private var isSolving = false

    var voiceEnabled: Bool = UserDefaults.standard.object(forKey: "voiceEnabled") as? Bool ?? false {
        didSet { UserDefaults.standard.set(voiceEnabled, forKey: "voiceEnabled"); syncSettings() }
    }
    var dynamicIslandEnabled: Bool = UserDefaults.standard.object(forKey: "diEnabled") as? Bool ?? false {
        didSet { UserDefaults.standard.set(dynamicIslandEnabled, forKey: "diEnabled"); syncSettings() }
    }
    var pipEnabled: Bool = UserDefaults.standard.object(forKey: "pipEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(pipEnabled, forKey: "pipEnabled"); syncSettings() }
    }

    let pipManager = PiPManager()

    private(set) var lastSpokenDirection: String = ""
    private(set) var isListening: Bool = false
    private(set) var isExtensionActive: Bool = false

    private static let voiceFiles: [String: String] = [
        "UP": "go_up", "DOWN": "go_down", "LEFT": "go_left", "RIGHT": "go_right"
    ]

    // MARK: - Live Settings Sync (takes effect immediately, no restart needed)

    private func syncSettings() {
        SharedState.turboMode = !voiceEnabled

        // Restart polling timer with appropriate speed
        if isListening {
            pollingTimer?.invalidate()
            let interval = voiceEnabled ? 0.4 : 0.15
            pollingTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.checkForNewBoard() }
            }
        }

        // Start/stop PiP and Live Activity as needed
        if pipEnabled && isListening { pipManager.start() }
        if !pipEnabled { pipManager.stop() }
        if dynamicIslandEnabled && isListening { startLiveActivity() }
        if !dynamicIslandEnabled { endLiveActivity() }

        if voiceEnabled { setupAudioSession() }
    }

    // MARK: - Audio Session

    func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("[SpeechManager] Audio session error: \(error)")
        }
    }

    // MARK: - Announce Direction

    private func announce(_ direction: String) {
        lastSpokenDirection = direction

        if voiceEnabled { playVoice(direction) }
        if pipEnabled { pipManager.updateDirection(direction) }
        if dynamicIslandEnabled { updateLiveActivity(direction: direction) }
    }

    // MARK: - Voice Playback

    private func playVoice(_ direction: String) {
        guard let fileName = Self.voiceFiles[direction],
              let url = Bundle.main.url(forResource: fileName, withExtension: "mp3", subdirectory: "Voices")
                ?? Bundle.main.url(forResource: fileName, withExtension: "mp3")
        else { return }

        do {
            audioPlayer?.stop()
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.volume = 1.0
            audioPlayer?.play()
        } catch {
            print("[SpeechManager] Audio error: \(error)")
        }
    }

    // MARK: - Solver (runs in main app process — unlimited memory)

    private func solveAndAnnounce(_ board: [[Int]]) {
        guard !isSolving else { return }
        isSolving = true

        let depth = SharedState.solverDepth
        let spawnMain = SharedState.spawnMain

        // Log the detected board
        Self.logBoard(board)

        // Run solver on background thread so UI stays responsive
        Task.detached(priority: .userInitiated) { [weak self] in
            let t0 = CFAbsoluteTimeGetCurrent()
            let results = Solver.findBestMove(board: board, depth: depth, spawnMain: spawnMain)
            let elapsed = (CFAbsoluteTimeGetCurrent() - t0) * 1000

            // Log solver results
            let scoresStr = results.map { "\($0.direction.rawValue): \(String(format: "%.0f", $0.score))" }.joined(separator: " | ")
            print("[Solver] depth=\(depth) time=\(String(format: "%.0f", elapsed))ms results: \(scoresStr)")

            // Log which moves are actually valid
            for dir in Direction.allCases {
                let moved = Solver.applyMove(board, dir)
                let valid = !Solver.equal(board, moved)
                print("[Solver]   \(dir.rawValue) valid=\(valid)")
            }

            await MainActor.run {
                self?.isSolving = false
                if let best = results.first {
                    self?.announce(best.direction.rawValue)
                }
            }
        }
    }

    private static func logBoard(_ board: [[Int]]) {
        let pieceNames = [
            0: "  .", 1: " P1", 2: " P2", 3: " P3", 4: " P4", 5: " P5",
            6: " P6", 7: " P7", 8: " P8", 9: " P9", 10: "P10", 11: "P11", 12: "P12"
        ]
        print("[Board] Detected board state:")
        for (r, row) in board.enumerated() {
            let cells = row.map { pieceNames[$0] ?? "?\($0)" }.joined(separator: " |")
            print("[Board]   row \(r): [\(cells) ]")
        }
    }

    // MARK: - Live Activity (Dynamic Island)

    private func startLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = SolverActivityAttributes()
        let state = SolverActivityAttributes.ContentState(direction: "---")
        do {
            currentActivity = try Activity.request(
                attributes: attributes, content: .init(state: state, staleDate: nil), pushType: nil)
        } catch {
            print("[SpeechManager] Live Activity error: \(error)")
        }
    }

    private func updateLiveActivity(direction: String) {
        if currentActivity == nil || currentActivity?.activityState == .ended {
            startLiveActivity()
        }
        let state = SolverActivityAttributes.ContentState(direction: direction)
        Task { await currentActivity?.update(ActivityContent(state: state, staleDate: nil)) }
    }

    private func endLiveActivity() {
        Task {
            for activity in Activity<SolverActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            currentActivity = nil
        }
    }

    // MARK: - Listening Lifecycle

    func startListening() {
        guard !isListening else { return }
        isListening = true

        SharedState.turboMode = !voiceEnabled
        setupAudioSession()

        if dynamicIslandEnabled { startLiveActivity() }
        if pipEnabled { pipManager.start() }

        // Listen for Darwin notifications from extension
        SharedState.observeDarwinNotification { [weak self] in
            Task { @MainActor in self?.checkForNewBoard() }
        }

        // Polling fallback
        let interval = voiceEnabled ? 0.4 : 0.15
        pollingTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkForNewBoard() }
        }
    }

    func stopListening() {
        isListening = false
        pollingTimer?.invalidate()
        pollingTimer = nil
        SharedState.stopObservingDarwinNotification()
        endLiveActivity()
        pipManager.stop()
    }

    // MARK: - Board State Check (extension sends board, we solve it here)

    private func checkForNewBoard() {
        isExtensionActive = SharedState.isExtensionActive

        guard let (board, timestamp) = SharedState.readBoardState() else {
            // Uncomment to debug: print("[Main] No board state in SharedState")
            return
        }
        guard timestamp > lastBoardTimestamp else { return }
        guard !Solver.equal(board, lastSolvedBoard) else { return }

        print("[Main] New board received at \(String(format: "%.2f", timestamp))")
        lastBoardTimestamp = timestamp
        lastSolvedBoard = board
        solveAndAnnounce(board)
    }
}
