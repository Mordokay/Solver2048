import CoreGraphics
import UIKit

/// Analyzes screen capture frames to extract the 4x4 board state.
/// Uses direct RGB pixel comparison — fast and accurate since reference images
/// are extracted from the actual game board (matching backgrounds).
enum BoardAnalyzer {
    static let N = 4
    static let refSize = 48 // resize to 48x48 for comparison

    typealias FeatureVector = [Double]

    /// Enable verbose logging (set to false after debugging)
    static var debugLogging = true

    // MARK: - Feature Computation (direct RGB average per 4x4 sub-region)

    nonisolated static func computeFeatures(from image: CGImage) -> FeatureVector? {
        let size = refSize
        let subGrid = 6 // 6x6 = 108 RGB features — enough to distinguish yellow from red
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
        features.reserveCapacity(subGrid * subGrid * 3)

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

    // MARK: - Precompute Piece References

    /// Level 0 = empty cell
    nonisolated static func precomputeAndStoreFeatures(bundle: Bundle = .main) {
        var features: [Int: [Double]] = [:]

        // Load empty cell reference (stored as level 0)
        if let uiImage = UIImage(named: "piece_empty", in: bundle, with: nil),
           let cgImage = uiImage.cgImage,
           let feat = computeFeatures(from: cgImage) {
            features[0] = feat
            NSLog("[BoardAnalyzer] piece_empty loaded (%d features)", feat.count)
        }

        for i in 1...20 {
            guard let uiImage = UIImage(named: "piece_\(i)", in: bundle, with: nil),
                  let cgImage = uiImage.cgImage,
                  let feat = computeFeatures(from: cgImage) else { continue }
            features[i] = feat
            NSLog("[BoardAnalyzer] piece_%d loaded (%d features)", i, feat.count)
        }
        SharedState.writePieceFeatures(features)
        NSLog("[BoardAnalyzer] Stored %d piece references (including empty)", features.count)
    }

    // MARK: - Empty Cell Detection

    /// Detect empty cells by checking overall brightness and saturation.
    /// Empty cells are dark brown (~#4d3b30).
    private nonisolated static func isCellEmpty(from image: CGImage) -> Bool {
        let size = 8 // small sample is enough
        guard let context = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return true }

        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        guard let data = context.data else { return true }
        let pixels = data.bindMemory(to: UInt8.self, capacity: size * size * 4)

        var totalR = 0.0, totalG = 0.0, totalB = 0.0
        let count = Double(size * size)
        for i in 0..<(size * size) {
            let off = i * 4
            totalR += Double(pixels[off])
            totalG += Double(pixels[off + 1])
            totalB += Double(pixels[off + 2])
        }
        let avgR = totalR / count
        let avgG = totalG / count
        let avgB = totalB / count

        let brightness = (avgR + avgG + avgB) / 3.0
        let maxC = max(avgR, avgG, avgB)
        let minC = min(avgR, avgG, avgB)
        let saturation = maxC > 0 ? (maxC - minC) / maxC : 0

        // Empty cells are dark (brightness < 100) and low saturation
        return brightness < 100 && saturation < 0.25
    }

    // MARK: - Board Analysis

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

        var board = Array(repeating: Array(repeating: 0, count: N), count: N)

        for r in 0..<N {
            for c in 0..<N {
                // Crop center 50% of cell to avoid grid borders
                let inset = 0.25
                let cx = CGFloat(c) * cellW + cellW * inset
                let cy = CGFloat(r) * cellH + cellH * inset
                let cw = cellW * (1 - 2 * inset)
                let ch = cellH * (1 - 2 * inset)

                let cellRect = CGRect(x: cx, y: cy, width: cw, height: ch)
                guard let cellImage = boardImage.cropping(to: cellRect) else { continue }

                board[r][c] = matchCell(cellImage, references: pieceFeatures, row: r, col: c)
            }
        }

        return board
    }

    // MARK: - Cell Matching

    private nonisolated static func matchCell(
        _ cellImage: CGImage,
        references: [Int: FeatureVector],
        row: Int = -1, col: Int = -1
    ) -> Int {
        guard let cellFeatures = computeFeatures(from: cellImage) else {
            if debugLogging { NSLog("[Match] (%d,%d) FAILED to compute features", row, col) }
            return 0
        }

        var bestMatch = 0
        var bestDist = Double.infinity
        var allDists: [(Int, Double)] = []

        for (level, refFeatures) in references {
            let dist = euclideanDistance(cellFeatures, refFeatures)
            allDists.append((level, dist))
            if dist < bestDist {
                bestDist = dist
                bestMatch = level
            }
        }

        if debugLogging {
            let sorted = allDists.sorted { $0.1 < $1.1 }.prefix(3)
                .map { "\($0.0 == 0 ? "empty" : "P\($0.0)")=\(String(format: "%.1f", $0.1))" }
                .joined(separator: " ")
            let label = bestMatch == 0 ? "EMPTY" : "→ P\(bestMatch)"
            NSLog("[Match] (%d,%d) top: %@ | %@", row, col, sorted, label)
        }

        // bestMatch 0 = empty cell reference was closest
        return bestMatch
    }

    /// Root mean square distance between two feature vectors.
    private nonisolated static func euclideanDistance(_ a: FeatureVector, _ b: FeatureVector) -> Double {
        var sum = 0.0
        let n = min(a.count, b.count)
        for i in 0..<n {
            let d = a[i] - b[i]
            sum += d * d
        }
        return sqrt(sum / Double(n))
    }
}
