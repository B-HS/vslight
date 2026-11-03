import Foundation

enum VolumeFormatter {
    static func percent(_ value: Double, decimals: Int) -> String {
        let clamped = min(max(value, 0), 1)
        let digits = max(0, min(decimals, 3))
        return String(format: "%.\(digits)f", clamped * 100)
    }

    static func parsePercent(_ text: String) -> Double? {
        let normalized = text
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(normalized), value.isFinite else {
            return nil
        }
        return min(max(value / 100, 0), 1)
    }
}
