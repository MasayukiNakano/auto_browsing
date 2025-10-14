import Foundation

actor LoadMoreStrategyClient {
    private let configuration = Configuration()
    private var fallbackStates: [String: FallbackState] = [:]

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var readerTask: Task<Void, Never>?
    private var pendingContinuations: [CheckedContinuation<StrategyResponsePayload, Error>] = []

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func ensureRunning() async throws {
        guard process == nil else { return }
        guard let launchCommand = configuration.command else {
            throw LoadMoreStrategyBridgeError.processUnavailable
        }

        let process = Process()
        process.executableURL = launchCommand.executable
        process.arguments = launchCommand.arguments
        process.currentDirectoryURL = configuration.workingDirectory

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        process.terminationHandler = { [weak self] proc in
            Task { await self?.handleTermination(exitCode: proc.terminationStatus) }
        }

        do {
            try process.run()
        } catch {
            throw LoadMoreStrategyBridgeError.processUnavailable
        }

        stdinHandle = stdinPipe.fileHandleForWriting
        readerTask = Task { [weak self] in
            await self?.readLoop(handle: stdoutPipe.fileHandleForReading)
        }

        // 標準エラーの内容はログ出しのみ
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
            Logger.shared.debug("Strategy stderr: \(text)")
        }

        self.process = process
    }

    func stop() async {
        readerTask?.cancel()
        readerTask = nil

        stdinHandle?.closeFile()
        stdinHandle = nil

        if let process {
            process.terminate()
            process.waitUntilExit()
        }
        process = nil

        // 未処理の待機者にエラーを返す
        while !pendingContinuations.isEmpty {
            let continuation = pendingContinuations.removeFirst()
            continuation.resume(throwing: LoadMoreStrategyBridgeError.unexpectedTermination)
        }

        fallbackStates.removeAll()
    }

    func nextInstruction(
        for site: SiteProfile,
        buttonSnapshots: [StrategyButtonSnapshot],
        linkSnapshots: [StrategyLinkSnapshot],
        pageURL: String?
    ) async throws -> AutomationInstruction {
        if canUseBridge {
            do {
                try await ensureRunning()
                if let response = try await sendRequest(site: site, buttonSnapshots: buttonSnapshots, linkSnapshots: linkSnapshots, pageURL: pageURL) {
                    return try instruction(from: response)
                }
            } catch {
                Logger.shared.error("戦略サーバーからの指示取得に失敗: \(error)")
            }
        }

        // ブリッジが使えない場合は従来のローカル戦略へフォールバック
        switch site.strategy.type {
        case .cssSelector:
            return cssSelectorInstruction(for: site)
        case .textMatch:
            return textMatchInstruction(for: site)
        case .script:
            return scriptInstruction(for: site)
        case .fallback:
            return fallbackInstruction(for: site)
        }
    }

    private var canUseBridge: Bool {
        configuration.command != nil
    }

    private func sendRequest(
        site: SiteProfile,
        buttonSnapshots: [StrategyButtonSnapshot],
        linkSnapshots: [StrategyLinkSnapshot],
        pageURL: String?
    ) async throws -> StrategyResponsePayload? {
        guard let stdinHandle else { return nil }

        let payload = StrategyRequestPayload(siteId: site.identifier, url: pageURL, visibleButtons: buttonSnapshots, links: linkSnapshots, metadata: nil)
        let data = try encoder.encode(payload)

        return try await withCheckedThrowingContinuation { continuation in
            pendingContinuations.append(continuation)
            stdinHandle.write(data)
            stdinHandle.write(Data([0x0A]))
        }
    }

    private func instruction(from response: StrategyResponsePayload) throws -> AutomationInstruction {
        guard response.success else {
            throw LoadMoreStrategyBridgeError.strategyFailure(response.message ?? "Unknown error")
        }

        switch response.action {
        case .press:
            guard let query = response.query else {
                throw LoadMoreStrategyBridgeError.responseMismatch
            }
            return .press(AccessibilitySelector(titleContains: query.titleContains, role: query.role))

        case .scroll:
            let distance = response.scrollDistance ?? -480
            return .scroll(distance: distance)

        case .wait:
            let seconds = response.waitSeconds ?? 2.0
            return .wait(seconds)

        case .noAction:
            return .noAction

        case .error:
            throw LoadMoreStrategyBridgeError.strategyFailure(response.message ?? "Strategy error")
        }
    }

    private func readLoop(handle: FileHandle) async {
        do {
            for try await line in handle.bytes.lines {
                await handleLine(String(line))
            }
        } catch {
            Logger.shared.error("戦略サーバーの出力読み込みに失敗: \(error)")
        }

        var exitCode: Int32 = 0
        if let proc = process {
            if proc.isRunning {
                proc.waitUntilExit()
            }
            exitCode = proc.terminationStatus
        }
        await handleTermination(exitCode: exitCode)
    }

    private func logHandshake(_ event: StrategyServerEvent) {
        switch event.event {
        case "hello":
            Logger.shared.info("Strategy server online: \(event.name ?? "unknown")")
        case "shutdown":
            Logger.shared.info("Strategy server shutdown")
        default:
            if let message = event.message {
                Logger.shared.info("Strategy event: \(event.event) - \(message)")
            } else {
                Logger.shared.info("Strategy event: \(event.event)")
            }
        }
    }

    private func handleLine(_ line: String) async {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let data = trimmed.data(using: .utf8) {
            if let response = try? decoder.decode(StrategyResponsePayload.self, from: data) {
                resumeNextContinuation(with: response)
                return
            }
            if let event = try? decoder.decode(StrategyServerEvent.self, from: data) {
                logHandshake(event)
                return
            }
        }

        Logger.shared.debug("Strategy server から未対応のメッセージ: \(line)")
    }

    private func resumeNextContinuation(with response: StrategyResponsePayload) {
        guard !pendingContinuations.isEmpty else {
            Logger.shared.debug("受信したレスポンスに対応する待機が存在しませんでした")
            return
        }
        let continuation = pendingContinuations.removeFirst()
        continuation.resume(returning: response)
    }

    private func handleTermination(exitCode: Int32) async {
        guard process != nil else { return }
        Logger.shared.info("Strategy server terminated with code \(exitCode)")
        process = nil
        stdinHandle = nil
        readerTask?.cancel()
        readerTask = nil

        while !pendingContinuations.isEmpty {
            let continuation = pendingContinuations.removeFirst()
            continuation.resume(throwing: LoadMoreStrategyBridgeError.unexpectedTermination)
        }
    }

    private func cssSelectorInstruction(for site: SiteProfile) -> AutomationInstruction {
        let title = site.strategy.options["buttonText"] ?? "Load more"
        return .press(AccessibilitySelector(titleContains: title, role: "AXButton"))
    }

    private func textMatchInstruction(for site: SiteProfile) -> AutomationInstruction {
        let phrase = site.strategy.options["phrase"] ?? "Load more"
        return .press(AccessibilitySelector(titleContains: phrase, role: "AXButton"))
    }

    private func scriptInstruction(for site: SiteProfile) -> AutomationInstruction {
        let phrase = site.strategy.options["fallbackText"] ?? "Load more"
        return .press(AccessibilitySelector(titleContains: phrase, role: "AXButton"))
    }

    private func fallbackInstruction(for site: SiteProfile) -> AutomationInstruction {
        var state = fallbackStates[site.identifier, default: FallbackState()]
        defer { fallbackStates[site.identifier] = state }

        if state.nextStepIsWait {
            state.nextStepIsWait = false
            let interval = Double(site.strategy.options["waitInterval"] ?? "2.0") ?? 2.0
            return .wait(interval)
        } else {
            state.nextStepIsWait = true
            let distance = Double(site.strategy.options["scrollDistance"] ?? "480") ?? 480
            return .scroll(distance: -abs(distance))
        }
    }

    private struct FallbackState {
        var nextStepIsWait = false
    }

    private struct Configuration {
        struct Command {
            let executable: URL
            let arguments: [String]
        }

        let command: Command?
        let workingDirectory: URL?

        init(fileManager: FileManager = .default) {
            let env = ProcessInfo.processInfo.environment
            if let commandString = env["AUTO_BROWSING_STRATEGY_CMD"], !commandString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let executable = URL(fileURLWithPath: "/bin/sh")
                self.command = Command(executable: executable, arguments: ["-lc", commandString])
                self.workingDirectory = nil
                return
            }

            // デフォルトでは、gradle installDist 後の実行スクリプトを探す
            let cwd = URL(fileURLWithPath: fileManager.currentDirectoryPath)
            let candidate = cwd
                .appendingPathComponent("..")
                .appendingPathComponent("java-strategy")
                .appendingPathComponent("build")
                .appendingPathComponent("install")
                .appendingPathComponent("load-more-strategy")
                .appendingPathComponent("bin")
                .appendingPathComponent("load-more-strategy")
                .standardized

            if fileManager.isExecutableFile(atPath: candidate.path) {
                self.command = Command(executable: candidate, arguments: [])
                self.workingDirectory = candidate.deletingLastPathComponent()
            } else {
                self.command = nil
                self.workingDirectory = nil
            }
        }
    }
}

enum LoadMoreStrategyClientError: Error {
    case notRunning
}
