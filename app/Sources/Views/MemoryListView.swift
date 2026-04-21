import SwiftUI

struct MemoryListView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if appState.memories.isEmpty {
                    emptyState
                } else {
                    ForEach(appState.memories) { memory in
                        MemoryCard(memory: memory)
                            .onTapGesture {
                                appState.selectedMemory = memory
                            }
                    }
                }
            }
            .padding(12)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("No memories yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Memories will appear as you work.\nKeep recording enabled.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

struct MemoryCard: View {
    let memory: Memory

    private var timeRange: String {
        let fmt = DateFormatter()
        fmt.timeStyle = .short
        return "\(fmt.string(from: memory.startTs)) – \(fmt.string(from: memory.endTs))"
    }

    private var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: memory.endTs, relativeTo: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(memory.appName, systemImage: appIcon(for: memory.appName))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(relativeTime)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text(memory.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)

            Text(memory.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            Text(timeRange)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator, lineWidth: 0.5))
    }

    private func appIcon(for name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("code") || lower.contains("xcode") || lower.contains("cursor") {
            return "chevron.left.forwardslash.chevron.right"
        } else if lower.contains("terminal") || lower.contains("iterm") || lower.contains("warp") || lower.contains("kitty") {
            return "terminal"
        } else if lower.contains("safari") || lower.contains("chrome") || lower.contains("firefox") || lower.contains("arc") || lower.contains("brave") {
            return "globe"
        }
        return "app"
    }
}
