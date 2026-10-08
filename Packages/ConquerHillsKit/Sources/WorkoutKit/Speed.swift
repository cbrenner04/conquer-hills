/// A treadmill belt speed. Entered and displayed in mph; the engine works in meters per second.
public struct Speed: Equatable, Hashable, Comparable, Sendable, Codable {
    public static let metersPerSecondPerMph = 0.44704

    /// The Peloton Tread's range and step.
    public static let minimumMph = 0.5
    public static let maximumMph = 12.5
    public static let stepMph = 0.1

    /// Speed in mph, rounded to 0.1 and limited to the treadmill's range.
    public let mph: Double

    public var metersPerSecond: Double { mph * Self.metersPerSecondPerMph }

    /// A speed as set on the treadmill: rounded to the nearest 0.1 mph and clamped to 0.5–12.5 mph.
    public static func mph(_ mph: Double) -> Speed {
        Speed(mph: mph)
    }

    private init(mph: Double) {
        let tenths = (mph / Self.stepMph).rounded()
        self.mph = min(max(tenths * Self.stepMph, Self.minimumMph), Self.maximumMph)
    }

    /// This speed changed by a number of 0.1 mph steps, staying within range.
    public func stepped(by steps: Int) -> Speed {
        .mph(mph + Double(steps) * Self.stepMph)
    }

    public static func < (lhs: Speed, rhs: Speed) -> Bool { lhs.mph < rhs.mph }

    public init(from decoder: any Decoder) throws {
        self.init(mph: try decoder.singleValueContainer().decode(Double.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(mph)
    }
}
