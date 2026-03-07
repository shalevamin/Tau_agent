import Foundation
import SwiftUI

extension OnboardingView {
    @MainActor
    func maybeRunUltimateSetup() async {
        guard UserDefaults.standard.integer(forKey: ultimateSetupVersionKey) < currentUltimateSetupVersion else {
            if self.ultimateSetupStatus == nil {
                self.ultimateSetupStatus = "Ultimate setup already applied."
            }
            return
        }
        await self.runUltimateSetup(force: false)
    }

    @MainActor
    func runUltimateSetup(force: Bool) async {
        guard !self.ultimateSetupRunning else { return }
        if !force,
           UserDefaults.standard.integer(forKey: ultimateSetupVersionKey) >= currentUltimateSetupVersion
        {
            return
        }

        self.ultimateSetupRunning = true
        self.ultimateSetupStatus = "Starting Tua Agent ultimate setup…"
        self.ultimateSetupDetail = nil
        defer { self.ultimateSetupRunning = false }

        do {
            self.state.launchAtLogin = true
            AppStateStore.updateLaunchAtLogin(enabled: true)

            try await self.applyUltimateConfigDefaults()
            try await self.ensureUltimateMemoryScaffold()
            self.seedUltimateExecApprovals()

            await self.setUltimateSetupStatus("Requesting macOS permissions…")
            for cap in Capability.allCases {
                _ = await PermissionManager.ensure([cap], interactive: true)
                await self.refreshPerms()
            }

            if !CLIInstaller.isInstalled() {
                await self.setUltimateSetupStatus("Installing the Tua/OpenClaw CLI…")
                await CLIInstaller.install { message in
                    self.cliStatus = message
                    self.ultimateSetupStatus = message
                }
            }
            self.refreshCLIStatus()

            await self.setUltimateSetupStatus("Installing OpenAI operator toolchain…")
            let toolchainOutput = try await self.installUltimateToolchain()

            await self.setUltimateSetupStatus("Syncing external skill packs…")
            let skillsOutput = try await self.installUltimateSkills()

            await self.setUltimateSetupStatus("Preparing native browser bridge…")
            let browserOutput = try await self.installBrowserExtension()

            UserDefaults.standard.set(currentUltimateSetupVersion, forKey: ultimateSetupVersionKey)
            self.ultimateSetupStatus = "Ultimate setup complete."
            self.ultimateSetupDetail = [toolchainOutput, skillsOutput, browserOutput]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        } catch {
            self.ultimateSetupStatus = "Ultimate setup failed."
            self.ultimateSetupDetail = error.localizedDescription
        }
    }

    @ViewBuilder
    func ultimateSetupCard() -> some View {
        self.onboardingCard(spacing: 10, padding: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "bolt.badge.checkmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 22)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("Ultimate setup")
                            .font(.headline)
                        if self.ultimateSetupRunning {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    Text(self.ultimateSetupStatus ?? "Tua Agent can preinstall skills, request permissions, seed command approvals, and prep browser automation.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail = self.ultimateSetupDetail, !detail.isEmpty {
                        Text(detail)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let browserExtensionPath, !browserExtensionPath.isEmpty {
                        Text("Browser relay staged at \(browserExtensionPath)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 10) {
                        Button(self.ultimateSetupRunning ? "Running…" : "Run again") {
                            Task { await self.runUltimateSetup(force: true) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(self.ultimateSetupRunning)

                        Button("Open Skills") {
                            self.openSettings(tab: .skills)
                        }
                        .buttonStyle(.bordered)
                        .disabled(self.ultimateSetupRunning)
                    }
                }
            }
        }
    }

    private func setUltimateSetupStatus(_ message: String) async {
        await MainActor.run {
            self.ultimateSetupStatus = message
        }
    }

    private func applyUltimateConfigDefaults() async throws {
        var root = await ConfigStore.load()

        var browser = root["browser"] as? [String: Any] ?? [:]
        browser["enabled"] = true
        let defaultProfile = (browser["defaultProfile"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if defaultProfile.isEmpty {
            browser["defaultProfile"] = "openclaw"
        }
        if browser["headless"] == nil {
            browser["headless"] = false
        }
        root["browser"] = browser

        var tools = root["tools"] as? [String: Any] ?? [:]
        var web = tools["web"] as? [String: Any] ?? [:]
        var search = web["search"] as? [String: Any] ?? [:]
        search["enabled"] = false
        web["search"] = search
        tools["web"] = web
        root["tools"] = tools

        var skills = root["skills"] as? [String: Any] ?? [:]
        var load = skills["load"] as? [String: Any] ?? [:]
        if load["watch"] == nil {
            load["watch"] = true
        }
        skills["load"] = load
        root["skills"] = skills

        var agents = root["agents"] as? [String: Any] ?? [:]
        var defaults = agents["defaults"] as? [String: Any] ?? [:]
        defaults["model"] = "openai/gpt-5.4"
        defaults["models"] = [
            "openai/gpt-5.4": [:],
            "openai/gpt-5.2": [:],
            "openai/gpt-5-mini": [:],
            "openai-codex/gpt-5.4": [:],
            "openai-codex/gpt-5.2-codex": [:],
        ]
        if defaults["thinkingDefault"] == nil {
            defaults["thinkingDefault"] = "low"
        }
        var subagents = defaults["subagents"] as? [String: Any] ?? [:]
        if subagents["maxSpawnDepth"] == nil {
            subagents["maxSpawnDepth"] = 3
        }
        if subagents["maxChildrenPerAgent"] == nil {
            subagents["maxChildrenPerAgent"] = 8
        }
        if subagents["runTimeoutSeconds"] == nil {
            subagents["runTimeoutSeconds"] = 1800
        }
        defaults["subagents"] = subagents

        var compaction = defaults["compaction"] as? [String: Any] ?? [:]
        if compaction["reserveTokensFloor"] == nil {
            compaction["reserveTokensFloor"] = 20000
        }
        var memoryFlush = compaction["memoryFlush"] as? [String: Any] ?? [:]
        if memoryFlush["enabled"] == nil {
            memoryFlush["enabled"] = true
        }
        if memoryFlush["softThresholdTokens"] == nil {
            memoryFlush["softThresholdTokens"] = 4000
        }
        if memoryFlush["systemPrompt"] == nil {
            memoryFlush["systemPrompt"] = "Session nearing compaction. Persist durable user and task memory before context is compacted."
        }
        if memoryFlush["prompt"] == nil {
            memoryFlush["prompt"] = "Write lasting user facts to MEMORY.md and volatile context to memory/YYYY-MM-DD.md. Reply with NO_REPLY if there is nothing worth storing."
        }
        compaction["memoryFlush"] = memoryFlush
        defaults["compaction"] = compaction

        var memorySearch = defaults["memorySearch"] as? [String: Any] ?? [:]
        if memorySearch["enabled"] == nil {
            memorySearch["enabled"] = true
        }
        if memorySearch["provider"] == nil {
            memorySearch["provider"] = "openai"
        }
        if memorySearch["fallback"] == nil {
            memorySearch["fallback"] = "none"
        }
        if memorySearch["sources"] == nil {
            memorySearch["sources"] = ["memory", "sessions"]
        }
        var experimental = memorySearch["experimental"] as? [String: Any] ?? [:]
        if experimental["sessionMemory"] == nil {
            experimental["sessionMemory"] = true
        }
        memorySearch["experimental"] = experimental
        var sync = memorySearch["sync"] as? [String: Any] ?? [:]
        if sync["onSessionStart"] == nil {
            sync["onSessionStart"] = true
        }
        if sync["onSearch"] == nil {
            sync["onSearch"] = true
        }
        if sync["watch"] == nil {
            sync["watch"] = true
        }
        if sync["watchDebounceMs"] == nil {
            sync["watchDebounceMs"] = 1500
        }
        memorySearch["sync"] = sync
        var query = memorySearch["query"] as? [String: Any] ?? [:]
        if query["maxResults"] == nil {
            query["maxResults"] = 8
        }
        var hybrid = query["hybrid"] as? [String: Any] ?? [:]
        if hybrid["enabled"] == nil {
            hybrid["enabled"] = true
        }
        var temporalDecay = hybrid["temporalDecay"] as? [String: Any] ?? [:]
        if temporalDecay["enabled"] == nil {
            temporalDecay["enabled"] = true
        }
        if temporalDecay["halfLifeDays"] == nil {
            temporalDecay["halfLifeDays"] = 45
        }
        hybrid["temporalDecay"] = temporalDecay
        query["hybrid"] = hybrid
        memorySearch["query"] = query
        defaults["memorySearch"] = memorySearch

        agents["defaults"] = defaults
        root["agents"] = agents

        var hooks = root["hooks"] as? [String: Any] ?? [:]
        var internalHooks = hooks["internal"] as? [String: Any] ?? [:]
        internalHooks["enabled"] = true
        var entries = internalHooks["entries"] as? [String: Any] ?? [:]
        var sessionMemory = entries["session-memory"] as? [String: Any] ?? [:]
        sessionMemory["enabled"] = true
        if sessionMemory["messages"] == nil {
            sessionMemory["messages"] = 25
        }
        entries["session-memory"] = sessionMemory
        internalHooks["entries"] = entries
        hooks["internal"] = internalHooks
        root["hooks"] = hooks

        try await ConfigStore.save(root)
    }

    private func ensureUltimateMemoryScaffold() async throws {
        let root = await ConfigStore.load()
        let workspaceURL: URL = {
            let workspacePath = ((root["agents"] as? [String: Any])?["defaults"] as? [String: Any])?["workspace"] as? String
            let trimmed = workspacePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if trimmed.isEmpty {
                return OpenClawConfigFile.defaultWorkspaceURL()
            }
            return URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath, isDirectory: true)
        }()
        try AgentWorkspace.ensureMemoryScaffold(workspaceURL: workspaceURL)
    }

    private func seedUltimateExecApprovals() {
        var file = ExecApprovalsStore.ensureFile()
        var defaults = file.defaults ?? ExecApprovalsDefaults()
        defaults.security = .full
        defaults.ask = .always
        defaults.askFallback = .full
        defaults.autoAllowSkills = true
        file.defaults = defaults
        ExecApprovalsStore.saveFile(file)
    }

    private func installUltimateSkills() async throws -> String? {
        guard let repoRoot = Self.devRepoRoot(),
              let node = CommandResolver.findExecutable(named: "node")
        else {
            return "Skill sync skipped: local repo root or node runtime not found."
        }
        let script = repoRoot.appendingPathComponent("scripts/install-ultimate-skills.mjs")
        guard FileManager().isReadableFile(atPath: script.path) else {
            return "Skill sync skipped: installer script unavailable."
        }

        let response = await ShellExecutor.runDetailed(
            command: [node, script.path],
            cwd: repoRoot.path,
            env: nil,
            timeout: 1800)
        if response.success {
            let summary = response.stdout
                .split(whereSeparator: \.isNewline)
                .prefix(6)
                .joined(separator: "\n")
            return summary.isEmpty ? "Skill sync finished." : summary
        }
        throw NSError(domain: "TuaSetup", code: 1, userInfo: [
            NSLocalizedDescriptionKey: response.stderr.nonEmpty ??
                response.errorMessage ??
                "Failed to install skill packs.",
        ])
    }

    private func installUltimateToolchain() async throws -> String? {
        guard let repoRoot = Self.devRepoRoot(),
              let node = CommandResolver.findExecutable(named: "node")
        else {
            return "Toolchain install skipped: local repo root or node runtime not found."
        }
        let script = repoRoot.appendingPathComponent("scripts/install-ultimate-toolchain.mjs")
        guard FileManager().isReadableFile(atPath: script.path) else {
            return "Toolchain install skipped: installer script unavailable."
        }

        let response = await ShellExecutor.runDetailed(
            command: [node, script.path],
            cwd: repoRoot.path,
            env: nil,
            timeout: 3600)
        if response.success {
            let summary = response.stdout
                .split(whereSeparator: \.isNewline)
                .prefix(8)
                .joined(separator: "\n")
            return summary.isEmpty ? "Native toolchain installed." : summary
        }
        throw NSError(domain: "TuaSetup", code: 3, userInfo: [
            NSLocalizedDescriptionKey: response.stderr.nonEmpty ??
                response.errorMessage ??
                "Failed to install the ultimate toolchain.",
        ])
    }

    private func installBrowserExtension() async throws -> String? {
        if let cliPath = CLIInstaller.installedLocation() {
            let response = await ShellExecutor.runDetailed(
                command: [cliPath, "browser", "extension", "install"],
                cwd: nil,
                env: nil,
                timeout: 180)
            if response.success {
                let path = response.stdout
                    .split(whereSeparator: \.isNewline)
                    .map(String.init)
                    .first?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                await MainActor.run {
                    self.browserExtensionPath = path
                }
                return "Browser extension staged."
            }
            throw NSError(domain: "TuaSetup", code: 2, userInfo: [
                NSLocalizedDescriptionKey: response.stderr.nonEmpty ??
                    response.errorMessage ??
                    "Failed to install the browser extension.",
            ])
        }
        return "Browser extension skipped: CLI unavailable."
    }

    private static func devRepoRoot() -> URL? {
        let sourceURL = URL(fileURLWithPath: #filePath)
        let repoRoot = sourceURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return FileManager().fileExists(atPath: repoRoot.path) ? repoRoot : nil
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = self.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
