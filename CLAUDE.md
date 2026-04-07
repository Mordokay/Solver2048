# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

This is an Xcode project (no SPM/CocoaPods). Open `Solver2048/Solver2048.xcodeproj` in Xcode.

```bash
# Build from command line
xcodebuild -project Solver2048/Solver2048.xcodeproj -scheme Solver2048 -sdk iphoneos build

# Build all three targets
xcodebuild -project Solver2048/Solver2048.xcodeproj -scheme Solver2048 -sdk iphoneos build
xcodebuild -project Solver2048/Solver2048.xcodeproj -scheme SolverBroadcast -sdk iphoneos build
xcodebuild -project Solver2048/Solver2048.xcodeproj -scheme SolverWidgetExtension -sdk iphoneos build
```

There are no tests in this project.

## Architecture

Real-time iOS 2048 solver that captures the screen, recognizes game pieces, and tells the user which direction to swipe via voice, PiP overlay, or Dynamic Island.

### Three Targets

- **Solver2048** (main app) — SwiftUI app that runs the solver, plays voice commands, manages PiP and Live Activity
- **SolverBroadcast** (Broadcast Upload Extension) — Captures screen frames via ReplayKit, runs board analysis with Vision, sends detected board state to main app. Has a **50MB memory limit** — the solver intentionally runs in the main app, not here.
- **SolverWidget** (Widget Extension) — Renders the Live Activity on Dynamic Island and Lock Screen

### App ↔ Extension Communication

The broadcast extension and main app run in separate processes. They communicate through:
1. **App Group UserDefaults** (`group.com.greenSphereStudios.Solver2048`) — shared state storage (calibration, board state, piece features, settings)
2. **Darwin notifications** — immediate cross-process signaling when new data is available
3. **Polling fallback** — timer-based polling in case Darwin notifications are missed

Flow: Extension captures frame → `BoardAnalyzer` detects board → writes to `SharedState` → Darwin notification → `SpeechManager` reads board → runs `Solver` → announces direction.

### Key Components

- **`SharedState`** — Centralized read/write bridge for all cross-process data. All keys are in UserDefaults under the app group. Board state is encoded as a 32-char hex string (2 hex chars per cell).
- **`BoardAnalyzer`** — Uses Apple Vision framework (`VNGenerateImageFeaturePrintRequest`) to generate Neural Engine embeddings for each board cell, then matches against precomputed reference piece embeddings via Euclidean distance. Caches results per cell using a fast pixel hash (`quickHash`) to skip Vision calls for unchanged cells.
- **`Solver`** — Expectimax search with snake weight heuristic (4 corner rotations) plus empty cells, merge opportunities, and smoothness bonuses. Cache is capped at 300K entries to prevent OOM in extension context. Board values are tile levels (1-based), not raw powers of 2.
- **`SpeechManager`** — Main app coordinator. Receives board state, runs solver on a background thread, announces results via voice (pre-recorded MP3s), PiP floating arrow, and/or Dynamic Island Live Activity. Polling interval adapts based on voice vs turbo mode.
- **`PiPManager`** — Uses `AVPictureInPictureController` with a video call content source to display a floating arrow overlay.
- **`CalibrationView`** — User imports a screenshot, taps top-left and bottom-right corners of the board. Coordinates stored as normalized (0-1) values.

### Shared Files Across Targets

`BoardAnalyzer.swift`, `SharedState.swift`, `Solver.swift`, and `Assets.xcassets` are included in **both** the main app and SolverBroadcast targets. `SolverActivityAttributes.swift` is shared between the main app and SolverWidget. Changes to these files affect multiple targets.

### Web Version

`index.html` at the repo root is a standalone browser-based 2048 solver (the original prototype). It contains the same Expectimax algorithm the Swift `Solver` was ported from.
