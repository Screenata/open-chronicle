import SwiftUI

struct MemoryDetailView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if let memory = appState.selectedMemory {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    backButton

                    VStack(alignment: .leading, spacing: 8) {
                        Label(memory.appName, systemImage: "app")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(memory.title)
                            .font(.title3.weight(.semibold))

                        Text(timeRange(memory))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    Divider()

                    section("Summary") {
                        Text(memory.summary)
                            .font(.callout)
                            .foregroundStyle(.primary)
                    }

                    if let rawContext = memory.rawContext, !rawContext.isEmpty {
                        section("Context") {
                            Text(rawContext)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }

                    if let projectHint = memory.projectHint, !projectHint.isEmpty {
                        section("Project") {
                            Label(projectHint, systemImage: "folder")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    thumbnailSection(memory)
                }
                .padding(16)
            }
        }
    }

    private var backButton: some View {
        Button(action: { appState.selectedMemory = nil }) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                Text("Back")
            }
            .font(.caption)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.blue)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }

    private func timeRange(_ memory: Memory) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return "\(fmt.string(from: memory.startTs)) – \(fmt.string(from: memory.endTs))"
    }

    @ViewBuilder
    private func thumbnailSection(_ memory: Memory) -> some View {
        let captures = appState.captures.filter {
            $0.ts >= memory.startTs && $0.ts <= memory.endTs
        }
        if let firstCapture = captures.first, let imagePath = firstCapture.imagePath {
            section("Screenshot") {
                if let nsImage = NSImage(contentsOfFile: imagePath) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator, lineWidth: 0.5))
                } else {
                    Text("Screenshot expired")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}
