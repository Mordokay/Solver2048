import CoreGraphics
import UIKit

/// Analyzes screen capture frames to extract the 4x4 board state.
/// Uses 48-dimensional color feature vectors (4x4 sub-region average RGB) for piece matching.
enum BoardAnalyzer {
    static let N = 4
    static let refSize = 24 // resize cells to 24x24 for comparison
    static let subGrid = 4  // divide into 4x4 sub-regions
    static let featureDim = subGrid * subGrid * 3 // 48

    typealias FeatureVector = [Double]

    // MARK: - Feature Computation

    /// Compute the 48-dim color feature vector from a CGImage.
    /// Divides the image into a 4x4 grid and computes average RGB per sub-region.
    nonisolated static func computeFeatures(from image: CGImage) -> FeatureVector? {
        let size = refSize
        guard let context = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        guard let data = context.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: size * size * 4)

        let subSize = size / subGrid
        var features: [Double] = []
        features.reserveCapacity(featureDim)

        for sy in 0..<subGrid {
            for sx in 0..<subGrid {
                var r = 0.0, g = 0.0, b = 0.0, count = 0.0
                for y in (sy * subSize)..<((sy + 1) * subSize) {
                    for x in (sx * subSize)..<((sx + 1) * subSize) {
                        let off = (y * size + x) * 4
                        r += Double(pixels[off])
                        g += Double(pixels[off + 1])
                        b += Double(pixels[off + 2])
                        count += 1
                    }
                }
                features.append(r / count)
                features.append(g / count)
                features.append(b / count)
            }
        }
        return features
    }

    // MARK: - Precompute Piece References (run in main app, store via SharedState)

    /// Load piece images from the asset catalog and store their feature vectors in App Group defaults.
    nonisolated static func precomputeAndStoreFeatures(bundle: Bundle = .main) {
        var features: [Int: [Double]] = [:]
        for i in 1...20 {
            guard let uiImage = UIImage(named: "piece_\(i)", in: bundle, with: nil),
                  let cgImage = uiImage.cgImage,
                  let feat = computeFeatures(from: cgImage) else { continue }
            features[i] = feat
        }
        SharedState.writePieceFeatures(features)
    }

    // MARK: - Board Analysis

    /// Analyze a full-screen CGImage to extract the 4x4 board state.
    /// Returns nil if calibration data or piece features are missing.
    nonisolated static func analyzeBoard(
        frame: CGImage,
        topLeft: CGPoint,
        bottomRight: CGPoint,
        pieceFeatures: [Int: FeatureVector]
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

        var board = Solver.newBoard()

        for r in 0..<N {
            for c in 0..<N {
                // Crop center 60% of cell to avoid grid borders
                let inset = 0.2
                let cx = CGFloat(c) * cellW + cellW * inset
                let cy = CGFloat(r) * cellH + cellH * inset
                let cw = cellW * (1 - 2 * inset)
                let ch = cellH * (1 - 2 * inset)

                let cellRect = CGRect(x: cx, y: cy, width: cw, height: ch)
                guard let cellImage = boardImage.cropping(to: cellRect) else { continue }

                board[r][c] = matchCell(cellImage, references: pieceFeatures)
            }
        }

        return board
    }

    // MARK: - Cell Matching

    /// Match a single cell image against piece references. Returns 0 for empty, 1-N for piece level.
    private nonisolated static func matchCell(
        _ cellImage: CGImage,
        references: [Int: FeatureVector]
    ) -> Int {
        guard let cellFeatures = computeFeatures(from: cellImage) else { return 0 }

        // Check if cell is empty (dark, low saturation background)
        if isCellEmpty(cellFeatures) { return 0 }

        // Find closest piece match
        var bestMatch = 0
        var bestDist = Double.infinity

        for (level, refFeatures) in references {
            let dist = euclideanDistance(cellFeatures, refFeatures)
            if dist < bestDist {
                bestDist = dist
                bestMatch = level
            }
        }

        // Reject if too far from any reference
        if bestDist > 80 { return 0 }

        return bestMatch
    }

    /// Detect empty cells by checking brightness and saturation.
    /// Empty cells in the game are dark brown (~#4d3b30).
    private nonisolated static func isCellEmpty(_ features: FeatureVector) -> Bool {
        var totalR = 0.0, totalG = 0.0, totalB = 0.0
        let regions = features.count / 3
        for i in 0..<regions {
            totalR += features[i * 3]
            totalG += features[i * 3 + 1]
            totalB += features[i * 3 + 2]
        }
        let avgR = totalR / Double(regions)
        let avgG = totalG / Double(regions)
        let avgB = totalB / Double(regions)

        let brightness = (avgR + avgG + avgB) / 3.0
        let maxC = max(avgR, avgG, avgB)
        let minC = min(avgR, avgG, avgB)
        let saturation = maxC > 0 ? (maxC - minC) / maxC : 0

        return brightness < 100 && saturation < 0.25
    }

    /// Euclidean distance between two feature vectors.
    private nonisolated static func euclideanDistance(_ a: FeatureVector, _ b: FeatureVector) -> Double {
        var sum = 0.0
        for i in 0..<min(a.count, b.count) {
            let d = a[i] - b[i]
            sum += d * d
        }
        return sqrt(sum / Double(min(a.count, b.count)))
    }
}
