import AppKit
import ApplicationServices
import Foundation
import OpenClawIPC
import OpenClawKit

actor MacNodeRuntime {
    private let cameraCapture = CameraCaptureService()
    private let makeMainActorServices: () async -> any MacNodeRuntimeMainActorServices
    private var cachedMainActorServices: (any MacNodeRuntimeMainActorServices)?
    private var mainSessionKey: String = "main"
    private var eventSender: (@Sendable (String, String?) async -> Void)?

    init(
        makeMainActorServices: @escaping () async -> any MacNodeRuntimeMainActorServices = {
            await MainActor.run { LiveMacNodeRuntimeMainActorServices() }
        })
    {
        self.makeMainActorServices = makeMainActorServices
    }

    func updateMainSessionKey(_ sessionKey: String) {
        let trimmed = sessionKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        self.mainSessionKey = trimmed
    }

    func setEventSender(_ sender: (@Sendable (String, String?) async -> Void)?) {
        self.eventSender = sender
    }

    func handleInvoke(_ req: BridgeInvokeRequest) async -> BridgeInvokeResponse {
        let command = req.command
        if self.isCanvasCommand(command), !Self.canvasEnabled() {
            return BridgeInvokeResponse(
                id: req.id,
                ok: false,
                error: OpenClawNodeError(
                    code: .unavailable,
                    message: "CANVAS_DISABLED: enable Canvas in Settings"))
        }
        do {
            switch command {
            case OpenClawCanvasCommand.present.rawValue,
                 OpenClawCanvasCommand.hide.rawValue,
                 OpenClawCanvasCommand.navigate.rawValue,
                 OpenClawCanvasCommand.evalJS.rawValue,
                 OpenClawCanvasCommand.snapshot.rawValue:
                return try await self.handleCanvasInvoke(req)
            case OpenClawCanvasA2UICommand.reset.rawValue,
                 OpenClawCanvasA2UICommand.push.rawValue,
                 OpenClawCanvasA2UICommand.pushJSONL.rawValue:
                return try await self.handleA2UIInvoke(req)
            case OpenClawCameraCommand.snap.rawValue,
                 OpenClawCameraCommand.clip.rawValue,
                 OpenClawCameraCommand.list.rawValue:
                return try await self.handleCameraInvoke(req)
            case OpenClawLocationCommand.get.rawValue:
                return try await self.handleLocationInvoke(req)
            case MacNodeScreenCommand.record.rawValue:
                return try await self.handleScreenRecordInvoke(req)
            case OpenClawSystemCommand.run.rawValue:
                return try await self.handleSystemRun(req)
            case OpenClawSystemCommand.which.rawValue:
                return try await self.handleSystemWhich(req)
            case OpenClawSystemCommand.notify.rawValue:
                return try await self.handleSystemNotify(req)
            case OpenClawSystemCommand.screenshot.rawValue:
                return try await self.handleSystemScreenshot(req)
            case OpenClawSystemCommand.mouse.rawValue:
                return try await self.handleSystemMouse(req)
            case OpenClawSystemCommand.type.rawValue:
                return try await self.handleSystemType(req)
            case OpenClawSystemCommand.keypress.rawValue:
                return try await self.handleSystemKeypress(req)
            case OpenClawSystemCommand.execApprovalsGet.rawValue:
                return try await self.handleSystemExecApprovalsGet(req)
            case OpenClawSystemCommand.execApprovalsSet.rawValue:
                return try await self.handleSystemExecApprovalsSet(req)
            default:
                return Self.errorResponse(req, code: .invalidRequest, message: "INVALID_REQUEST: unknown command")
            }
        } catch {
            return Self.errorResponse(req, code: .unavailable, message: error.localizedDescription)
        }
    }

    private func isCanvasCommand(_ command: String) -> Bool {
        command.hasPrefix("canvas.") || command.hasPrefix("canvas.a2ui.")
    }

    private func handleCanvasInvoke(_ req: BridgeInvokeRequest) async throws -> BridgeInvokeResponse {
        switch req.command {
        case OpenClawCanvasCommand.present.rawValue:
            let params = (try? Self.decodeParams(OpenClawCanvasPresentParams.self, from: req.paramsJSON)) ??
                OpenClawCanvasPresentParams()
            let urlTrimmed = params.url?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let url = urlTrimmed.isEmpty ? nil : urlTrimmed
            let placement = params.placement.map {
                CanvasPlacement(x: $0.x, y: $0.y, width: $0.width, height: $0.height)
            }
            let sessionKey = self.mainSessionKey
            try await MainActor.run {
                _ = try CanvasManager.shared.showDetailed(
                    sessionKey: sessionKey,
                    target: url,
                    placement: placement)
            }
            return BridgeInvokeResponse(id: req.id, ok: true)
        case OpenClawCanvasCommand.hide.rawValue:
            let sessionKey = self.mainSessionKey
            await MainActor.run {
                CanvasManager.shared.hide(sessionKey: sessionKey)
            }
            return BridgeInvokeResponse(id: req.id, ok: true)
        case OpenClawCanvasCommand.navigate.rawValue:
            let params = try Self.decodeParams(OpenClawCanvasNavigateParams.self, from: req.paramsJSON)
            let sessionKey = self.mainSessionKey
            try await MainActor.run {
                _ = try CanvasManager.shared.show(sessionKey: sessionKey, path: params.url)
            }
            return BridgeInvokeResponse(id: req.id, ok: true)
        case OpenClawCanvasCommand.evalJS.rawValue:
            let params = try Self.decodeParams(OpenClawCanvasEvalParams.self, from: req.paramsJSON)
            let sessionKey = self.mainSessionKey
            let result = try await CanvasManager.shared.eval(
                sessionKey: sessionKey,
                javaScript: params.javaScript)
            let payload = try Self.encodePayload(["result": result] as [String: String])
            return BridgeInvokeResponse(id: req.id, ok: true, payloadJSON: payload)
        case OpenClawCanvasCommand.snapshot.rawValue:
            let params = try? Self.decodeParams(OpenClawCanvasSnapshotParams.self, from: req.paramsJSON)
            let format = params?.format ?? .jpeg
            let maxWidth: Int? = {
                if let raw = params?.maxWidth, raw > 0 { return raw }
                return switch format {
                case .png: 900
                case .jpeg: 1600
                }
            }()
            let quality = params?.quality ?? 0.9

            let sessionKey = self.mainSessionKey
            let path = try await CanvasManager.shared.snapshot(sessionKey: sessionKey, outPath: nil)
            defer { try? FileManager().removeItem(atPath: path) }
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            guard let image = NSImage(data: data) else {
                return Self.errorResponse(req, code: .unavailable, message: "canvas snapshot decode failed")
            }
            let encoded = try Self.encodeCanvasSnapshot(
                image: image,
                format: format,
                maxWidth: maxWidth,
                quality: quality)
            let payload = try Self.encodePayload([
                "format": format == .jpeg ? "jpeg" : "png",
                "base64": encoded.base64EncodedString(),
            ])
            return BridgeInvokeResponse(id: req.id, ok: true, payloadJSON: payload)
        default:
            return Self.errorResponse(req, code: .invalidRequest, message: "INVALID_REQUEST: unknown command")
        }
    }

    private func handleA2UIInvoke(_ req: BridgeInvokeRequest) async throws -> BridgeInvokeResponse {
        switch req.command {
        case OpenClawCanvasA2UICommand.reset.rawValue:
            try await self.handleA2UIReset(req)
        case OpenClawCanvasA2UICommand.push.rawValue,
             OpenClawCanvasA2UICommand.pushJSONL.rawValue:
            try await self.handleA2UIPush(req)
        default:
            Self.errorResponse(req, code: .invalidRequest, message: "INVALID_REQUEST: unknown command")
        }
    }

    private func handleCameraInvoke(_ req: BridgeInvokeRequest) async throws -> BridgeInvokeResponse {
        guard Self.cameraEnabled() else {
            return BridgeInvokeResponse(
                id: req.id,
                ok: false,
                error: OpenClawNodeError(
                    code: .unavailable,
                    message: "CAMERA_DISABLED: enable Camera in Settings"))
        }
        switch req.command {
        case OpenClawCameraCommand.snap.rawValue:
            let params = (try? Self.decodeParams(OpenClawCameraSnapParams.self, from: req.paramsJSON)) ??
                OpenClawCameraSnapParams()
            let delayMs = min(10000, max(0, params.delayMs ?? 2000))
            let res = try await self.cameraCapture.snap(
                facing: CameraFacing(rawValue: params.facing?.rawValue ?? "") ?? .front,
                maxWidth: params.maxWidth,
                quality: params.quality,
                deviceId: params.deviceId,
                delayMs: delayMs)
            struct SnapPayload: Encodable {
                var format: String
                var base64: String
                var width: Int
                var height: Int
            }
            let payload = try Self.encodePayload(SnapPayload(
                format: (params.format ?? .jpg).rawValue,
                base64: res.data.base64EncodedString(),
                width: Int(res.size.width),
                height: Int(res.size.height)))
            return BridgeInvokeResponse(id: req.id, ok: true, payloadJSON: payload)
        case OpenClawCameraCommand.clip.rawValue:
            let params = (try? Self.decodeParams(OpenClawCameraClipParams.self, from: req.paramsJSON)) ??
                OpenClawCameraClipParams()
            let res = try await self.cameraCapture.clip(
                facing: CameraFacing(rawValue: params.facing?.rawValue ?? "") ?? .front,
                durationMs: params.durationMs,
                includeAudio: params.includeAudio ?? true,
                deviceId: params.deviceId,
                outPath: nil)
            defer { try? FileManager().removeItem(atPath: res.path) }
            let data = try Data(contentsOf: URL(fileURLWithPath: res.path))
            struct ClipPayload: Encodable {
                var format: String
                var base64: String
                var durationMs: Int
                var hasAudio: Bool
            }
            let payload = try Self.encodePayload(ClipPayload(
                format: (params.format ?? .mp4).rawValue,
                base64: data.base64EncodedString(),
                durationMs: res.durationMs,
                hasAudio: res.hasAudio))
            return BridgeInvokeResponse(id: req.id, ok: true, payloadJSON: payload)
        case OpenClawCameraCommand.list.rawValue:
            let devices = await self.cameraCapture.listDevices()
            let payload = try Self.encodePayload(["devices": devices])
            return BridgeInvokeResponse(id: req.id, ok: true, payloadJSON: payload)
        default:
            return Self.errorResponse(req, code: .invalidRequest, message: "INVALID_REQUEST: unknown command")
        }
    }

    private func handleLocationInvoke(_ req: BridgeInvokeRequest) async throws -> BridgeInvokeResponse {
        let mode = Self.locationMode()
        guard mode != .off else {
            return BridgeInvokeResponse(
                id: req.id,
                ok: false,
                error: OpenClawNodeError(
                    code: .unavailable,
                    message: "LOCATION_DISABLED: enable Location in Settings"))
        }
        let params = (try? Self.decodeParams(OpenClawLocationGetParams.self, from: req.paramsJSON)) ??
            OpenClawLocationGetParams()
        let desired = params.desiredAccuracy ??
            (Self.locationPreciseEnabled() ? .precise : .balanced)
        let services = await self.mainActorServices()
        let status = await services.locationAuthorizationStatus()
        let hasPermission = switch mode {
        case .always:
            status == .authorizedAlways
        case .whileUsing:
            status == .authorizedAlways
        case .off:
            false
        }
        if !hasPermission {
            return BridgeInvokeResponse(
                id: req.id,
                ok: false,
                error: OpenClawNodeError(
                    code: .unavailable,
                    message: "LOCATION_PERMISSION_REQUIRED: grant Location permission"))
        }
        do {
            let location = try await services.currentLocation(
                desiredAccuracy: desired,
                maxAgeMs: params.maxAgeMs,
                timeoutMs: params.timeoutMs)
            let isPrecise = await services.locationAccuracyAuthorization() == .fullAccuracy
            let payload = OpenClawLocationPayload(
                lat: location.coordinate.latitude,
                lon: location.coordinate.longitude,
                accuracyMeters: location.horizontalAccuracy,
                altitudeMeters: location.verticalAccuracy >= 0 ? location.altitude : nil,
                speedMps: location.speed >= 0 ? location.speed : nil,
                headingDeg: location.course >= 0 ? location.course : nil,
                timestamp: ISO8601DateFormatter().string(from: location.timestamp),
                isPrecise: isPrecise,
                source: nil)
            let json = try Self.encodePayload(payload)
            return BridgeInvokeResponse(id: req.id, ok: true, payloadJSON: json)
        } catch MacNodeLocationService.Error.timeout {
            return BridgeInvokeResponse(
                id: req.id,
                ok: false,
                error: OpenClawNodeError(
                    code: .unavailable,
                    message: "LOCATION_TIMEOUT: no fix in time"))
        } catch {
            return BridgeInvokeResponse(
                id: req.id,
                ok: false,
                error: OpenClawNodeError(
                    code: .unavailable,
                    message: "LOCATION_UNAVAILABLE: \(error.localizedDescription)"))
        }
    }

    private func handleScreenRecordInvoke(_ req: BridgeInvokeRequest) async throws -> BridgeInvokeResponse {
        let params = (try? Self.decodeParams(MacNodeScreenRecordParams.self, from: req.paramsJSON)) ??
            MacNodeScreenRecordParams()
        if let format = params.format?.lowercased(), !format.isEmpty, format != "mp4" {
            return Self.errorResponse(
                req,
                code: .invalidRequest,
                message: "INVALID_REQUEST: screen format must be mp4")
        }
        let services = await self.mainActorServices()
        let res = try await services.recordScreen(
            screenIndex: params.screenIndex,
            durationMs: params.durationMs,
            fps: params.fps,
            includeAudio: params.includeAudio,
            outPath: nil)
        defer { try? FileManager().removeItem(atPath: res.path) }
        let data = try Data(contentsOf: URL(fileURLWithPath: res.path))
        struct ScreenPayload: Encodable {
            var format: String
            var base64: String
            var durationMs: Int?
            var fps: Double?
            var screenIndex: Int?
            var hasAudio: Bool
        }
        let payload = try Self.encodePayload(ScreenPayload(
            format: "mp4",
            base64: data.base64EncodedString(),
            durationMs: params.durationMs,
            fps: params.fps,
            screenIndex: params.screenIndex,
            hasAudio: res.hasAudio))
        return BridgeInvokeResponse(id: req.id, ok: true, payloadJSON: payload)
    }

    private func mainActorServices() async -> any MacNodeRuntimeMainActorServices {
        if let cachedMainActorServices { return cachedMainActorServices }
        let services = await self.makeMainActorServices()
        self.cachedMainActorServices = services
        return services
    }

    private func handleA2UIReset(_ req: BridgeInvokeRequest) async throws -> BridgeInvokeResponse {
        try await self.ensureA2UIHost()

        let sessionKey = self.mainSessionKey
        let json = try await CanvasManager.shared.eval(sessionKey: sessionKey, javaScript: """
        (() => {
          const host = globalThis.openclawA2UI;
          if (!host) return JSON.stringify({ ok: false, error: "missing openclawA2UI" });
          return JSON.stringify(host.reset());
        })()
        """)
        return BridgeInvokeResponse(id: req.id, ok: true, payloadJSON: json)
    }

    private func handleA2UIPush(_ req: BridgeInvokeRequest) async throws -> BridgeInvokeResponse {
        let command = req.command
        let messages: [OpenClawKit.AnyCodable]
        if command == OpenClawCanvasA2UICommand.pushJSONL.rawValue {
            let params = try Self.decodeParams(OpenClawCanvasA2UIPushJSONLParams.self, from: req.paramsJSON)
            messages = try OpenClawCanvasA2UIJSONL.decodeMessagesFromJSONL(params.jsonl)
        } else {
            do {
                let params = try Self.decodeParams(OpenClawCanvasA2UIPushParams.self, from: req.paramsJSON)
                messages = params.messages
            } catch {
                let params = try Self.decodeParams(OpenClawCanvasA2UIPushJSONLParams.self, from: req.paramsJSON)
                messages = try OpenClawCanvasA2UIJSONL.decodeMessagesFromJSONL(params.jsonl)
            }
        }

        try await self.ensureA2UIHost()

        let messagesJSON = try OpenClawCanvasA2UIJSONL.encodeMessagesJSONArray(messages)
        let js = """
        (() => {
          try {
            const host = globalThis.openclawA2UI;
            if (!host) return JSON.stringify({ ok: false, error: "missing openclawA2UI" });
            const messages = \(messagesJSON);
            return JSON.stringify(host.applyMessages(messages));
          } catch (e) {
            return JSON.stringify({ ok: false, error: String(e?.message ?? e) });
          }
        })()
        """
        let sessionKey = self.mainSessionKey
        let resultJSON = try await CanvasManager.shared.eval(sessionKey: sessionKey, javaScript: js)
        return BridgeInvokeResponse(id: req.id, ok: true, payloadJSON: resultJSON)
    }

    private func ensureA2UIHost() async throws {
        if await self.isA2UIReady() { return }
        guard let a2uiUrl = await self.resolveA2UIHostUrl() else {
            throw NSError(domain: "Canvas", code: 30, userInfo: [
                NSLocalizedDescriptionKey: "A2UI_HOST_NOT_CONFIGURED: gateway did not advertise canvas host",
            ])
        }
        let sessionKey = self.mainSessionKey
        _ = try await MainActor.run {
            try CanvasManager.shared.show(sessionKey: sessionKey, path: a2uiUrl)
        }
        if await self.isA2UIReady(poll: true) { return }
        throw NSError(domain: "Canvas", code: 31, userInfo: [
            NSLocalizedDescriptionKey: "A2UI_HOST_UNAVAILABLE: A2UI host not reachable",
        ])
    }

    private func resolveA2UIHostUrl() async -> String? {
        guard let raw = await GatewayConnection.shared.canvasHostUrl() else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let baseUrl = URL(string: trimmed) else { return nil }
        return baseUrl.appendingPathComponent("__openclaw__/a2ui/").absoluteString + "?platform=macos"
    }

    private func isA2UIReady(poll: Bool = false) async -> Bool {
        let deadline = poll ? Date().addingTimeInterval(6.0) : Date()
        while true {
            do {
                let sessionKey = self.mainSessionKey
                let ready = try await CanvasManager.shared.eval(sessionKey: sessionKey, javaScript: """
                (() => {
                  const host = globalThis.openclawA2UI;
                  return String(Boolean(host));
                })()
                """)
                let trimmed = ready.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed == "true" { return true }
            } catch {
                // Ignore transient eval failures while the page is loading.
            }

            guard poll, Date() < deadline else { return false }
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
    }

    private func handleSystemRun(_ req: BridgeInvokeRequest) async throws -> BridgeInvokeResponse {
        let params = try Self.decodeParams(OpenClawSystemRunParams.self, from: req.paramsJSON)
        let command = params.command
        guard !command.isEmpty else {
            return Self.errorResponse(req, code: .invalidRequest, message: "INVALID_REQUEST: command required")
        }
        let sessionKey = (params.sessionKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? params.sessionKey!.trimmingCharacters(in: .whitespacesAndNewlines)
            : self.mainSessionKey
        let runId = UUID().uuidString
        let evaluation = await ExecApprovalEvaluator.evaluate(
            command: command,
            rawCommand: params.rawCommand,
            cwd: params.cwd,
            envOverrides: params.env,
            agentId: params.agentId)

        if evaluation.security == .deny {
            await self.emitExecEvent(
                "exec.denied",
                payload: ExecEventPayload(
                    sessionKey: sessionKey,
                    runId: runId,
                    host: "node",
                    command: evaluation.displayCommand,
                    reason: "security=deny"))
            return Self.errorResponse(
                req,
                code: .unavailable,
                message: "SYSTEM_RUN_DISABLED: security=deny")
        }

        let approval = await self.resolveSystemRunApproval(
            req: req,
            params: params,
            context: ExecRunContext(
                displayCommand: evaluation.displayCommand,
                security: evaluation.security,
                ask: evaluation.ask,
                agentId: evaluation.agentId,
                resolution: evaluation.resolution,
                allowlistMatch: evaluation.allowlistMatch,
                skillAllow: evaluation.skillAllow,
                sessionKey: sessionKey,
                runId: runId))
        if let response = approval.response { return response }
        let approvedByAsk = approval.approvedByAsk
        let persistAllowlist = approval.persistAllowlist
        self.persistAllowlistPatterns(
            persistAllowlist: persistAllowlist,
            security: evaluation.security,
            agentId: evaluation.agentId,
            command: command,
            allowlistResolutions: evaluation.allowlistResolutions)

        if evaluation.security == .allowlist, !evaluation.allowlistSatisfied, !evaluation.skillAllow, !approvedByAsk {
            await self.emitExecEvent(
                "exec.denied",
                payload: ExecEventPayload(
                    sessionKey: sessionKey,
                    runId: runId,
                    host: "node",
                    command: evaluation.displayCommand,
                    reason: "allowlist-miss"))
            return Self.errorResponse(
                req,
                code: .unavailable,
                message: "SYSTEM_RUN_DENIED: allowlist miss")
        }

        self.recordAllowlistMatches(
            security: evaluation.security,
            allowlistSatisfied: evaluation.allowlistSatisfied,
            agentId: evaluation.agentId,
            allowlistMatches: evaluation.allowlistMatches,
            allowlistResolutions: evaluation.allowlistResolutions,
            displayCommand: evaluation.displayCommand)

        if let permissionResponse = await self.validateScreenRecordingIfNeeded(
            req: req,
            needsScreenRecording: params.needsScreenRecording,
            sessionKey: sessionKey,
            runId: runId,
            displayCommand: evaluation.displayCommand)
        {
            return permissionResponse
        }

        return try await self.executeSystemRun(
            req: req,
            params: params,
            command: command,
            env: evaluation.env,
            sessionKey: sessionKey,
            runId: runId,
            displayCommand: evaluation.displayCommand)
    }

    private func handleSystemWhich(_ req: BridgeInvokeRequest) async throws -> BridgeInvokeResponse {
        let params = try Self.decodeParams(OpenClawSystemWhichParams.self, from: req.paramsJSON)
        let bins = params.bins
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !bins.isEmpty else {
            return Self.errorResponse(req, code: .invalidRequest, message: "INVALID_REQUEST: bins required")
        }

        let searchPaths = CommandResolver.preferredPaths()
        var matches: [String] = []
        var paths: [String: String] = [:]
        for bin in bins {
            if let path = CommandResolver.findExecutable(named: bin, searchPaths: searchPaths) {
                matches.append(bin)
                paths[bin] = path
            }
        }

        struct WhichPayload: Encodable {
            let bins: [String]
            let paths: [String: String]
        }
        let payload = try Self.encodePayload(WhichPayload(bins: matches, paths: paths))
        return BridgeInvokeResponse(id: req.id, ok: true, payloadJSON: payload)
    }

    private struct ExecApprovalOutcome {
        var approvedByAsk: Bool
        var persistAllowlist: Bool
        var response: BridgeInvokeResponse?
    }

    private struct ExecRunContext {
        var displayCommand: String
        var security: ExecSecurity
        var ask: ExecAsk
        var agentId: String?
        var resolution: ExecCommandResolution?
        var allowlistMatch: ExecAllowlistEntry?
        var skillAllow: Bool
        var sessionKey: String
        var runId: String
    }

    private func resolveSystemRunApproval(
        req: BridgeInvokeRequest,
        params: OpenClawSystemRunParams,
        context: ExecRunContext) async -> ExecApprovalOutcome
    {
        let requiresAsk = ExecApprovalHelpers.requiresAsk(
            ask: context.ask,
            security: context.security,
            allowlistMatch: context.allowlistMatch,
            skillAllow: context.skillAllow)

        let decisionFromParams = ExecApprovalHelpers.parseDecision(params.approvalDecision)
        var approvedByAsk = params.approved == true || decisionFromParams != nil
        var persistAllowlist = decisionFromParams == .allowAlways
        if decisionFromParams == .deny {
            await self.emitExecEvent(
                "exec.denied",
                payload: ExecEventPayload(
                    sessionKey: context.sessionKey,
                    runId: context.runId,
                    host: "node",
                    command: context.displayCommand,
                    reason: "user-denied"))
            return ExecApprovalOutcome(
                approvedByAsk: approvedByAsk,
                persistAllowlist: persistAllowlist,
                response: Self.errorResponse(
                    req,
                    code: .unavailable,
                    message: "SYSTEM_RUN_DENIED: user denied"))
        }

        if requiresAsk, !approvedByAsk {
            let decision = await MainActor.run {
                ExecApprovalsPromptPresenter.prompt(
                    ExecApprovalPromptRequest(
                        command: context.displayCommand,
                        cwd: params.cwd,
                        host: "node",
                        security: context.security.rawValue,
                        ask: context.ask.rawValue,
                        agentId: context.agentId,
                        resolvedPath: context.resolution?.resolvedPath,
                        sessionKey: context.sessionKey))
            }
            switch decision {
            case .deny:
                await self.emitExecEvent(
                    "exec.denied",
                    payload: ExecEventPayload(
                        sessionKey: context.sessionKey,
                        runId: context.runId,
                        host: "node",
                        command: context.displayCommand,
                        reason: "user-denied"))
                return ExecApprovalOutcome(
                    approvedByAsk: approvedByAsk,
                    persistAllowlist: persistAllowlist,
                    response: Self.errorResponse(
                        req,
                        code: .unavailable,
                        message: "SYSTEM_RUN_DENIED: user denied"))
            case .allowAlways:
                approvedByAsk = true
                persistAllowlist = true
            case .allowOnce:
                approvedByAsk = true
            }
        }

        return ExecApprovalOutcome(
            approvedByAsk: approvedByAsk,
            persistAllowlist: persistAllowlist,
            response: nil)
    }

    private func handleSystemExecApprovalsGet(_ req: BridgeInvokeRequest) async throws -> BridgeInvokeResponse {
        _ = ExecApprovalsStore.ensureFile()
        let snapshot = ExecApprovalsStore.readSnapshot()
        let redacted = ExecApprovalsSnapshot(
            path: snapshot.path,
            exists: snapshot.exists,
            hash: snapshot.hash,
            file: ExecApprovalsStore.redactForSnapshot(snapshot.file))
        let payload = try Self.encodePayload(redacted)
        return BridgeInvokeResponse(id: req.id, ok: true, payloadJSON: payload)
    }

    private func handleSystemExecApprovalsSet(_ req: BridgeInvokeRequest) async throws -> BridgeInvokeResponse {
        struct SetParams: Decodable {
            var file: ExecApprovalsFile
            var baseHash: String?
        }

        let params = try Self.decodeParams(SetParams.self, from: req.paramsJSON)
        let current = ExecApprovalsStore.ensureFile()
        let snapshot = ExecApprovalsStore.readSnapshot()
        if snapshot.exists {
            if snapshot.hash.isEmpty {
                return Self.errorResponse(
                    req,
                    code: .invalidRequest,
                    message: "INVALID_REQUEST: exec approvals base hash unavailable; reload and retry")
            }
            let baseHash = params.baseHash?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if baseHash.isEmpty {
                return Self.errorResponse(
                    req,
                    code: .invalidRequest,
                    message: "INVALID_REQUEST: exec approvals base hash required; reload and retry")
            }
            if baseHash != snapshot.hash {
                return Self.errorResponse(
                    req,
                    code: .invalidRequest,
                    message: "INVALID_REQUEST: exec approvals changed; reload and retry")
            }
        }

        var normalized = ExecApprovalsStore.normalizeIncoming(params.file)
        let socketPath = normalized.socket?.path?.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = normalized.socket?.token?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedPath = (socketPath?.isEmpty == false)
            ? socketPath!
            : current.socket?.path?.trimmingCharacters(in: .whitespacesAndNewlines) ??
            ExecApprovalsStore.socketPath()
        let resolvedToken = (token?.isEmpty == false)
            ? token!
            : current.socket?.token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        normalized.socket = ExecApprovalsSocketConfig(path: resolvedPath, token: resolvedToken)

        ExecApprovalsStore.saveFile(normalized)
        let nextSnapshot = ExecApprovalsStore.readSnapshot()
        let redacted = ExecApprovalsSnapshot(
            path: nextSnapshot.path,
            exists: nextSnapshot.exists,
            hash: nextSnapshot.hash,
            file: ExecApprovalsStore.redactForSnapshot(nextSnapshot.file))
        let payload = try Self.encodePayload(redacted)
        return BridgeInvokeResponse(id: req.id, ok: true, payloadJSON: payload)
    }

    private func emitExecEvent(_ event: String, payload: ExecEventPayload) async {
        guard let sender = self.eventSender else { return }
        guard let data = try? JSONEncoder().encode(payload),
              let json = String(data: data, encoding: .utf8)
        else {
            return
        }
        await sender(event, json)
    }

    private func handleSystemNotify(_ req: BridgeInvokeRequest) async throws -> BridgeInvokeResponse {
        let params = try Self.decodeParams(OpenClawSystemNotifyParams.self, from: req.paramsJSON)
        let title = params.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = params.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty, body.isEmpty {
            return Self.errorResponse(req, code: .invalidRequest, message: "INVALID_REQUEST: empty notification")
        }

        let priority = params.priority.flatMap { NotificationPriority(rawValue: $0.rawValue) }
        let delivery = params.delivery.flatMap { NotificationDelivery(rawValue: $0.rawValue) } ?? .system
        let manager = NotificationManager()

        switch delivery {
        case .system:
            let ok = await manager.send(
                title: title,
                body: body,
                sound: params.sound,
                priority: priority)
            return ok
                ? BridgeInvokeResponse(id: req.id, ok: true)
                : Self.errorResponse(req, code: .unavailable, message: "NOT_AUTHORIZED: notifications")
        case .overlay:
            await NotifyOverlayController.shared.present(title: title, body: body)
            return BridgeInvokeResponse(id: req.id, ok: true)
        case .auto:
            let ok = await manager.send(
                title: title,
                body: body,
                sound: params.sound,
                priority: priority)
            if ok {
                return BridgeInvokeResponse(id: req.id, ok: true)
            }
            await NotifyOverlayController.shared.present(title: title, body: body)
            return BridgeInvokeResponse(id: req.id, ok: true)
        }
    }

    private func handleSystemScreenshot(_ req: BridgeInvokeRequest) async throws -> BridgeInvokeResponse {
        let authorized = await PermissionManager.status([.screenRecording])[.screenRecording] ?? false
        guard authorized else {
            return Self.errorResponse(
                req,
                code: .unavailable,
                message: "PERMISSION_MISSING: screenRecording")
        }

        let params = (try? Self.decodeParams(OpenClawSystemScreenshotParams.self, from: req.paramsJSON)) ??
            OpenClawSystemScreenshotParams()
        let screen = try await self.resolveScreenDescriptor(index: params.screenIndex)
        guard let cgImage = CGDisplayCreateImage(screen.displayID) else {
            return Self.errorResponse(
                req,
                code: .unavailable,
                message: "SCREENSHOT_FAILED: unable to capture display")
        }

        let image = NSImage(
            cgImage: cgImage,
            size: NSSize(width: screen.frame.width, height: screen.frame.height))
        let format = params.format ?? .jpeg
        let maxWidth = Self.normalizedScreenshotMaxWidth(
            params.maxWidth,
            fallback: Int(screen.frame.width.rounded(.down)))
        let quality = params.quality ?? 0.9
        let encoded = try Self.encodeCanvasSnapshot(
            image: image,
            format: format,
            maxWidth: maxWidth,
            quality: quality)
        let size = try Self.encodedImagePixelSize(encoded)

        struct ScreenshotPayload: Encodable {
            var format: String
            var base64: String
            var width: Int
            var height: Int
            var coordinateWidth: Double
            var coordinateHeight: Double
            var screenIndex: Int
            var screenOriginX: Double
            var screenOriginY: Double
            var inputOrigin: String
        }

        let payload = try Self.encodePayload(ScreenshotPayload(
            format: format == .jpeg ? "jpeg" : "png",
            base64: encoded.base64EncodedString(),
            width: size.width,
            height: size.height,
            coordinateWidth: screen.frame.width,
            coordinateHeight: screen.frame.height,
            screenIndex: screen.index,
            screenOriginX: screen.frame.minX,
            screenOriginY: screen.frame.minY,
            inputOrigin: OpenClawComputerInputOrigin.topLeft.rawValue))
        return BridgeInvokeResponse(id: req.id, ok: true, payloadJSON: payload)
    }

    private func handleSystemMouse(_ req: BridgeInvokeRequest) async throws -> BridgeInvokeResponse {
        let authorized = await PermissionManager.status([.accessibility])[.accessibility] ?? false
        guard authorized else {
            return Self.errorResponse(
                req,
                code: .unavailable,
                message: "PERMISSION_MISSING: accessibility")
        }

        let params = try Self.decodeParams(OpenClawSystemMouseParams.self, from: req.paramsJSON)
        switch params.action {
        case .scroll:
            if params.x != nil, params.y != nil {
                let screen = try await self.resolveScreenDescriptor(index: params.screenIndex)
                let point = try await self.resolveMousePoint(params: params, screen: screen)
                try self.warpMouse(to: point)
            }
            let deltaX = Int32((params.deltaX ?? 0).rounded())
            let deltaY = Int32((params.deltaY ?? 0).rounded())
            guard deltaX != 0 || deltaY != 0 else {
                return Self.errorResponse(
                    req,
                    code: .invalidRequest,
                    message: "INVALID_REQUEST: deltaX or deltaY required for scroll")
            }
            guard let event = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 2,
                wheel1: deltaY,
                wheel2: deltaX,
                wheel3: 0)
            else {
                return Self.errorResponse(
                    req,
                    code: .unavailable,
                    message: "MOUSE_EVENT_FAILED: unable to create scroll event")
            }
            event.post(tap: .cghidEventTap)
        case .move, .click, .doubleClick, .down, .up:
            let screen = try await self.resolveScreenDescriptor(index: params.screenIndex)
            let point = try await self.resolveMousePoint(params: params, screen: screen)
            let button = params.button ?? .left
            try self.warpMouse(to: point)

            switch params.action {
            case .move:
                try self.postMouseEvent(type: .mouseMoved, point: point, button: button)
            case .click:
                try await self.postMouseClick(at: point, button: button, count: 1)
            case .doubleClick:
                try await self.postMouseClick(at: point, button: button, count: 2)
            case .down:
                try self.postMouseEvent(type: Self.mouseDownType(for: button), point: point, button: button)
            case .up:
                try self.postMouseEvent(type: Self.mouseUpType(for: button), point: point, button: button)
            case .scroll:
                break
            }
        }

        struct MousePayload: Encodable {
            var ok: Bool
        }
        let payload = try Self.encodePayload(MousePayload(ok: true))
        return BridgeInvokeResponse(id: req.id, ok: true, payloadJSON: payload)
    }

    private func handleSystemType(_ req: BridgeInvokeRequest) async throws -> BridgeInvokeResponse {
        let authorized = await PermissionManager.status([.accessibility])[.accessibility] ?? false
        guard authorized else {
            return Self.errorResponse(
                req,
                code: .unavailable,
                message: "PERMISSION_MISSING: accessibility")
        }

        let params = try Self.decodeParams(OpenClawSystemTypeParams.self, from: req.paramsJSON)
        let text = params.text
        guard !text.isEmpty else {
            return Self.errorResponse(req, code: .invalidRequest, message: "INVALID_REQUEST: text required")
        }

        try self.postKeyboardText(text)
        let payload = try Self.encodePayload(["ok": true])
        return BridgeInvokeResponse(id: req.id, ok: true, payloadJSON: payload)
    }

    private func handleSystemKeypress(_ req: BridgeInvokeRequest) async throws -> BridgeInvokeResponse {
        let authorized = await PermissionManager.status([.accessibility])[.accessibility] ?? false
        guard authorized else {
            return Self.errorResponse(
                req,
                code: .unavailable,
                message: "PERMISSION_MISSING: accessibility")
        }

        let params = try Self.decodeParams(OpenClawSystemKeypressParams.self, from: req.paramsJSON)
        let key = params.key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            return Self.errorResponse(req, code: .invalidRequest, message: "INVALID_REQUEST: key required")
        }

        let modifiers = params.modifiers ?? []
        if let keyCode = Self.keyCode(for: key) {
            try self.postKeyCode(keyCode, modifiers: modifiers)
        } else if modifiers.isEmpty {
            try self.postKeyboardText(key)
        } else {
            return Self.errorResponse(
                req,
                code: .invalidRequest,
                message: "INVALID_REQUEST: unsupported key '\(key)' for modified keypress")
        }

        let payload = try Self.encodePayload(["ok": true])
        return BridgeInvokeResponse(id: req.id, ok: true, payloadJSON: payload)
    }

    private struct ScreenDescriptor {
        var index: Int
        var frame: CGRect
        var displayID: CGDirectDisplayID
    }

    private func resolveScreenDescriptor(index: Int?) async throws -> ScreenDescriptor {
        let screens = await MainActor.run { NSScreen.screens }
        guard !screens.isEmpty else {
            throw NSError(domain: "Node", code: 40, userInfo: [
                NSLocalizedDescriptionKey: "No screens available",
            ])
        }

        let resolvedIndex = min(max(index ?? 0, 0), screens.count - 1)
        let screen = screens[resolvedIndex]
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            throw NSError(domain: "Node", code: 41, userInfo: [
                NSLocalizedDescriptionKey: "Unable to resolve display identifier",
            ])
        }
        return ScreenDescriptor(
            index: resolvedIndex,
            frame: screen.frame,
            displayID: CGDirectDisplayID(number.uint32Value))
    }

    private func resolveMousePoint(
        params: OpenClawSystemMouseParams,
        screen: ScreenDescriptor) async throws -> CGPoint
    {
        guard let rawX = params.x, let rawY = params.y else {
            throw NSError(domain: "Node", code: 42, userInfo: [
                NSLocalizedDescriptionKey: "x and y are required",
            ])
        }

        let scaleX = (params.fromWidth ?? 0) > 0 ? screen.frame.width / params.fromWidth! : 1.0
        let scaleY = (params.fromHeight ?? 0) > 0 ? screen.frame.height / params.fromHeight! : 1.0
        let localX = min(max(0, rawX * scaleX), max(0, screen.frame.width - 1))
        let localY = min(max(0, rawY * scaleY), max(0, screen.frame.height - 1))
        let origin = params.origin ?? .topLeft
        let desktopTop = await self.desktopTopEdge()

        let globalX = screen.frame.minX + localX
        let globalYBottomLeft = switch origin {
        case .topLeft:
            screen.frame.maxY - localY
        case .bottomLeft:
            screen.frame.minY + localY
        }
        return CGPoint(x: globalX, y: desktopTop - globalYBottomLeft)
    }

    private func desktopTopEdge() async -> Double {
        await MainActor.run {
            NSScreen.screens.map { $0.frame.maxY }.max() ?? 0
        }
    }

    private func warpMouse(to point: CGPoint) throws {
        let result = CGWarpMouseCursorPosition(point)
        guard result == .success else {
            throw NSError(domain: "Node", code: 43, userInfo: [
                NSLocalizedDescriptionKey: "Unable to move mouse cursor",
            ])
        }
    }

    private func postMouseEvent(
        type: CGEventType,
        point: CGPoint,
        button: OpenClawSystemMouseButton,
        clickState: Int64 = 1) throws
    {
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: Self.mouseButton(for: button))
        else {
            throw NSError(domain: "Node", code: 44, userInfo: [
                NSLocalizedDescriptionKey: "Unable to create mouse event",
            ])
        }
        event.setIntegerValueField(.mouseEventClickState, value: clickState)
        event.post(tap: .cghidEventTap)
    }

    private func postMouseClick(
        at point: CGPoint,
        button: OpenClawSystemMouseButton,
        count: Int) async throws
    {
        for clickIndex in 1...max(1, count) {
            try self.postMouseEvent(
                type: Self.mouseDownType(for: button),
                point: point,
                button: button,
                clickState: Int64(clickIndex))
            try self.postMouseEvent(
                type: Self.mouseUpType(for: button),
                point: point,
                button: button,
                clickState: Int64(clickIndex))
            if clickIndex < count {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }

    private func postKeyboardText(_ text: String) throws {
        let utf16 = Array(text.utf16)
        guard !utf16.isEmpty else { return }
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
        else {
            throw NSError(domain: "Node", code: 45, userInfo: [
                NSLocalizedDescriptionKey: "Unable to create keyboard event",
            ])
        }
        keyDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        keyUp.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func postKeyCode(_ keyCode: CGKeyCode, modifiers: [OpenClawSystemKeyModifier]) throws {
        let flags = Self.keyFlags(for: modifiers)
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
        else {
            throw NSError(domain: "Node", code: 46, userInfo: [
                NSLocalizedDescriptionKey: "Unable to create keyboard shortcut event",
            ])
        }
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private static func mouseButton(for button: OpenClawSystemMouseButton) -> CGMouseButton {
        switch button {
        case .left:
            .left
        case .right:
            .right
        case .center:
            .center
        }
    }

    private static func mouseDownType(for button: OpenClawSystemMouseButton) -> CGEventType {
        switch button {
        case .left:
            .leftMouseDown
        case .right:
            .rightMouseDown
        case .center:
            .otherMouseDown
        }
    }

    private static func mouseUpType(for button: OpenClawSystemMouseButton) -> CGEventType {
        switch button {
        case .left:
            .leftMouseUp
        case .right:
            .rightMouseUp
        case .center:
            .otherMouseUp
        }
    }

    private static func keyFlags(for modifiers: [OpenClawSystemKeyModifier]) -> CGEventFlags {
        modifiers.reduce(into: CGEventFlags()) { flags, modifier in
            switch modifier {
            case .command:
                flags.insert(.maskCommand)
            case .shift:
                flags.insert(.maskShift)
            case .option:
                flags.insert(.maskAlternate)
            case .control:
                flags.insert(.maskControl)
            case .fn:
                flags.insert(.maskSecondaryFn)
            }
        }
    }

    private static func keyCode(for key: String) -> CGKeyCode? {
        Self.keyCodes[key.lowercased()]
    }

    private static let keyCodes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19,
        "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28,
        "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "enter": 36,
        "return": 36, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43,
        "/": 44, "n": 45, "m": 46, ".": 47, "tab": 48, "space": 49, "`": 50,
        "backspace": 51, "delete": 51, "escape": 53, "esc": 53, "command": 55, "shift": 56,
        "capslock": 57, "option": 58, "alt": 58, "control": 59, "ctrl": 59, "rightshift": 60,
        "rightoption": 61, "rightalt": 61, "rightcontrol": 62, "fn": 63, "left": 123,
        "right": 124, "down": 125, "up": 126, "home": 115, "end": 119, "pageup": 116,
        "pagedown": 121,
    ]
}

extension MacNodeRuntime {
    private func persistAllowlistPatterns(
        persistAllowlist: Bool,
        security: ExecSecurity,
        agentId: String?,
        command: [String],
        allowlistResolutions: [ExecCommandResolution])
    {
        guard persistAllowlist, security == .allowlist else { return }
        var seenPatterns = Set<String>()
        for candidate in allowlistResolutions {
            guard let pattern = ExecApprovalHelpers.allowlistPattern(command: command, resolution: candidate) else {
                continue
            }
            if seenPatterns.insert(pattern).inserted {
                ExecApprovalsStore.addAllowlistEntry(agentId: agentId, pattern: pattern)
            }
        }
    }

    private func recordAllowlistMatches(
        security: ExecSecurity,
        allowlistSatisfied: Bool,
        agentId: String?,
        allowlistMatches: [ExecAllowlistEntry],
        allowlistResolutions: [ExecCommandResolution],
        displayCommand: String)
    {
        guard security == .allowlist, allowlistSatisfied else { return }
        var seenPatterns = Set<String>()
        for (idx, match) in allowlistMatches.enumerated() {
            if !seenPatterns.insert(match.pattern).inserted {
                continue
            }
            let resolvedPath = idx < allowlistResolutions.count ? allowlistResolutions[idx].resolvedPath : nil
            ExecApprovalsStore.recordAllowlistUse(
                agentId: agentId,
                pattern: match.pattern,
                command: displayCommand,
                resolvedPath: resolvedPath)
        }
    }

    private func validateScreenRecordingIfNeeded(
        req: BridgeInvokeRequest,
        needsScreenRecording: Bool?,
        sessionKey: String,
        runId: String,
        displayCommand: String) async -> BridgeInvokeResponse?
    {
        guard needsScreenRecording == true else { return nil }
        let authorized = await PermissionManager
            .status([.screenRecording])[.screenRecording] ?? false
        if authorized {
            return nil
        }
        await self.emitExecEvent(
            "exec.denied",
            payload: ExecEventPayload(
                sessionKey: sessionKey,
                runId: runId,
                host: "node",
                command: displayCommand,
                reason: "permission:screenRecording"))
        return Self.errorResponse(
            req,
            code: .unavailable,
            message: "PERMISSION_MISSING: screenRecording")
    }

    private func executeSystemRun(
        req: BridgeInvokeRequest,
        params: OpenClawSystemRunParams,
        command: [String],
        env: [String: String],
        sessionKey: String,
        runId: String,
        displayCommand: String) async throws -> BridgeInvokeResponse
    {
        let timeoutSec = params.timeoutMs.flatMap { Double($0) / 1000.0 }
        await self.emitExecEvent(
            "exec.started",
            payload: ExecEventPayload(
                sessionKey: sessionKey,
                runId: runId,
                host: "node",
                command: displayCommand))
        let result = await ShellExecutor.runDetailed(
            command: command,
            cwd: params.cwd,
            env: env,
            timeout: timeoutSec)
        let combined = [result.stdout, result.stderr, result.errorMessage]
            .compactMap(\.self)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        await self.emitExecEvent(
            "exec.finished",
            payload: ExecEventPayload(
                sessionKey: sessionKey,
                runId: runId,
                host: "node",
                command: displayCommand,
                exitCode: result.exitCode,
                timedOut: result.timedOut,
                success: result.success,
                output: ExecEventPayload.truncateOutput(combined)))

        struct RunPayload: Encodable {
            var exitCode: Int?
            var timedOut: Bool
            var success: Bool
            var stdout: String
            var stderr: String
            var error: String?
        }
        let runPayload = RunPayload(
            exitCode: result.exitCode,
            timedOut: result.timedOut,
            success: result.success,
            stdout: result.stdout,
            stderr: result.stderr,
            error: result.errorMessage)
        let payload = try Self.encodePayload(runPayload)
        return BridgeInvokeResponse(id: req.id, ok: true, payloadJSON: payload)
    }

    private static func decodeParams<T: Decodable>(_ type: T.Type, from json: String?) throws -> T {
        guard let json, let data = json.data(using: .utf8) else {
            throw NSError(domain: "Gateway", code: 20, userInfo: [
                NSLocalizedDescriptionKey: "INVALID_REQUEST: paramsJSON required",
            ])
        }
        return try JSONDecoder().decode(type, from: data)
    }

    private static func encodePayload(_ obj: some Encodable) throws -> String {
        let data = try JSONEncoder().encode(obj)
        guard let json = String(bytes: data, encoding: .utf8) else {
            throw NSError(domain: "Node", code: 21, userInfo: [
                NSLocalizedDescriptionKey: "Failed to encode payload as UTF-8",
            ])
        }
        return json
    }

    private nonisolated static func canvasEnabled() -> Bool {
        UserDefaults.standard.object(forKey: canvasEnabledKey) as? Bool ?? true
    }

    private nonisolated static func cameraEnabled() -> Bool {
        UserDefaults.standard.object(forKey: cameraEnabledKey) as? Bool ?? false
    }

    private nonisolated static func locationMode() -> OpenClawLocationMode {
        let raw = UserDefaults.standard.string(forKey: locationModeKey) ?? "off"
        return OpenClawLocationMode(rawValue: raw) ?? .off
    }

    private nonisolated static func locationPreciseEnabled() -> Bool {
        if UserDefaults.standard.object(forKey: locationPreciseKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: locationPreciseKey)
    }

    private static func errorResponse(
        _ req: BridgeInvokeRequest,
        code: OpenClawNodeErrorCode,
        message: String) -> BridgeInvokeResponse
    {
        BridgeInvokeResponse(
            id: req.id,
            ok: false,
            error: OpenClawNodeError(code: code, message: message))
    }

    private static func encodeCanvasSnapshot(
        image: NSImage,
        format: OpenClawCanvasSnapshotFormat,
        maxWidth: Int?,
        quality: Double) throws -> Data
    {
        let source = Self.scaleImage(image, maxWidth: maxWidth) ?? image
        guard let tiff = source.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff)
        else {
            throw NSError(domain: "Canvas", code: 22, userInfo: [
                NSLocalizedDescriptionKey: "snapshot encode failed",
            ])
        }

        switch format {
        case .png:
            guard let data = rep.representation(using: .png, properties: [:]) else {
                throw NSError(domain: "Canvas", code: 23, userInfo: [
                    NSLocalizedDescriptionKey: "png encode failed",
                ])
            }
            return data
        case .jpeg:
            let clamped = min(1.0, max(0.05, quality))
            guard let data = rep.representation(
                using: .jpeg,
                properties: [.compressionFactor: clamped])
            else {
                throw NSError(domain: "Canvas", code: 24, userInfo: [
                    NSLocalizedDescriptionKey: "jpeg encode failed",
                ])
            }
            return data
        }
    }

    private static func normalizedScreenshotMaxWidth(_ maxWidth: Int?, fallback: Int) -> Int? {
        guard let maxWidth else { return max(1, fallback) }
        return maxWidth > 0 ? maxWidth : max(1, fallback)
    }

    private static func encodedImagePixelSize(_ data: Data) throws -> (width: Int, height: Int) {
        guard let rep = NSBitmapImageRep(data: data) else {
            throw NSError(domain: "Node", code: 47, userInfo: [
                NSLocalizedDescriptionKey: "Unable to inspect encoded screenshot",
            ])
        }
        return (rep.pixelsWide, rep.pixelsHigh)
    }

    private static func scaleImage(_ image: NSImage, maxWidth: Int?) -> NSImage? {
        guard let maxWidth, maxWidth > 0 else { return image }
        let size = image.size
        guard size.width > 0, size.width > CGFloat(maxWidth) else { return image }
        let scale = CGFloat(maxWidth) / size.width
        let target = NSSize(width: CGFloat(maxWidth), height: size.height * scale)

        let out = NSImage(size: target)
        out.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: target),
            from: NSRect(origin: .zero, size: size),
            operation: .copy,
            fraction: 1.0)
        out.unlockFocus()
        return out
    }
}
