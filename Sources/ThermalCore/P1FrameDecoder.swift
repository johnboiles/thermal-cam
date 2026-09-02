import Foundation

/// Wire layout and decoder for Thermal Master P1-compatible cameras.
public enum P1FrameDecoder {
    public static let width = 160
    public static let height = 120
    public static let metadataRows = 2
    public static let frameRows = height * 2 + metadataRows
    public static let markerSize = 12
    public static let pixelDataSize = frameRows * width * 2
    public static let wireSize = markerSize + pixelDataSize + markerSize

    public static func decode(wireBytes: [UInt8]) throws -> ThermalFrame {
        let requiredSize = markerSize + pixelDataSize
        guard wireBytes.count >= requiredSize else {
            throw ThermalCameraError.malformedFrame(
                "Expected at least \(requiredSize) bytes, received \(wireBytes.count)"
            )
        }

        guard wireBytes[0] == UInt8(markerSize),
              wireBytes[1] == 0x8C || wireBytes[1] == 0x8D else {
            throw ThermalCameraError.malformedFrame("Missing P1 start marker")
        }

        let counter = littleEndianUInt32(wireBytes, at: 2)
        var brightness = [UInt8](repeating: 0, count: width * height)
        var temperatures = [Float](repeating: 0, count: width * height)
        var minimum = Float.greatestFiniteMagnitude
        var maximum = -Float.greatestFiniteMagnitude

        for y in 0..<height {
            for x in 0..<width {
                let pixelIndex = y * width + x
                let displayOffset = markerSize + pixelIndex * 2
                brightness[pixelIndex] = wireBytes[displayOffset]

                let thermalRow = height + metadataRows + y
                let thermalOffset = markerSize + (thermalRow * width + x) * 2
                let raw = UInt16(wireBytes[thermalOffset])
                    | (UInt16(wireBytes[thermalOffset + 1]) << 8)
                let celsius = Float(raw) / 64.0 - 273.15
                temperatures[pixelIndex] = celsius
                minimum = min(minimum, celsius)
                maximum = max(maximum, celsius)
            }
        }

        return ThermalFrame(
            width: width,
            height: height,
            brightness: brightness,
            temperaturesCelsius: temperatures,
            frameCounter: counter,
            minimumCelsius: minimum,
            maximumCelsius: maximum
        )
    }
}

func littleEndianUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
    UInt32(bytes[offset])
        | (UInt32(bytes[offset + 1]) << 8)
        | (UInt32(bytes[offset + 2]) << 16)
        | (UInt32(bytes[offset + 3]) << 24)
}
