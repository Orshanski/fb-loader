import Foundation

/// Сведения о томе, на котором лежит сохранённый путь: по ним при старте
/// отличают неподключённый сетевой диск от пропавшего файла.
nonisolated struct VolumeInfo: Codable, Equatable, Sendable {
    let name: String
    let isNetwork: Bool
    let remountURL: URL?

    /// `nil`, если путь недоступен или система не отдала сведения.
    static func detect(_ url: URL) -> VolumeInfo? {
        let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeIsLocalKey, .volumeURLForRemountingKey]
        guard let v = try? url.resourceValues(forKeys: keys),
              let name = v.volumeName, let isLocal = v.volumeIsLocal else { return nil }
        return VolumeInfo(name: name, isNetwork: !isLocal, remountURL: v.volumeURLForRemounting)
    }

    /// Адрес шары для показа: без логина/пароля и без Bonjour-меток вида `._smb._tcp`.
    var shareAddress: String? {
        guard isNetwork, let remountURL,
              var c = URLComponents(url: remountURL, resolvingAgainstBaseURL: false),
              let host = c.host else { return nil }
        c.user = nil
        c.password = nil
        c.host = host.replacingOccurrences(of: #"\._[A-Za-z0-9-]+\._tcp"#, with: "",
                                           options: .regularExpression)
        return c.string
    }
}
