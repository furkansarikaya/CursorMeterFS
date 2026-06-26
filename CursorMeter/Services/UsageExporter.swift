import Foundation

/// Optionally exports aggregated usage data to `~/.cursormeter/usage.json`.
/// SECURITY: This file contains ONLY percentages and counts — no tokens, no email.
final class UsageExporter {

    static let shared = UsageExporter()
    private init() {}

    private var exportURL: URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir  = home.appendingPathComponent(".cursormeter")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("usage.json")
    }

    struct ExportData: Encodable {
        let updatedAt: String       // ISO8601
        let plan: String
        let usedRequests: Int
        let totalRequests: Int
        let percentageUsed: Int
        let remainingRequests: Int
        let onDemandSpendUSD: Double
        let resetIn: String
        // NOTE: no token, no email, no credentials of any kind
    }

    func export(usage: UsageData) {
        guard let url = exportURL else { return }

        let formatter = ISO8601DateFormatter()
        let data = ExportData(
            updatedAt: formatter.string(from: Date()),
            plan: usage.plan.displayName,
            usedRequests: usage.used,
            totalRequests: usage.total,
            percentageUsed: usage.percentageInt,
            remainingRequests: usage.remainingRequests,
            onDemandSpendUSD: usage.onDemandSpendUSD,
            resetIn: usage.resetDateDescription
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let json = try? encoder.encode(data) else { return }

        // Write atomically to avoid partial-file reads
        try? json.write(to: url, options: .atomic)
    }

    func deleteExport() {
        guard let url = exportURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
