import Foundation

struct Capture: Identifiable, Codable {
    let id: Int64
    let ts: Date
    let appName: String
    let windowTitle: String
    let imagePath: String?
    let ocrText: String?
    let windowHash: String
    let isDuplicate: Bool
}

struct Memory: Identifiable, Codable {
    let id: Int64
    let startTs: Date
    let endTs: Date
    let appName: String
    let title: String
    let summary: String
    let rawContext: String?
    let projectHint: String?
}

struct ExcludedApp: Identifiable, Codable {
    var id: String { bundleId }
    let bundleId: String
    let appName: String
}

enum RecordingState {
    case recording
    case paused
}
