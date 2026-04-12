import Foundation

public enum MonitorFreshnessStage: String, Codable, Sendable {
    case live
    case cooling
    case recentIdle
    case staleHidden
    case expired
}

public struct MonitorFreshnessPolicy: Codable, Equatable, Sendable {
    public let liveStateWindow: TimeInterval
    public let coolingIdleWindow: TimeInterval
    public let visibleIdleWindow: TimeInterval
    public let statusUnavailableWindow: TimeInterval

    public init(
        liveStateWindow: TimeInterval,
        coolingIdleWindow: TimeInterval,
        visibleIdleWindow: TimeInterval,
        statusUnavailableWindow: TimeInterval
    ) {
        self.liveStateWindow = liveStateWindow
        self.coolingIdleWindow = coolingIdleWindow
        self.visibleIdleWindow = visibleIdleWindow
        self.statusUnavailableWindow = statusUnavailableWindow
    }

    public static let v02Smooth = MonitorFreshnessPolicy(
        liveStateWindow: 3 * 60,
        coolingIdleWindow: 12 * 60,
        visibleIdleWindow: 25 * 60,
        statusUnavailableWindow: 45 * 60
    )

    public func stage(lastSignalAt: Date?, now: Date) -> MonitorFreshnessStage {
        guard let lastSignalAt else {
            return .expired
        }

        let age = max(0, now.timeIntervalSince(lastSignalAt))
        if age <= liveStateWindow {
            return .live
        }
        if age <= coolingIdleWindow {
            return .cooling
        }
        if age <= visibleIdleWindow {
            return .recentIdle
        }
        if age <= statusUnavailableWindow {
            return .staleHidden
        }
        return .expired
    }

    public func freshnessScore(lastSignalAt: Date?, now: Date) -> Double {
        guard let lastSignalAt else {
            return 0
        }

        let age = max(0, now.timeIntervalSince(lastSignalAt))
        if statusUnavailableWindow <= 0 {
            return 0
        }
        return max(0, min(1, 1 - (age / statusUnavailableWindow)))
    }
}
