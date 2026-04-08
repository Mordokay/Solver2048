import SwiftUI
import PhotosUI

/// Manage the 18 piece reference images (empty + P1–P17).
/// Users upload screenshots of each piece; Vision embeddings are computed and stored
/// so the BoardAnalyzer can recognize them during screen capture.
struct PieceManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pieceImages: [Int: UIImage] = [:] // 0=empty, 1..17=pieces
    @State private var selectedSlot: Int?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isProcessing = false

    private let slots = [0] + Array(1...17) // empty + P1..P17

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    instructionBanner

                    LazyVGrid(columns: [
                        GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())
                    ], spacing: 12) {
                        ForEach(slots, id: \.self) { slot in
                            pieceSlot(slot)
                        }
                    }
                    .padding(.horizontal)

                    if isProcessing {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Computing embeddings...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 8)
                    }

                    saveButton
                        .padding(.horizontal)
                        .padding(.top, 8)
                }
                .padding(.vertical)
            }
            .navigationTitle("Piece Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .tint(.orange)
                }
            }
            .onChange(of: selectedPhoto) { _, newItem in
                guard let newItem, let slot = selectedSlot else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        pieceImages[slot] = img
                        savePieceImage(img, slot: slot)
                    }
                    selectedPhoto = nil
                    selectedSlot = nil
                }
            }
            .onAppear { loadSavedImages() }
        }
        .presentationDetents([.large])
    }

    // MARK: - Instruction Banner

    @ViewBuilder
    private var instructionBanner: some View {
        VStack(spacing: 6) {
            Label("Upload piece images from your game", systemImage: "photo.on.rectangle.angled")
                .font(.subheadline.weight(.medium))
            Text("Crop each piece tightly. The AI uses these to recognize tiles on your screen. Update when the weekly drawing changes.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
    }

    // MARK: - Piece Slot

    @ViewBuilder
    private func pieceSlot(_ slot: Int) -> some View {
        let label = slot == 0 ? "Empty" : "P\(slot)"
        let hasImage = pieceImages[slot] != nil

        PhotosPicker(selection: $selectedPhoto, matching: .images) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(hasImage ? Color.clear : Color(.systemGray5))
                        .frame(height: 90)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(hasImage ? .green : .gray.opacity(0.4),
                                              lineWidth: hasImage ? 2 : 1)
                        )

                    if let img = pieceImages[slot] {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 90)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Image(systemName: "plus.circle")
                            .font(.title2)
                            .foregroundStyle(.gray)
                    }
                }

                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(hasImage ? .primary : .secondary)
            }
        }
        .simultaneousGesture(TapGesture().onEnded {
            selectedSlot = slot
        })
    }

    // MARK: - Save Button

    @ViewBuilder
    private var saveButton: some View {
        let uploadedCount = pieceImages.count
        Button {
            processAndSaveEmbeddings()
        } label: {
            HStack {
                if isProcessing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }
                Text(isProcessing ? "Processing..." : "Save & Compute Embeddings (\(uploadedCount)/18)")
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
        .disabled(isProcessing || uploadedCount == 0)
    }

    // MARK: - Image Persistence (shared via BoardAnalyzer.pieceImageDir)

    private func savePieceImage(_ image: UIImage, slot: Int) {
        guard let data = image.jpegData(compressionQuality: 0.9) else { return }
        let url = BoardAnalyzer.pieceImageDir.appendingPathComponent("piece_\(slot).jpg")
        try? data.write(to: url)
    }

    private func loadSavedImages() {
        for slot in slots {
            if let img = BoardAnalyzer.loadUserPieceImage(slot: slot) {
                pieceImages[slot] = img
            }
        }
    }

    // MARK: - Compute Embeddings

    private func processAndSaveEmbeddings() {
        isProcessing = true
        Task.detached(priority: .userInitiated) {
            var encoded: [Int: [Double]] = [:]

            for slot in [0] + Array(1...17) {
                guard let img = BoardAnalyzer.loadUserPieceImage(slot: slot),
                      let cgImage = img.cgImage,
                      let fp = BoardAnalyzer.featurePrint(for: cgImage),
                      let data = BoardAnalyzer.serializeFeaturePrint(fp) else { continue }
                encoded[slot] = data
                NSLog("[PieceManager] piece_%d embedding computed (%d floats)", slot, data.count)
            }

            SharedState.writePieceFeatures(encoded)
            BoardAnalyzer.resetCache()
            NSLog("[PieceManager] Saved %d piece embeddings", encoded.count)

            await MainActor.run {
                isProcessing = false
            }
        }
    }
}
