import SwiftUI

struct ContentView: View {
    @State private var speechManager = SpeechManager()
    @State private var showCalibration = false
    @State private var isCalibrated = SharedState.isCalibrated
    @State private var solverDepth = SharedState.solverDepth
    @State private var spawnMain = SharedState.spawnMain

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    statusCard
                    broadcastSection
                    calibrationSection
                    settingsSection
                    helpSection
                }
                .padding()
            }
            .navigationTitle("2048 Solver")
            .onAppear {
                speechManager.startListening()
                isCalibrated = SharedState.isCalibrated
            }
            .onDisappear {
                speechManager.stopListening()
            }
            .sheet(isPresented: $showCalibration) {
                CalibrationView()
            }
            .onChange(of: showCalibration) { _, showing in
                if !showing { isCalibrated = SharedState.isCalibrated }
            }
        }
    }

    // MARK: - Status Card

    @ViewBuilder
    private var statusCard: some View {
        VStack(spacing: 12) {
            // Active indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(speechManager.isExtensionActive ? .green : .gray)
                    .frame(width: 12, height: 12)
                Text(speechManager.isExtensionActive ? "ACTIVE - Analyzing game" : "Inactive")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(speechManager.isExtensionActive ? .green : .secondary)
                Spacer()
            }

            // Last direction
            if !speechManager.lastSpokenDirection.isEmpty {
                Text(speechManager.lastSpokenDirection)
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            } else {
                Text("---")
                    .font(.system(size: 48, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Broadcast Section

    @ViewBuilder
    private var broadcastSection: some View {
        VStack(spacing: 12) {
            Text("Screen Capture")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 16) {
                // Broadcast picker - the system view IS the button
                BroadcastPickerView()
                    .frame(width: 70, height: 70)
                    .background(.orange, in: RoundedRectangle(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Tap the circle to start broadcast")
                        .font(.subheadline.weight(.medium))
                    Text("Captures your screen to analyze the game board in real-time.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !isCalibrated {
                Label("Calibrate first before starting", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Calibration Section

    @ViewBuilder
    private var calibrationSection: some View {
        VStack(spacing: 12) {
            Text("Board Calibration")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Label(
                        isCalibrated ? "Calibrated" : "Not calibrated",
                        systemImage: isCalibrated ? "checkmark.circle.fill" : "xmark.circle"
                    )
                    .foregroundStyle(isCalibrated ? .green : .red)
                    .font(.subheadline.weight(.medium))

                    Text("Import a screenshot and mark the board corners.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showCalibration = true
                } label: {
                    Label("Calibrate", systemImage: "crop")
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Settings

    @ViewBuilder
    private var settingsSection: some View {
        VStack(spacing: 16) {
            Text("Settings")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                Text("Solver Depth: \(solverDepth)")
                Picker("Depth", selection: $solverDepth) {
                    Text("2").tag(2)
                    Text("3").tag(3)
                    Text("4").tag(4)
                    Text("5").tag(5)
                    Text("6").tag(6)
                    Text("7").tag(7)
                }
                .pickerStyle(.segmented)

                Text(depthDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .onChange(of: solverDepth) { _, v in SharedState.solverDepth = v }

            HStack {
                Text("Main Spawn")
                Spacer()
                Picker("Spawn", selection: $spawnMain) {
                    Text("Piece 1").tag(1)
                    Text("Piece 2").tag(2)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }
            .onChange(of: spawnMain) { _, v in SharedState.spawnMain = v }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Help

    @ViewBuilder
    private var helpSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How to use")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                step(1, "Tap **Calibrate** and import a game screenshot")
                step(2, "Mark the top-left and bottom-right corners of the board")
                step(3, "Tap the **broadcast button** and confirm screen recording")
                step(4, "Switch to your game and play")
                step(5, "Listen for voice commands: UP, DOWN, LEFT, RIGHT")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var depthDescription: String {
        switch solverDepth {
        case 2: return "Fast (~10ms) - quick reactions, basic strategy"
        case 3: return "Balanced (~30ms) - good for most games"
        case 4: return "Smart (~100ms) - stronger lookahead"
        case 5: return "Very smart (~300ms) - deep analysis, updates ~1/sec"
        case 6: return "Genius (~1-2s) - near-optimal play, updates every ~2s"
        case 7: return "Super genius (~3-5s) - maximum strength, updates every ~3s"
        default: return ""
        }
    }

    @ViewBuilder
    private func step(_ num: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(num).")
                .fontWeight(.bold)
                .frame(width: 16, alignment: .trailing)
            Text(text)
        }
    }
}

#Preview {
    ContentView()
}
