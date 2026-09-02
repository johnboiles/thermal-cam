import XCTest
@testable import ThermalCore

final class ThermalFrameTests: XCTestCase {
    func testGenericFrameCarriesArbitraryDimensions() {
        let frame = ThermalFrame(
            width: 3,
            height: 2,
            brightness: [0, 1, 2, 3, 4, 5],
            temperaturesCelsius: [10, 11, 12, 13, 14, 15],
            frameCounter: 7,
            minimumCelsius: 10,
            maximumCelsius: 15
        )

        XCTAssertEqual(frame.width, 3)
        XCTAssertEqual(frame.height, 2)
        XCTAssertEqual(frame.centerCelsius, 14)
        XCTAssertEqual(frame.temperature(x: 2, y: 1), 15)
        XCTAssertEqual(ThermalPalette.iron.rgbaPixels(for: frame).count, 3 * 2 * 4)
    }

    func testDecodesP1BrightnessAndTemperaturePlanes() throws {
        var bytes = [UInt8](repeating: 0, count: P1FrameDecoder.wireSize)
        bytes[0] = 12
        bytes[1] = 0x8C
        bytes[2] = 0x78
        bytes[3] = 0x56
        bytes[4] = 0x34
        bytes[5] = 0x12

        let pixel = 60 * P1FrameDecoder.width + 80
        let displayOffset = P1FrameDecoder.markerSize + pixel * 2
        bytes[displayOffset] = 137

        let thermalRow = P1FrameDecoder.height + P1FrameDecoder.metadataRows + 60
        let thermalOffset = P1FrameDecoder.markerSize + (thermalRow * P1FrameDecoder.width + 80) * 2
        let raw = UInt16(300 * 64)
        bytes[thermalOffset] = UInt8(raw & 0xFF)
        bytes[thermalOffset + 1] = UInt8(raw >> 8)

        let frame = try P1FrameDecoder.decode(wireBytes: bytes)
        XCTAssertEqual(frame.frameCounter, 0x12345678)
        XCTAssertEqual(frame.brightness[pixel], 137)
        XCTAssertEqual(frame.temperature(x: 80, y: 60)!, 26.85, accuracy: 0.001)
    }

    func testRejectsFrameWithoutMarker() {
        let bytes = [UInt8](repeating: 0, count: P1FrameDecoder.wireSize)
        XCTAssertThrowsError(try P1FrameDecoder.decode(wireBytes: bytes))
    }

    func testPalettesProduceOpaqueRGBAImage() throws {
        var bytes = [UInt8](repeating: 0, count: P1FrameDecoder.wireSize)
        bytes[0] = 12
        bytes[1] = 0x8D
        let thermalStart = P1FrameDecoder.markerSize
            + (P1FrameDecoder.height + P1FrameDecoder.metadataRows) * P1FrameDecoder.width * 2
        for pixel in 0..<(P1FrameDecoder.width * P1FrameDecoder.height) {
            let raw = UInt16(18_000 + pixel % 1_000)
            let offset = thermalStart + pixel * 2
            bytes[offset] = UInt8(raw & 0xFF)
            bytes[offset + 1] = UInt8(raw >> 8)
        }
        let frame = try P1FrameDecoder.decode(wireBytes: bytes)

        for palette in ThermalPalette.allCases {
            let rgba = palette.rgbaPixels(for: frame)
            XCTAssertEqual(rgba.count, P1FrameDecoder.width * P1FrameDecoder.height * 4)
            XCTAssertEqual(rgba[3], 255)
        }
    }
}
