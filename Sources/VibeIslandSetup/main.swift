import Foundation
import VibeIslandCore

@main
struct VibeIslandSetupCLI {
    static func main() {
        do {
            let command = try SetupCommand(arguments: Array(CommandLine.arguments.dropFirst()))
            try command.run()
        } catch let error as SetupError {
            fputs("error: \(error.localizedDescription)\n", stderr)
            exit(1)
        } catch {
            fputs("error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}

private struct SetupCommand {
    enum Action: String {
        case install
        case uninstall
        case status
    }

    let action: Action
    let codexDirectory: URL
    let hooksBinary: URL?

    init(arguments: [String]) throws {
        guard let rawAction = arguments.first,
              let action = Action(rawValue: rawAction) else {
            throw SetupError.usage
        }

        self.action = action

        var hooksBinary: URL?
        var codexDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)

        var index = 1
        while index < arguments.count {
            switch arguments[index] {
            case "--hooks-binary":
                index += 1
                guard index < arguments.count else {
                    throw SetupError.missingValue("--hooks-binary")
                }
                hooksBinary = URL(fileURLWithPath: arguments[index]).standardizedFileURL

            case "--codex-dir":
                index += 1
                guard index < arguments.count else {
                    throw SetupError.missingValue("--codex-dir")
                }
                codexDirectory = URL(fileURLWithPath: arguments[index]).standardizedFileURL

            default:
                throw SetupError.unexpectedArgument(arguments[index])
            }

            index += 1
        }

        if action == .install, hooksBinary == nil {
            hooksBinary = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".build/release/VibeIslandHooks")
                .standardizedFileURL
        }

        self.codexDirectory = codexDirectory
        self.hooksBinary = hooksBinary
    }

    func run() throws {
        switch action {
        case .install:
            try install()
        case .uninstall:
            try uninstall()
        case .status:
            try status()
        }
    }

    private func install() throws {
        guard let hooksBinary else {
            throw SetupError.usage
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: codexDirectory, withIntermediateDirectories: true)

        let configURL = codexDirectory.appendingPathComponent("config.toml")
        let hooksURL = codexDirectory.appendingPathComponent("hooks.json")
        let manifestURL = codexDirectory.appendingPathComponent(CodexHookInstallerManifest.fileName)

        let existingConfig = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        let existingHooks = try? Data(contentsOf: hooksURL)

        let command = CodexHookInstaller.hookCommand(for: hooksBinary.path)
        let featureMutation = CodexHookInstaller.enableCodexHooksFeature(in: existingConfig)
        let hooksMutation = try CodexHookInstaller.installHooksJSON(existingData: existingHooks, hookCommand: command)

        if featureMutation.changed, fileManager.fileExists(atPath: configURL.path) {
            try backupFile(at: configURL)
        }
        if hooksMutation.changed, fileManager.fileExists(atPath: hooksURL.path) {
            try backupFile(at: hooksURL)
        }

        try featureMutation.contents.write(to: configURL, atomically: true, encoding: .utf8)
        if let hooksData = hooksMutation.contents {
            try hooksData.write(to: hooksURL, options: .atomic)
        }

        let manifest = CodexHookInstallerManifest(
            hookCommand: command,
            enabledCodexHooksFeature: featureMutation.featureEnabledByInstaller
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)

        print("Installed Vibe Island Codex hooks.")
        print("Codex dir: \(codexDirectory.path)")
        print("Hooks binary: \(hooksBinary.path)")
        if featureMutation.featureEnabledByInstaller {
            print("Updated config.toml to enable [features].codex_hooks = true")
        } else {
            print("config.toml already had codex_hooks enabled")
        }
    }

    private func uninstall() throws {
        let fileManager = FileManager.default
        let configURL = codexDirectory.appendingPathComponent("config.toml")
        let hooksURL = codexDirectory.appendingPathComponent("hooks.json")
        let manifestURL = codexDirectory.appendingPathComponent(CodexHookInstallerManifest.fileName)

        let manifest = try loadManifest(at: manifestURL)
        let existingHooks = try? Data(contentsOf: hooksURL)
        let hooksMutation = try CodexHookInstaller.uninstallHooksJSON(
            existingData: existingHooks,
            managedCommand: manifest?.hookCommand
        )

        if hooksMutation.changed, fileManager.fileExists(atPath: hooksURL.path) {
            try backupFile(at: hooksURL)
        }

        if let hooksData = hooksMutation.contents {
            try hooksData.write(to: hooksURL, options: .atomic)
        } else if fileManager.fileExists(atPath: hooksURL.path) {
            try fileManager.removeItem(at: hooksURL)
        }

        if let manifest, manifest.enabledCodexHooksFeature, !hooksMutation.hasRemainingHooks {
            let existingConfig = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
            let featureMutation = CodexHookInstaller.disableCodexHooksFeatureIfManaged(in: existingConfig)

            if featureMutation.changed {
                if fileManager.fileExists(atPath: configURL.path) {
                    try backupFile(at: configURL)
                }
                try featureMutation.contents.write(to: configURL, atomically: true, encoding: .utf8)
            }
        }

        if fileManager.fileExists(atPath: manifestURL.path) {
            try fileManager.removeItem(at: manifestURL)
        }

        print("Removed Vibe Island Codex hooks.")
        print("Codex dir: \(codexDirectory.path)")
        if hooksMutation.hasRemainingHooks {
            print("Preserved unrelated hooks.json entries.")
        }
    }

    private func status() throws {
        let configURL = codexDirectory.appendingPathComponent("config.toml")
        let hooksURL = codexDirectory.appendingPathComponent("hooks.json")
        let manifestURL = codexDirectory.appendingPathComponent(CodexHookInstallerManifest.fileName)

        let configContents = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        let hooksData = try? Data(contentsOf: hooksURL)
        let manifest = try loadManifest(at: manifestURL)

        let hooksCommand = manifest?.hookCommand ?? hooksBinary.map { CodexHookInstaller.hookCommand(for: $0.path) }
        let isFeatureEnabled = configContents.contains("codex_hooks = true")
        let hasManagedHooks = ((try? CodexHookInstaller.uninstallHooksJSON(existingData: hooksData, managedCommand: hooksCommand))?.changed) == true

        print("Codex dir: \(codexDirectory.path)")
        print("Feature flag enabled: \(isFeatureEnabled ? "yes" : "no")")
        print("Managed hooks present: \(hasManagedHooks ? "yes" : "no")")
        if let hooksBinary {
            print("Hooks binary: \(hooksBinary.path)")
        }
        if let manifest {
            print("Manifest: present")
            print("Feature enabled by installer: \(manifest.enabledCodexHooksFeature ? "yes" : "no")")
        } else {
            print("Manifest: missing")
        }
    }

    private func loadManifest(at url: URL) throws -> CodexHookInstallerManifest? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CodexHookInstallerManifest.self, from: data)
    }

    private func backupFile(at url: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timestamp = formatter.string(from: .now).replacingOccurrences(of: ":", with: "-")
        let backupURL = url.appendingPathExtension("backup.\(timestamp)")
        if fileManager.fileExists(atPath: backupURL.path) {
            try fileManager.removeItem(at: backupURL)
        }
        try fileManager.copyItem(at: url, to: backupURL)
    }
}

private enum SetupError: Error, LocalizedError {
    case usage
    case missingValue(String)
    case unexpectedArgument(String)

    var errorDescription: String? {
        switch self {
        case .usage:
            """
            Usage:
              swift run VibeIslandSetup install [--hooks-binary /abs/path/to/VibeIslandHooks] [--codex-dir /abs/path/to/.codex]
              swift run VibeIslandSetup uninstall [--codex-dir /abs/path/to/.codex]
              swift run VibeIslandSetup status [--hooks-binary /abs/path/to/VibeIslandHooks] [--codex-dir /abs/path/to/.codex]
            """
        case let .missingValue(flag):
            "Missing value for \(flag)"
        case let .unexpectedArgument(argument):
            "Unexpected argument: \(argument)"
        }
    }
}
