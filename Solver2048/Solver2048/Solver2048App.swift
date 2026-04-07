import SwiftUI
import AVFoundation

@main
struct Solver2048App: App {

    init() {
        // Set up audio session early so background playback works
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers, .duckOthers])
            try session.setActive(true)
        } catch {
            print("[Solver2048] Audio session setup error: \(error)")
        }

        // Initialize solver depth default if not set
        if SharedState.defaults.integer(forKey: "solverDepth") == 0 {
            SharedState.solverDepth = 3
        }

        // Always regenerate piece features on launch (handles code changes & new assets)
        BoardAnalyzer.precomputeAndStoreFeatures()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
