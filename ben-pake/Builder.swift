import Foundation

struct BuildFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

struct WebsiteOptions: Encodable, Sendable {
    var fullscreen = false
    var hideTitleBar = false
    var darkMode = false
    var hideOnClose = true
    var showSystemTray = false
    var restoreLastUrl = false
    var multiWindow = false
    var newWindow = false
    var alwaysOnTop = false
    var incognito = false
    var startToTray = false
    var activationShortcut = ""
    var proxyUrl = ""
    var userAgent = ""
}

struct Recipe: Sendable {
    let url: String
    let name: String
    let icon: String?
    let width: Int
    let height: Int
    let options: WebsiteOptions
    let styles: String
    let script: String

    init(url: String, name: String, icon: URL?, width: String, height: String, options: WebsiteOptions,
         styles: String, script: String, galleryIcon: String?) throws {
        let url = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let address = URLComponents(string: url),
              ["http", "https"].contains(address.scheme?.lowercased() ?? ""),
              let host = address.host, !host.isEmpty else {
            throw BuildFailure("请输入完整的 HTTP 或 HTTPS 网址。")
        }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != ".", name != "..",
              name.rangeOfCharacter(from: CharacterSet(charactersIn: "/\\:").union(.controlCharacters)) == nil else {
            throw BuildFailure("请输入应用名称，名称不能包含路径分隔符或控制字符。")
        }
        guard let width = Int(width), let height = Int(height), width > 0, height > 0 else {
            throw BuildFailure("窗口宽高必须是正整数。")
        }
        self.url = url
        self.name = name
        self.icon = icon?.path ?? galleryIcon
        self.width = width
        self.height = height
        self.options = options
        self.styles = styles
        self.script = script
    }

    func writeConfig(to file: URL) throws {
        let settings = try JSONEncoder().encode(options)
        var config = try JSONSerialization.jsonObject(with: settings) as? [String: Any] ?? [:]
        config["url"] = url
        config["name"] = name
        config["icon"] = icon
        config["width"] = width
        config["height"] = height
        var injectionFiles: [String] = []
        for (name, content) in [("custom.css", styles), ("custom.js", script)] where !content.isEmpty {
            let source = file.deletingLastPathComponent().appendingPathComponent(name)
            try content.write(to: source, atomically: true, encoding: .utf8)
            injectionFiles.append(source.path)
        }
        config["inject"] = injectionFiles
        try JSONSerialization.data(withJSONObject: config).write(to: file)
    }
}

struct Builder: Sendable {
    let cli: URL
    let environment: [String: String]

    init(cli: URL, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.cli = cli
        var environment = environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = ["\(home)/.cargo/bin", "/opt/homebrew/bin", "/usr/local/bin",
                     "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        environment["PATH"] = ([environment["PATH"] ?? ""] + paths)
            .filter { !$0.isEmpty }.joined(separator: ":")
        let cache = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/Ben-Pake/cargo-target", isDirectory: true)
        environment["CARGO_TARGET_DIR"] = cache.path
        self.environment = environment
    }

    func build(_ recipe: Recipe, in directory: URL, log: @escaping @Sendable (String) -> Void) throws -> URL {
        let files = FileManager.default
        let destination = directory.appendingPathComponent(recipe.name).appendingPathExtension("dmg")
        guard !files.fileExists(atPath: destination.path) else {
            throw BuildFailure("保存位置已有「\(destination.lastPathComponent)」。请选择其他位置或更改名称。")
        }
        guard files.isReadableFile(atPath: cli.path) else {
            throw BuildFailure("缺少随附的 Pake CLI。请重新安装 Ben-Pake。")
        }

        let workspace = files.temporaryDirectory.appendingPathComponent("ben-pake-\(UUID())", isDirectory: true)
        try files.createDirectory(at: workspace, withIntermediateDirectories: false)
        defer { try? files.removeItem(at: workspace) }
        let config = workspace.appendingPathComponent("app.json")
        try recipe.writeConfig(to: config)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["node", cli.path, "--config", config.path, "--targets", "dmg", "--json"]
        process.currentDirectoryURL = workspace
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        let stdout = workspace.appendingPathComponent("result.json")
        try Data().write(to: stdout)
        let resultWriter = try FileHandle(forWritingTo: stdout)
        defer { try? resultWriter.close() }
        let stderr = Pipe()
        process.standardOutput = resultWriter
        process.standardError = stderr
        try process.run()
        try stderr.fileHandleForWriting.close()

        let lastLog = try streamLog(stderr.fileHandleForReading, to: log)
        process.waitUntilExit()

        let result = try? JSONDecoder().decode(CLIResult.self, from: Data(contentsOf: stdout))
        guard process.terminationStatus == 0, let result, result.ok else {
            let details = [result?.error?.message, result?.error?.hint].compactMap { $0 }.joined(separator: "\n")
            let fallback = lastLog.isEmpty ? "Pake 构建失败（退出码 \(process.terminationStatus)）。" : lastLog
            throw BuildFailure(details.isEmpty ? fallback : details)
        }
        guard let image = result.outputs.first(where: { $0.format == "dmg" }) else {
            throw BuildFailure("打包已结束，但 Pake 没有返回 DMG。")
        }
        let source = URL(fileURLWithPath: image.path).resolvingSymlinksInPath()
        guard source.deletingLastPathComponent().path == workspace.resolvingSymlinksInPath().path,
              let bytes = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize, bytes > 0 else {
            throw BuildFailure("Pake 返回的 DMG 无法读取。")
        }

        let staged = directory.appendingPathComponent(".ben-pake-\(UUID()).dmg")
        defer { try? files.removeItem(at: staged) }
        try files.copyItem(at: source, to: staged)
        do {
            try files.linkItem(at: staged, to: destination)
        } catch let error as CocoaError where error.code == .fileWriteFileExists {
            throw BuildFailure("保存位置已有「\(destination.lastPathComponent)」。请选择其他位置或更改名称。")
        }
        return destination
    }
}

private struct CLIResult: Decodable {
    struct Output: Decodable {
        let path: String
        let format: String
    }
    struct Failure: Decodable {
        let message: String
        let hint: String?
    }

    let ok: Bool
    let outputs: [Output]
    let error: Failure?
}

private func streamLog(_ handle: FileHandle, to log: (String) -> Void) throws -> String {
    var pending = Data()
    var last = ""
    while let chunk = try handle.read(upToCount: 4096), !chunk.isEmpty {
        pending.append(chunk)
        while let newline = pending.firstIndex(of: 10) {
            last = String(decoding: pending[..<newline], as: UTF8.self)
            pending.removeSubrange(...newline)
            log(last)
        }
    }
    if !pending.isEmpty {
        last = String(decoding: pending, as: UTF8.self)
        log(last)
    }
    return last
}
