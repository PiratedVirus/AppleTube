import CryptoKit
import Foundation

/// Raw API responses in memory and on disk (Caches), so revisited pages open instantly and Home/Library can
/// paint from the last session while fresh data loads.
@MainActor
final class ResponseCache {
    private var memory: [String: (data: Data, date: Date)] = [:]
    private let directory: URL = {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "APIResponses")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    func get(key: String, maxAge: TimeInterval) -> Data? {
        if let hit = memory[key] {
            return Date.now.timeIntervalSince(hit.date) <= maxAge ? hit.data : nil
        }
        let file = path(for: key)
        guard let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
              Date.now.timeIntervalSince(date) <= maxAge,
              let data = try? Data(contentsOf: file)
        else { return nil }
        memory[key] = (data, date)
        return data
    }

    func put(_ data: Data, key: String) {
        memory[key] = (data, .now)
        let file = path(for: key)
        Task.detached(priority: .background) { try? data.write(to: file, options: .atomic) }
    }

    func remove(key: String) {
        memory[key] = nil
        try? FileManager.default.removeItem(at: path(for: key))
    }

    private func path(for key: String) -> URL {
        let hash = SHA256.hash(data: Data(key.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: "\(hash).json")
    }
}
