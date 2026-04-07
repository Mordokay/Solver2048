import ActivityKit
import WidgetKit
import SwiftUI

/// Renders the Live Activity on the Dynamic Island and Lock Screen.
/// Shows a direction arrow similar to Apple Maps turn-by-turn navigation.
struct SolverLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SolverActivityAttributes.self) { context in
            // ── Lock Screen Banner ──
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // ── Expanded View (long-press Dynamic Island) ──
                DynamicIslandExpandedRegion(.center) {
                    expandedView(context: context)
                }
            } compactLeading: {
                // Left side of pill
                Image(systemName: SolverActivityAttributes.arrowIcon(for: context.state.direction))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.orange)
            } compactTrailing: {
                // Right side of pill
                Text(context.state.direction)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
            } minimal: {
                // Minimal (when another Live Activity is also active)
                Image(systemName: SolverActivityAttributes.arrowIcon(for: context.state.direction))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Lock Screen View

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<SolverActivityAttributes>) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(.orange)
                    .frame(width: 50, height: 50)
                Image(systemName: SolverActivityAttributes.arrowIcon(for: context.state.direction))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("2048 Solver")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Swipe \(context.state.direction)")
                    .font(.title3.bold())
            }

            Spacer()

            Text(SolverActivityAttributes.arrowChar(for: context.state.direction))
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(.orange)
        }
        .padding(16)
        .background(.black.opacity(0.8))
    }

    // MARK: - Expanded Dynamic Island View

    @ViewBuilder
    private func expandedView(context: ActivityViewContext<SolverActivityAttributes>) -> some View {
        VStack(spacing: 8) {
            Image(systemName: SolverActivityAttributes.arrowIcon(for: context.state.direction))
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(.orange)

            Text("Swipe \(context.state.direction)")
                .font(.headline)
                .foregroundStyle(.white)
        }
        .padding(.vertical, 4)
    }
}
