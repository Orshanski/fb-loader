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
        return VolumeInfo(name: name, isNetwork: !isLocal, remountURL: v.volumeURLForRemounting.map(withoutCredentials))
    }

    /// `nil` и при таймауте: зависший SMB не должен задерживать вызывающего.
    static func detectOffMain(_ url: URL) async -> VolumeInfo? {
        await withTimeout(.seconds(5)) { detect(url) } ?? nil
    }

    /// Пароль и логин из URL перемонтирования не должны оседать в UserDefaults.
    static func withoutCredentials(_ url: URL) -> URL {
        guard var c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        c.user = nil
        c.password = nil
        return c.url ?? url
    }

    /// Адрес шары для показа: без логина/пароля, без Bonjour-меток вида `._smb._tcp`, в читаемом виде.
    var shareAddress: String? {
        guard isNetwork, let remountURL,
              let c = URLComponents(url: remountURL, resolvingAgainstBaseURL: false),
              let scheme = c.scheme, let host = c.host else { return nil }
        let cleanHost = Self.stripServiceLabel(host)
        let port = c.port.map { ":\($0)" } ?? ""
        return "\(scheme)://\(cleanHost)\(port)\(c.path)"
    }

    /// Одна и та же шара: схема, хост (без регистра, без `._smb._tcp` и `.local`), порт и путь.
    static func sameShare(_ a: URL, _ b: URL) -> Bool {
        guard let ka = shareKey(a), let kb = shareKey(b) else { return false }
        return ka == kb
    }

    private static func shareKey(_ url: URL) -> String? {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = c.scheme, let host = c.host else { return nil }
        let bare = stripServiceLabel(host).lowercased()
        let trimmedHost = bare.hasSuffix(".local") ? String(bare.dropLast(6)) : bare
        var path = c.path.lowercased()
        while path.hasSuffix("/") { path.removeLast() }
        return "\(scheme.lowercased())://\(trimmedHost):\(c.port.map(String.init) ?? "")\(path)"
    }

    fileprivate static func stripServiceLabel(_ host: String) -> String {
        host.replacingOccurrences(of: #"\._[A-Za-z0-9-]+\._tcp"#, with: "", options: .regularExpression)
    }
}
