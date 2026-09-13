// SPDX-License-Identifier: MIT

import Foundation

/// Stockage des jetons pour l'outil de mise au point uniquement.
///
/// En clair, dans `~/.config/ipanoramax/tokens.json`. L'application, elle,
/// place le jeton dans le Keychain : ne recopie pas ce code dans iPanoramax.
struct TokenStore {

    struct Entry: Codable {
        var id: String
        var jwt: String
    }

    private let fileURL: URL

    init() {
        let configuration = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/ipanoramax", isDirectory: true)
        self.fileURL = configuration.appendingPathComponent("tokens.json")
    }

    private func load() -> [String: Entry] {
        guard let data = try? Data(contentsOf: fileURL),
              let entries = try? JSONDecoder().decode([String: Entry].self, from: data)
        else { return [:] }
        return entries
    }

    private func save(_ entries: [String: Entry]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(entries).write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    func entry(for host: String) -> Entry? {
        load()[host]
    }

    func store(_ entry: Entry, for host: String) throws {
        var entries = load()
        entries[host] = entry
        try save(entries)
    }

    func remove(host: String) throws {
        var entries = load()
        entries.removeValue(forKey: host)
        try save(entries)
    }

    var path: String { fileURL.path }
}
