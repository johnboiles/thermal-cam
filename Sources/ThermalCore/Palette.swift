import Foundation

public enum ThermalPalette: String, CaseIterable, Identifiable, Sendable {
    case iron = "Iron"
    case inferno = "Inferno"
    case whiteHot = "White Hot"
    case blackHot = "Black Hot"
    case rainbow = "Rainbow"

    public var id: String { rawValue }

    /// Returns an RGBA image. Color limits follow the current frame's measured
    /// temperature range, matching the auto-ranging behavior of handheld imagers.
    public func rgbaPixels(for frame: ThermalFrame) -> [UInt8] {
        let low = frame.minimumCelsius
        let span = max(frame.maximumCelsius - low, 0.001)
        var output = [UInt8](repeating: 0, count: frame.temperaturesCelsius.count * 4)

        for (index, temperature) in frame.temperaturesCelsius.enumerated() {
            let normalized = min(max((temperature - low) / span, 0), 1)
            let color = color(at: normalized)
            let offset = index * 4
            output[offset] = color.0
            output[offset + 1] = color.1
            output[offset + 2] = color.2
            output[offset + 3] = 255
        }
        return output
    }

    private func color(at value: Float) -> (UInt8, UInt8, UInt8) {
        switch self {
        case .whiteHot:
            let v = byte(value)
            return (v, v, v)
        case .blackHot:
            let v = byte(1 - value)
            return (v, v, v)
        case .iron:
            return interpolate(
                value,
                stops: [
                    (0.00, 0, 0, 0),
                    (0.18, 28, 10, 65),
                    (0.38, 112, 22, 92),
                    (0.58, 207, 55, 50),
                    (0.78, 250, 143, 32),
                    (0.92, 255, 232, 120),
                    (1.00, 255, 255, 255),
                ]
            )
        case .inferno:
            return interpolate(
                value,
                stops: [
                    (0.00, 0, 0, 4),
                    (0.20, 66, 10, 104),
                    (0.40, 147, 38, 103),
                    (0.60, 221, 81, 58),
                    (0.80, 252, 166, 54),
                    (1.00, 252, 255, 164),
                ]
            )
        case .rainbow:
            return interpolate(
                value,
                stops: [
                    (0.00, 0, 0, 90),
                    (0.20, 0, 80, 255),
                    (0.40, 0, 220, 220),
                    (0.60, 80, 255, 0),
                    (0.80, 255, 220, 0),
                    (1.00, 255, 0, 0),
                ]
            )
        }
    }

    private func byte(_ value: Float) -> UInt8 {
        UInt8(min(max(value, 0), 1) * 255)
    }

    private func interpolate(
        _ value: Float,
        stops: [(Float, UInt8, UInt8, UInt8)]
    ) -> (UInt8, UInt8, UInt8) {
        let value = min(max(value, 0), 1)
        for index in 1..<stops.count {
            let lower = stops[index - 1]
            let upper = stops[index]
            if value <= upper.0 {
                let fraction = (value - lower.0) / max(upper.0 - lower.0, 0.001)
                func channel(_ a: UInt8, _ b: UInt8) -> UInt8 {
                    UInt8(Float(a) + (Float(b) - Float(a)) * fraction)
                }
                return (channel(lower.1, upper.1), channel(lower.2, upper.2), channel(lower.3, upper.3))
            }
        }
        let last = stops[stops.count - 1]
        return (last.1, last.2, last.3)
    }
}
