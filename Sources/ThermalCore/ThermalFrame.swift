import Foundation

/// One decoded radiometric frame, independent of camera brand or resolution.
public struct ThermalFrame: Sendable {
    public let width: Int
    public let height: Int
    public let brightness: [UInt8]
    public let temperaturesCelsius: [Float]
    public let frameCounter: UInt32
    public let minimumCelsius: Float
    public let maximumCelsius: Float

    public init(
        width: Int,
        height: Int,
        brightness: [UInt8],
        temperaturesCelsius: [Float],
        frameCounter: UInt32,
        minimumCelsius: Float,
        maximumCelsius: Float
    ) {
        self.width = width
        self.height = height
        self.brightness = brightness
        self.temperaturesCelsius = temperaturesCelsius
        self.frameCounter = frameCounter
        self.minimumCelsius = minimumCelsius
        self.maximumCelsius = maximumCelsius
    }

    public var centerCelsius: Float {
        temperaturesCelsius[(height / 2) * width + width / 2]
    }

    public func temperature(x: Int, y: Int) -> Float? {
        guard (0..<width).contains(x), (0..<height).contains(y) else {
            return nil
        }
        return temperaturesCelsius[y * width + x]
    }
}
