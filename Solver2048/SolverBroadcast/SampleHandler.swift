//
//  SampleHandler.swift
//  SolverBroadcast
//
//  Created by Pixie on 07/04/2026.
//

import ReplayKit
import CoreImage

/// Broadcast Upload Extension handler.
/// Captures screen frames, analyzes the board, and sends the board state to the main app.
/// The main app runs the solver (no 50MB memory limit → depth 7 works like the browser).
class SampleHandler: RPBroadcastSampleHandler {

    // MARK: - Properties

    private var pieceFeatures: [Int: [Double]] = [:]
    private var calibrationTL: CGPoint = .zero
    private var calibrationBR: CGPoint = .zero
    private var isSetUp = false

    private var lastBoardState: [[Int]] = Array(repeating: Array(repeating: 0, count: 4), count: 4)
    private var prevBoardState: [[Int]] = Array(repeating: Array(repeating: 0, count: 4), count: 4)
    private var lastSentBoard: [[Int]] = Array(repeating: Array(repeating: 0, count: 4), count: 4)
    private var frameCount: Int = 0
    private var cooldownUntilFrame: Int = 0
    private var lastFeatureReload: Int = 0

    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    private static func emptyBoard() -> [[Int]] {
        Array(repeating: Array(repeating: 0, count: 4), count: 4)
    }

    private static func boardsEqual(_ a: [[Int]], _ b: [[Int]]) -> Bool {
        for r in 0..<4 { for c in 0..<4 { if a[r][c] != b[r][c] { return false } } }
        return true
    }

    // MARK: - Speed Parameters (read live from SharedState every frame)

    private func skipInterval() -> Int {
        // Turbo: analyze as fast as possible; Normal: conservative for voice playback
        return SharedState.turboMode ? 5 : 15
    }

    private func cooldownFrames() -> Int {
        SharedState.turboMode ? 6 : 21
    }

    // MARK: - Broadcast Lifecycle

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        guard let cal = SharedState.readCalibration() else {
            finishBroadcastWithError(NSError(domain: "Solver2048", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Not calibrated. Open the app and calibrate first."]))
            return
        }
        calibrationTL = cal.topLeft
        calibrationBR = cal.bottomRight

        guard let features = SharedState.readPieceFeatures(), !features.isEmpty else {
            finishBroadcastWithError(NSError(domain: "Solver2048", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Piece references not found. Recalibrate in the app."]))
            return
        }
        pieceFeatures = features
        isSetUp = true
        SharedState.writeExtensionActive(true)
    }

    override func broadcastPaused() {}

    override func broadcastResumed() {
        frameCount = 0
        cooldownUntilFrame = 0
    }

    override func broadcastFinished() {
        SharedState.writeExtensionActive(false)
    }

    // MARK: - Frame Processing

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video, isSetUp else { return }

        frameCount += 1

        // Re-read piece features every ~5 seconds (300 frames at 60fps)
        // so newly uploaded pieces are picked up without restarting broadcast
        if frameCount - lastFeatureReload >= 300 {
            lastFeatureReload = frameCount
            if let features = SharedState.readPieceFeatures(), !features.isEmpty {
                if features.count != pieceFeatures.count {
                    pieceFeatures = features
                    BoardAnalyzer.resetCache()
                    NSLog("[SolverBroadcast] Reloaded %d piece features", features.count)
                } else {
                    pieceFeatures = features
                }
            }
        }

        guard frameCount >= cooldownUntilFrame else { return }
        guard frameCount % skipInterval() == 0 else { return }

        autoreleasepool {
            processFrame(sampleBuffer)
        }
    }

    private func processFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }

        guard let board = BoardAnalyzer.analyzeBoard(
            frame: cgImage,
            topLeft: calibrationTL,
            bottomRight: calibrationBR,
            pieceFeatures: pieceFeatures
        ) else { return }

        // Already sent this exact board
        guard !Self.boardsEqual(board, lastSentBoard) else {
            prevBoardState = lastBoardState
            lastBoardState = board
            return
        }

        // Stability check: must match TWO previous consecutive reads (3 total)
        // to filter out Vision misreads and mid-animation artifacts
        if !Self.boardsEqual(board, lastBoardState) || !Self.boardsEqual(board, prevBoardState) {
            prevBoardState = lastBoardState
            lastBoardState = board
            return
        }

        // Board is stable and new — send to main app for solving
        let hasPieces = board.contains { row in row.contains { $0 > 0 } }
        guard hasPieces else { return }

        SharedState.writeBoardState(board)
        lastSentBoard = board
        cooldownUntilFrame = frameCount + cooldownFrames()
    }
}
