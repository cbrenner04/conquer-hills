import Foundation

/// Display formatting for run values. Data and logic use meters; the UI shows miles, mph, and feet.
public enum RunFormatting {
    public static let metersPerMile = 1609.344
    public static let feetPerMeter = 3.28084

    /// "1.49 mi"
    public static func miles(_ meters: Double, decimals: Int = 2) -> String {
        String(format: "%.\(decimals)f mi", meters / metersPerMile)
    }

    /// "1.49": miles without the unit, for ranges like "mi 13.1–26.2".
    public static func mileNumber(_ meters: Double, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f", meters / metersPerMile)
    }

    /// "6.0 mph"
    public static func speed(_ speed: Speed) -> String {
        String(format: "%.1f mph", speed.mph)
    }

    /// "6.5%"
    public static func incline(_ percent: Double) -> String {
        String(format: "%.1f%%", percent)
    }

    /// "246 ft"
    public static func feet(_ meters: Double) -> String {
        "\(Int((meters * feetPerMeter).rounded())) ft"
    }

    /// "4:52" under an hour, "1:02:03" from an hour. Whole seconds, rounded down.
    public static func duration(_ duration: Duration) -> String {
        let total = max(0, Int(duration.seconds.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}
