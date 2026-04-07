//
//  SampleHandler.swift
//  SolverBroadcast
//
//  Created by Pixie on 07/04/2026.
//

import ReplayKit
import CoreImage

/// Broadcast Upload Extension handler.
/// Receives screen capture frames, analyzes the game board, runs the solver,
/// and writes the best direction to SharedState for the main app to speak aloud.
class SampleHandler: RPBroadcastSampleHandler {

    // MARK: - Properties

    private var pieceFeatures: [Int: [Double]] = [:]
    private var calibrationTL: CGPoint = .zero
    private var calibrationBR: CGPoint = .zero
    private var isSetUp = false

    private var lastBoardState: [[Int]] = Solver.newBoard()
    private var lastSolvedBoard: [[Int]] = Solver.newBoard()
    private var frameCount: Int = 0
    private var cooldownUntilFrame: Int = 0 // skip frames during animation cooldown

    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // MARK: - Broadcast Lifecycle

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        // Load calibration
        guard let cal = SharedState.readCalibration() else {
            let error = NSError(domain: "Solver2048", code: 1,
                                userInfo: [NSLocalizedDescriptionKey: "Not calibrated. Open the app and calibrate first."])
            finishBroadcastWithError(error)
            return
        }
        calibrationTL = cal.topLeft
        calibrationBR = cal.bottomRight

        // Load precomputed piece features
        guard let features = SharedState.readPieceFeatures(), !features.isEmpty else {
            let error = NSError(domain: "Solver2048", code: 2,
                                userInfo: [NSLocalizedDescriptionKey: "Piece references not found. Recalibrate in the app."])
            finishBroadcastWithError(error)
            return
        }
        pieceFeatures = features
        isSetUp = true

        SharedState.writeExtensionActive(true)
    }

    override func broadcastPaused() {
        // User has requested to pause the broadcast. Samples will stop being delivered.
    }

    override func broadcastResumed() {
        frameCount = 0
    }

    override func broadcastFinished() {
        SharedState.writeExtensionActive(false)
    }

    // MARK: - Frame Processing

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video, isSetUp else { return }

        // Higher depth = process fewer frames (more time per solve)
        // Depth 2-3: every 20 frames (~1.5/sec), Depth 5: every 45, Depth 7: every 90
        let depth = SharedState.solverDepth
        let skipN = depth <= 3 ? 20 : depth <= 5 ? 45 : 90

        frameCount += 1

        // Animation cooldown: after a solve, ignore frames for ~0.7s
        // to let the score popup (+8, +18) and piece movement animation finish
        guard frameCount >= cooldownUntilFrame else { return }

        guard frameCount % skipN == 0 else { return }

        autoreleasepool {
            processFrame(sampleBuffer)
        }
    }

    private func processFrame(_ sampleBuffer: CMSampleBuffer) {
        // Convert CMSampleBuffer → CGImage
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }

        // Analyze the board
        guard let board = BoardAnalyzer.analyzeBoard(
            frame: cgImage,
            topLeft: calibrationTL,
            bottomRight: calibrationBR,
            pieceFeatures: pieceFeatures
        ) else { return }

        // If board matches what we last solved, nothing to do
        guard !Solver.equal(board, lastSolvedBoard) else {
            lastBoardState = board
            return
        }

        // Board changed — but is it stable? (not mid-animation)
        // If it also differs from the PREVIOUS frame, the board is still animating. Wait.
        if !Solver.equal(board, lastBoardState) {
            lastBoardState = board
            return // Come back next eligible frame to see if it settled
        }

        // Board is the same as the previous read but different from last solve → stable & new.
        // Check there are any pieces on the board (skip empty boards)
        let hasPieces = board.contains { row in row.contains { $0 > 0 } }
        guard hasPieces else { return }

        // Run the solver
        let depth = SharedState.solverDepth
        let spawnMain = SharedState.spawnMain
        let results = Solver.findBestMove(board: board, depth: depth, spawnMain: spawnMain)

        if let best = results.first {
            SharedState.writeDirection(best.direction.rawValue)
        }

        lastSolvedBoard = board

        // Set cooldown: skip the next ~0.7 seconds of frames (21 frames at 30fps)
        // so we don't re-read during the next swipe's animation
        cooldownUntilFrame = frameCount + 21
    }
}
