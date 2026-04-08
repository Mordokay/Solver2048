import CoreGraphics
import UIKit
import Vision

/// Analyzes screen capture frames to extract the 4x4 board state.
/// Uses Apple's Vision framework Neural Engine to generate perceptual embeddings
/// for each cell, then matches against reference piece embeddings.
/// This handles any flower design without per-piece tuning.
enum BoardAnalyzer {
    static let N = 4
    static let cellSize = 64 // downscale cells before Vision (faster inference)
    static var debugLogging = false

    // Cache: last known embedding + match per cell position
    private nonisolated(unsafe) static var cachedMatches: [[Int]] = Array(repeating: Array(repeating: -1, count: 4), count: 4)
    private nonisolated(unsafe) static var cachedPixelHashes: [[UInt64]] = Array(repeating: Array(repeating: 0, count: 4), count: 4)

    // MARK: - Vision Feature Print

    /// Generate a neural feature print for an image using Apple's Vision framework.
    /// Runs on the Neural Engine — fast, accurate, and perceptually meaningful.
    nonisolated static func featurePrint(for cgImage: CGImage) -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
            return request.results?.first as? VNFeaturePrintObservation
        } catch {
            NSLog("[BoardAnalyzer] Feature print error: %@", error.localizedDescription)
            return nil
        }
    }

    /// Compute distance between two feature prints. Lower = more similar.
    nonisolated static func distance(_ a: VNFeaturePrintObservation, _ b: VNFeaturePrintObservation) -> Float {
        var dist: Float = 0
        do {
            try a.computeDistance(&dist, to: b)
        } catch {
            return Float.greatestFiniteMagnitude
        }
        return dist
    }

    // MARK: - Precompute Piece References

    /// Directory for user-uploaded piece images (in App Group, accessible by both app and extension).
    nonisolated static var pieceImageDir: URL {
        let groupDir = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedState.appGroupID)!
        let dir = groupDir.appendingPathComponent("PieceImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Load a user-uploaded piece image from disk. Returns nil if not uploaded.
    nonisolated static func loadUserPieceImage(slot: Int) -> UIImage? {
        let url = pieceImageDir.appendingPathComponent("piece_\(slot).jpg")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// Loads piece images and computes Vision embeddings.
    /// Priority: user-uploaded images > asset catalog fallback.
    nonisolated static func precomputeAndStoreFeatures(bundle: Bundle = .main) {
        var encoded: [Int: [Double]] = [:]

        for slot in [0] + Array(1...17) {
            // Try user-uploaded image first
            var uiImage: UIImage? = loadUserPieceImage(slot: slot)
            let source: String

            if uiImage != nil {
                source = "user"
            } else {
                // Fallback to asset catalog
                let assetName = slot == 0 ? "piece_empty" : "piece_\(slot)"
                uiImage = UIImage(named: assetName, in: bundle, with: nil)
                source = "asset"
            }

            guard let image = uiImage,
                  let cgImage = image.cgImage,
                  let fp = featurePrint(for: cgImage),
                  let data = serializeFeaturePrint(fp) else { continue }
            encoded[slot] = data
            let label = slot == 0 ? "empty" : "piece_\(slot)"
            NSLog("[BoardAnalyzer] %@ loaded from %@ (%d floats)", label, source, data.count)
        }

        SharedState.writePieceFeatures(encoded)
        NSLog("[BoardAnalyzer] Stored %d piece references (Neural Engine embeddings)", encoded.count)
    }

    /// Serialize VNFeaturePrintObservation to [Double] for storage.
    nonisolated static func serializeFeaturePrint(_ fp: VNFeaturePrintObservation) -> [Double]? {
        let data = fp.data
        let count = fp.elementCount

        switch fp.elementType {
        case .float:
            let floats = data.withUnsafeBytes { ptr in
                Array(ptr.bindMemory(to: Float.self).prefix(count))
            }
            return floats.map { Double($0) }
        case .double:
            return data.withUnsafeBytes { ptr in
                Array(ptr.bindMemory(to: Double.self).prefix(count))
            }
        @unknown default:
            return nil
        }
    }

    /// Deserialize [Double] back to VNFeaturePrintObservation.
    private nonisolated static func deserializeFeaturePrint(_ doubles: [Double]) -> VNFeaturePrintObservation? {
        // Create a small dummy image and get its feature print to use as a template
        // Then overwrite the data — this is a workaround since VNFeaturePrintObservation
        // can't be directly constructed.
        // Instead, we'll compare using raw float distance.
        return nil // We'll use raw distance instead
    }

    /// Compute Euclidean distance between two serialized feature prints.
    private nonisolated static func embeddingDistance(_ a: [Double], _ b: [Double]) -> Float {
        let n = min(a.count, b.count)
        guard n > 0 else { return Float.greatestFiniteMagnitude }
        var sum = 0.0
        for i in 0..<n {
            let d = a[i] - b[i]
            sum += d * d
        }
        return Float(sqrt(sum))
    }

    // MARK: - Fast Pixel Hash (detect which cells changed without running Vision)

    /// Quick hash of an image by sampling a few pixels. Different hash = cell changed.
    nonisolated static func quickHash(of image: CGImage) -> UInt64 {
        let size = 8 // tiny 8x8 sample
        guard let ctx = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0 }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        guard let data = ctx.data else { return 0 }
        let bytes = data.bindMemory(to: UInt8.self, capacity: size * size * 4)

        // FNV-1a hash of sampled pixels
        var hash: UInt64 = 14695981039346656037
        for i in stride(from: 0, to: size * size * 4, by: 4) {
            hash ^= UInt64(bytes[i])
            hash &*= 1099511628211
            hash ^= UInt64(bytes[i + 1])
            hash &*= 1099511628211
            hash ^= UInt64(bytes[i + 2])
            hash &*= 1099511628211
        }
        return hash
    }

    /// Resize a CGImage to a target size for faster Vision processing.
    nonisolated static func resize(_ image: CGImage, to size: Int) -> CGImage? {
        guard let ctx = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        return ctx.makeImage()
    }

    /// Reset the cache (call when calibration changes).
    nonisolated static func resetCache() {
        cachedMatches = Array(repeating: Array(repeating: -1, count: 4), count: 4)
        cachedPixelHashes = Array(repeating: Array(repeating: 0, count: 4), count: 4)
    }

    // MARK: - Board Analysis

    nonisolated static func analyzeBoard(
        frame: CGImage,
        topLeft: CGPoint,
        bottomRight: CGPoint,
        pieceFeatures: [Int: [Double]]
    ) -> [[Int]]? {
        let imgW = CGFloat(frame.width)
        let imgH = CGFloat(frame.height)

        let boardX = topLeft.x * imgW
        let boardY = topLeft.y * imgH
        let boardW = (bottomRight.x - topLeft.x) * imgW
        let boardH = (bottomRight.y - topLeft.y) * imgH

        guard boardW > 0, boardH > 0 else { return nil }

        let boardRect = CGRect(x: boardX, y: boardY, width: boardW, height: boardH)
        guard let boardImage = frame.cropping(to: boardRect) else { return nil }

        let cellW = CGFloat(boardImage.width) / CGFloat(N)
        let cellH = CGFloat(boardImage.height) / CGFloat(N)

        var board = Array(repeating: Array(repeating: 0, count: N), count: N)
        var visionCalls = 0

        for r in 0..<N {
            for c in 0..<N {
                let inset = 0.08
                let cx = CGFloat(c) * cellW + cellW * inset
                let cy = CGFloat(r) * cellH + cellH * inset
                let cw = cellW * (1 - 2 * inset)
                let ch = cellH * (1 - 2 * inset)

                let cellRect = CGRect(x: cx, y: cy, width: cw, height: ch)
                guard let cellImage = boardImage.cropping(to: cellRect) else { continue }

                // Quick hash to check if this cell changed since last frame
                let hash = quickHash(of: cellImage)
                if hash == cachedPixelHashes[r][c] && cachedMatches[r][c] >= 0 {
                    // Cell unchanged — reuse cached result
                    board[r][c] = cachedMatches[r][c]
                    continue
                }

                // Cell changed — resize and run Vision
                guard let resized = resize(cellImage, to: cellSize),
                      let cellFP = featurePrint(for: resized),
                      let cellEmb = serializeFeaturePrint(cellFP) else { continue }

                let match = matchCell(cellEmb, references: pieceFeatures, row: r, col: c)
                board[r][c] = match
                cachedMatches[r][c] = match
                cachedPixelHashes[r][c] = hash
                visionCalls += 1
            }
        }

        if debugLogging {
            NSLog("[BoardAnalyzer] Vision calls: %d/16 (cached: %d)", visionCalls, 16 - visionCalls)
        }

        return board
    }

    // MARK: - Cell Matching

    private nonisolated static func matchCell(
        _ cellEmbedding: [Double],
        references: [Int: [Double]],
        row: Int = -1, col: Int = -1
    ) -> Int {
        var bestMatch = 0
        var bestDist: Float = .greatestFiniteMagnitude
        var allDists: [(Int, Float)] = []

        for (level, refEmbedding) in references {
            let dist = embeddingDistance(cellEmbedding, refEmbedding)
            allDists.append((level, dist))
            if dist < bestDist {
                bestDist = dist
                bestMatch = level
            }
        }

        if debugLogging {
            let sorted = allDists.sorted { $0.1 < $1.1 }.prefix(3)
                .map { "\($0.0 == 0 ? "empty" : "P\($0.0)")=\(String(format: "%.2f", $0.1))" }
                .joined(separator: " ")
            let label = bestMatch == 0 ? "EMPTY" : "→ P\(bestMatch)"
            NSLog("[Match] (%d,%d) top: %@ | %@", row, col, sorted, label)
        }

        return bestMatch
    }
}
