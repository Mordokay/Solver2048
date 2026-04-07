import SwiftUI

struct ContentView: View {
    @State private var speechManager = SpeechManager()
    @State private var showCalibration = false
    @State private var isCalibrated = SharedState.isCalibrated
    @State private var solverDepth = SharedState.solverDepth
    @State private var spawnMain = SharedState.spawnMain
    @State private var safeLevel = SharedState.safeLevel
    @State private var showHelp = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    statusCard
                    broadcastSection
                    calibrationSection
                    settingsSection
                }
                .padding()
            }
            .navigationTitle("2048 Solver")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showHelp = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.title3)
                    }
                    .tint(.orange)
                }
            }
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
            .sheet(isPresented: $showHelp) {
                HelpSheet()
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

            // Last direction (also serves as PiP source view)
            ZStack {
                // PiP source view (invisible, but needed for PiP to anchor from)
                PiPSourceView(pipManager: speechManager.pipManager)
                    .frame(width: 1, height: 1)
                    .opacity(0.01)

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

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Safety", systemImage: "shield.checkered")
                    Spacer()
                    Text(safetyLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(safetyColor)
                }
                Slider(value: $safeLevel, in: 0...1)
                    .tint(safetyColor)
                    .onChange(of: safeLevel) { _, v in SharedState.safeLevel = (v * 100).rounded() / 100 }
            }

            Toggle(isOn: $speechManager.voiceEnabled) {
                Label("Voice", systemImage: "speaker.wave.2")
            }
            .tint(.orange)

            Toggle(isOn: $speechManager.pipEnabled) {
                Label("Floating Arrow (PiP)", systemImage: "pip")
            }
            .tint(.orange)

            Toggle(isOn: $speechManager.dynamicIslandEnabled) {
                Label("Dynamic Island", systemImage: "arrow.up.arrow.down")
            }
            .tint(.orange)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var safetyLabel: String {
        switch safeLevel {
        case 0:        return "Off"
        case ..<0.3:   return "Aggressive"
        case ..<0.6:   return "Balanced"
        case ..<0.85:  return "Cautious"
        default:       return "Very Safe"
        }
    }

    private var safetyColor: Color {
        if safeLevel < 0.01 { return .red }
        return Color(
            red: 1.0 - safeLevel,
            green: 0.3 + safeLevel * 0.7,
            blue: 0.1
        )
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

}

// MARK: - Help Sheet

struct HelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    gettingStartedSection
                    outputMethodsSection
                    solverSettingsSection
                    tipsSection
                }
                .padding()
                .padding(.bottom, 20)
            }
            .navigationTitle("How It Works")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .tint(.orange)
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("2048 Solver")
                .font(.title.bold())
            Text("Real-time AI that watches your screen and tells you the best move.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    // MARK: - Getting Started

    @ViewBuilder
    private var gettingStartedSection: some View {
        helpGroup("Getting Started", icon: "play.circle.fill") {
            helpStep(number: 1, icon: "crop", title: "Calibrate",
                     detail: "Import a screenshot of your game and tap the top-left and bottom-right corners of the board.")
            helpStep(number: 2, icon: "record.circle", title: "Start Broadcast",
                     detail: "Tap the broadcast button and confirm screen recording. This captures your screen in real-time.")
            helpStep(number: 3, icon: "hand.tap", title: "Play",
                     detail: "Switch to your game. The solver analyzes each frame and recommends the best swipe direction.")
        }
    }

    // MARK: - Output Methods

    @ViewBuilder
    private var outputMethodsSection: some View {
        helpGroup("How You Receive Moves", icon: "bell.badge.fill") {
            helpRow(icon: "speaker.wave.2.fill", title: "Voice",
                    detail: "Speaks the direction out loud — UP, DOWN, LEFT, RIGHT. Works even when the screen is off.")
            helpRow(icon: "pip.fill", title: "Floating Arrow (PiP)",
                    detail: "A small floating window shows a directional arrow on top of any app. Drag it anywhere on screen.")
            helpRow(icon: "platter.filled.top.and.arrow.up.iphone", title: "Dynamic Island",
                    detail: "Shows the current direction in the Dynamic Island and on the Lock Screen as a Live Activity.")
        }
    }

    // MARK: - Solver Settings

    @ViewBuilder
    private var solverSettingsSection: some View {
        helpGroup("Settings Explained", icon: "slider.horizontal.3") {
            helpRow(icon: "brain.head.profile.fill", title: "Solver Depth",
                    detail: "How many moves ahead the AI looks. Higher depth = smarter but slower. Depth 6 is recommended for strong play.")
            helpRow(icon: "leaf.fill", title: "Main Spawn",
                    detail: "Which piece spawns 90% of the time in your game. Set this to match your game's most common new tile.")
            helpRow(icon: "shield.checkered", title: "Safety Slider",
                    detail: "Controls how conservatively the solver plays. Slide left (red) for aggressive play that risks filling the board, or right (green) for safer play that keeps more empty cells. Adjust mid-game to find your sweet spot.")
        }
    }

    // MARK: - Tips

    @ViewBuilder
    private var tipsSection: some View {
        helpGroup("Tips", icon: "lightbulb.fill") {
            helpRow(icon: "arrow.counterclockwise", title: "Recalibrate if needed",
                    detail: "If detection seems off, recalibrate. Make sure the board corners are marked precisely.")
            helpRow(icon: "bolt.fill", title: "PiP is the fastest output",
                    detail: "Voice has a small playback delay. For maximum speed, use only the floating arrow with voice turned off.")
            helpRow(icon: "exclamationmark.triangle.fill", title: "Follow every move",
                    detail: "The solver plans sequences of moves. Skipping a recommendation can break the planned path and lead to a loss.")
        }
    }

    // MARK: - Reusable Components

    @ViewBuilder
    private func helpGroup<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon)
                .font(.title3.bold())
                .foregroundStyle(.orange)
            content()
        }
    }

    @ViewBuilder
    private func helpStep(number: Int, icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(.orange)
                    .frame(width: 32, height: 32)
                Text("\(number)")
                    .font(.callout.bold())
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                Label(title, systemImage: icon)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func helpRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.orange)
                .frame(width: 32, alignment: .center)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    ContentView()
}
