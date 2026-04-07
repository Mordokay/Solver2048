import SwiftUI
import PhotosUI

/// Calibration screen: user imports a game screenshot and taps the top-left
/// and bottom-right corners of the 4x4 board to define the crop region.
struct CalibrationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var screenshotImage: UIImage?
    @State private var phase: TapPhase = .selectImage
    @State private var topLeft: CGPoint?       // normalized 0-1
    @State private var bottomRight: CGPoint?   // normalized 0-1
    @State private var saved = false
    @State private var zoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var lastPanOffset: CGSize = .zero

    enum TapPhase {
        case selectImage, tapTopLeft, tapBottomRight, done
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                instructionBanner

                if let image = screenshotImage {
                    imageWithOverlay(image)
                } else {
                    Spacer()
                    PhotosPicker(selection: $selectedPhoto, matching: .screenshots) {
                        Label("Select Game Screenshot", systemImage: "photo.on.rectangle")
                            .font(.title3)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    Text("Take a screenshot of your game first,\nthen import it here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }

                if phase == .done {
                    Button {
                        saveCalibration()
                    } label: {
                        Label(saved ? "Saved!" : "Save Calibration", systemImage: saved ? "checkmark.circle.fill" : "square.and.arrow.down")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(saved ? .green : .orange)
                    .padding(.horizontal)
                }

                if screenshotImage != nil {
                    HStack(spacing: 16) {
                        Button("Reset Points") {
                            topLeft = nil; bottomRight = nil
                            phase = .tapTopLeft; saved = false
                        }
                        .foregroundStyle(.secondary)

                        if zoomScale > 1.05 {
                            Button("Reset Zoom") {
                                withAnimation {
                                    zoomScale = 1.0
                                    panOffset = .zero
                                    lastPanOffset = .zero
                                }
                            }
                            .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .padding()
            .navigationTitle("Calibrate Board")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onChange(of: selectedPhoto) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        screenshotImage = img
                        phase = .tapTopLeft
                    }
                }
            }
        }
    }

    // MARK: - Instruction Banner

    @ViewBuilder
    private var instructionBanner: some View {
        HStack {
            Image(systemName: phaseIcon)
                .foregroundStyle(.orange)
            Text(phaseText)
                .font(.subheadline.weight(.medium))
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    private var phaseIcon: String {
        switch phase {
        case .selectImage:   return "photo"
        case .tapTopLeft:    return "arrow.up.left"
        case .tapBottomRight: return "arrow.down.right"
        case .done:          return "checkmark.circle"
        }
    }

    private var phaseText: String {
        switch phase {
        case .selectImage:   return "Import a screenshot of your game"
        case .tapTopLeft:    return "Tap the TOP-LEFT corner of the board"
        case .tapBottomRight: return "Tap the BOTTOM-RIGHT corner of the board"
        case .done:          return "Board region marked! Save when ready."
        }
    }

    // MARK: - Image with Tap Overlay

    /// Convert a normalized (0-1) point to view coordinates using the current display rect
    private func toView(_ norm: CGPoint, in displayRect: CGRect) -> CGPoint {
        CGPoint(
            x: displayRect.minX + norm.x * displayRect.width,
            y: displayRect.minY + norm.y * displayRect.height
        )
    }

    @ViewBuilder
    private func imageWithOverlay(_ image: UIImage) -> some View {
        GeometryReader { geo in
            let displayRect = imageDisplayRect(imageSize: image.size, in: geo.size)

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: geo.size.width, height: geo.size.height)
                .overlay {
                    Canvas { ctx, size in
                        let dr = imageDisplayRect(imageSize: image.size, in: size)

                        if let tl = topLeft {
                            let pt = toView(tl, in: dr)
                            let circle = CGRect(x: pt.x - 12, y: pt.y - 12, width: 24, height: 24)
                            ctx.stroke(Path(ellipseIn: circle), with: .color(.green), lineWidth: 3)
                            ctx.fill(Path(ellipseIn: circle.insetBy(dx: 8, dy: 8)), with: .color(.green))
                        }
                        if let br = bottomRight {
                            let pt = toView(br, in: dr)
                            let circle = CGRect(x: pt.x - 12, y: pt.y - 12, width: 24, height: 24)
                            ctx.stroke(Path(ellipseIn: circle), with: .color(.red), lineWidth: 3)
                            ctx.fill(Path(ellipseIn: circle.insetBy(dx: 8, dy: 8)), with: .color(.red))
                        }
                        if let tl = topLeft, let br = bottomRight {
                            let tlPt = toView(tl, in: dr)
                            let brPt = toView(br, in: dr)
                            let rect = CGRect(x: tlPt.x, y: tlPt.y,
                                              width: brPt.x - tlPt.x, height: brPt.y - tlPt.y)
                            ctx.stroke(Path(rect), with: .color(.yellow), lineWidth: 2)
                            let cellW = rect.width / 4
                            let cellH = rect.height / 4
                            for i in 1..<4 {
                                var hLine = Path()
                                hLine.move(to: CGPoint(x: rect.minX, y: rect.minY + cellH * CGFloat(i)))
                                hLine.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cellH * CGFloat(i)))
                                ctx.stroke(hLine, with: .color(.yellow.opacity(0.5)), lineWidth: 1)
                                var vLine = Path()
                                vLine.move(to: CGPoint(x: rect.minX + cellW * CGFloat(i), y: rect.minY))
                                vLine.addLine(to: CGPoint(x: rect.minX + cellW * CGFloat(i), y: rect.maxY))
                                ctx.stroke(vLine, with: .color(.yellow.opacity(0.5)), lineWidth: 1)
                            }
                        }
                    }
                    .allowsHitTesting(false)
                }
                .scaleEffect(zoomScale, anchor: .center)
                .offset(panOffset)
                .gesture(
                    MagnificationGesture()
                        .onChanged { scale in
                            zoomScale = max(1.0, min(5.0, scale))
                        }
                )
                .gesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { value in
                            guard zoomScale > 1.05 else { return }
                            panOffset = CGSize(
                                width: lastPanOffset.width + value.translation.width,
                                height: lastPanOffset.height + value.translation.height
                            )
                        }
                        .onEnded { _ in
                            lastPanOffset = panOffset
                        }
                )
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onEnded { value in
                            let dragDist = sqrt(pow(value.translation.width, 2) + pow(value.translation.height, 2))
                            guard dragDist < 8 else { return }

                            let loc = value.startLocation
                            let centerX = geo.size.width / 2
                            let centerY = geo.size.height / 2
                            let origX = (loc.x - centerX - panOffset.width) / zoomScale + centerX
                            let origY = (loc.y - centerY - panOffset.height) / zoomScale + centerY

                            print("[Calibration] tap=(\(Int(loc.x)),\(Int(loc.y))) orig=(\(Int(origX)),\(Int(origY))) zoom=\(String(format: "%.1f", zoomScale)) pan=(\(Int(panOffset.width)),\(Int(panOffset.height)))")
                            handleTap(at: CGPoint(x: origX, y: origY), displayRect: displayRect)
                        }
                )
        }
    }

    /// Compute where the image is actually displayed (accounting for scaledToFit)
    private func imageDisplayRect(imageSize: CGSize, in viewSize: CGSize) -> CGRect {
        let imgAspect = imageSize.width / imageSize.height
        let viewAspect = viewSize.width / viewSize.height

        if imgAspect > viewAspect {
            let w = viewSize.width
            let h = w / imgAspect
            return CGRect(x: 0, y: (viewSize.height - h) / 2, width: w, height: h)
        } else {
            let h = viewSize.height
            let w = h * imgAspect
            return CGRect(x: (viewSize.width - w) / 2, y: 0, width: w, height: h)
        }
    }

    private func handleTap(at point: CGPoint, displayRect: CGRect) {
        guard displayRect.contains(point) else { return }

        let normX = (point.x - displayRect.minX) / displayRect.width
        let normY = (point.y - displayRect.minY) / displayRect.height

        switch phase {
        case .tapTopLeft:
            topLeft = CGPoint(x: normX, y: normY)
            phase = .tapBottomRight
        case .tapBottomRight:
            bottomRight = CGPoint(x: normX, y: normY)
            phase = .done
            // Zoom out after a brief delay so state change settles first
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                withAnimation(.easeOut(duration: 0.4)) {
                    zoomScale = 1.0
                    panOffset = .zero
                    lastPanOffset = .zero
                }
            }
        default:
            break
        }
    }

    // MARK: - Save

    private func saveCalibration() {
        guard let tl = topLeft, let br = bottomRight else { return }
        SharedState.writeCalibration(topLeft: tl, bottomRight: br)
        // Precompute piece reference features and store in App Group
        BoardAnalyzer.precomputeAndStoreFeatures()
        saved = true

        // Auto-dismiss after a short delay
        Task {
            try? await Task.sleep(for: .seconds(0.8))
            dismiss()
        }
    }
}
