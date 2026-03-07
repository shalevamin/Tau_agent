import Foundation

public enum OpenClawSystemCommand: String, Codable, Sendable {
    case run = "system.run"
    case which = "system.which"
    case notify = "system.notify"
    case screenshot = "system.screenshot"
    case mouse = "system.mouse"
    case type = "system.type"
    case keypress = "system.keypress"
    case execApprovalsGet = "system.execApprovals.get"
    case execApprovalsSet = "system.execApprovals.set"
}

public enum OpenClawNotificationPriority: String, Codable, Sendable {
    case passive
    case active
    case timeSensitive
}

public enum OpenClawNotificationDelivery: String, Codable, Sendable {
    case system
    case overlay
    case auto
}

public struct OpenClawSystemRunParams: Codable, Sendable, Equatable {
    public var command: [String]
    public var rawCommand: String?
    public var cwd: String?
    public var env: [String: String]?
    public var timeoutMs: Int?
    public var needsScreenRecording: Bool?
    public var agentId: String?
    public var sessionKey: String?
    public var approved: Bool?
    public var approvalDecision: String?

    public init(
        command: [String],
        rawCommand: String? = nil,
        cwd: String? = nil,
        env: [String: String]? = nil,
        timeoutMs: Int? = nil,
        needsScreenRecording: Bool? = nil,
        agentId: String? = nil,
        sessionKey: String? = nil,
        approved: Bool? = nil,
        approvalDecision: String? = nil)
    {
        self.command = command
        self.rawCommand = rawCommand
        self.cwd = cwd
        self.env = env
        self.timeoutMs = timeoutMs
        self.needsScreenRecording = needsScreenRecording
        self.agentId = agentId
        self.sessionKey = sessionKey
        self.approved = approved
        self.approvalDecision = approvalDecision
    }
}

public struct OpenClawSystemWhichParams: Codable, Sendable, Equatable {
    public var bins: [String]

    public init(bins: [String]) {
        self.bins = bins
    }
}

public struct OpenClawSystemNotifyParams: Codable, Sendable, Equatable {
    public var title: String
    public var body: String
    public var sound: String?
    public var priority: OpenClawNotificationPriority?
    public var delivery: OpenClawNotificationDelivery?

    public init(
        title: String,
        body: String,
        sound: String? = nil,
        priority: OpenClawNotificationPriority? = nil,
        delivery: OpenClawNotificationDelivery? = nil)
    {
        self.title = title
        self.body = body
        self.sound = sound
        self.priority = priority
        self.delivery = delivery
    }
}

public enum OpenClawComputerInputOrigin: String, Codable, Sendable {
    case topLeft
    case bottomLeft
}

public enum OpenClawSystemMouseAction: String, Codable, Sendable {
    case move
    case click
    case doubleClick
    case down
    case up
    case scroll
}

public enum OpenClawSystemMouseButton: String, Codable, Sendable {
    case left
    case right
    case center
}

public enum OpenClawSystemKeyModifier: String, Codable, Sendable {
    case command
    case shift
    case option
    case control
    case fn
}

public struct OpenClawSystemScreenshotParams: Codable, Sendable, Equatable {
    public var screenIndex: Int?
    public var maxWidth: Int?
    public var quality: Double?
    public var format: OpenClawCanvasSnapshotFormat?

    public init(
        screenIndex: Int? = nil,
        maxWidth: Int? = nil,
        quality: Double? = nil,
        format: OpenClawCanvasSnapshotFormat? = nil)
    {
        self.screenIndex = screenIndex
        self.maxWidth = maxWidth
        self.quality = quality
        self.format = format
    }
}

public struct OpenClawSystemMouseParams: Codable, Sendable, Equatable {
    public var action: OpenClawSystemMouseAction
    public var x: Double?
    public var y: Double?
    public var screenIndex: Int?
    public var origin: OpenClawComputerInputOrigin?
    public var button: OpenClawSystemMouseButton?
    public var deltaX: Double?
    public var deltaY: Double?
    public var fromWidth: Double?
    public var fromHeight: Double?

    public init(
        action: OpenClawSystemMouseAction,
        x: Double? = nil,
        y: Double? = nil,
        screenIndex: Int? = nil,
        origin: OpenClawComputerInputOrigin? = nil,
        button: OpenClawSystemMouseButton? = nil,
        deltaX: Double? = nil,
        deltaY: Double? = nil,
        fromWidth: Double? = nil,
        fromHeight: Double? = nil)
    {
        self.action = action
        self.x = x
        self.y = y
        self.screenIndex = screenIndex
        self.origin = origin
        self.button = button
        self.deltaX = deltaX
        self.deltaY = deltaY
        self.fromWidth = fromWidth
        self.fromHeight = fromHeight
    }
}

public struct OpenClawSystemTypeParams: Codable, Sendable, Equatable {
    public var text: String

    public init(text: String) {
        self.text = text
    }
}

public struct OpenClawSystemKeypressParams: Codable, Sendable, Equatable {
    public var key: String
    public var modifiers: [OpenClawSystemKeyModifier]?

    public init(key: String, modifiers: [OpenClawSystemKeyModifier]? = nil) {
        self.key = key
        self.modifiers = modifiers
    }
}
