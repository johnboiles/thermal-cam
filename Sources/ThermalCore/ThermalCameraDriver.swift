import Foundation

public struct ThermalCameraInfo: Sendable {
    public let manufacturer: String
    public let model: String
    public let firmware: String
    public let serial: String
    public let width: Int
    public let height: Int

    public init(
        manufacturer: String,
        model: String,
        firmware: String,
        serial: String,
        width: Int,
        height: Int
    ) {
        self.manufacturer = manufacturer
        self.model = model
        self.firmware = firmware
        self.serial = serial
        self.width = width
        self.height = height
    }

    public var displayName: String {
        model.isEmpty ? manufacturer : model
    }
}
/// Contract implemented by each camera-specific transport/decoder pair.
/// Implementations are synchronous and are driven from the app's capture queue.
public protocol ThermalCameraDriver: AnyObject, Sendable {
    var info: ThermalCameraInfo { get }
    func startStreaming() throws
    func readFrame() throws -> ThermalFrame
    func stopStreaming()
    func requestStop()
    func requestShutterCalibration()
    func close()
}

public protocol OpenableThermalCamera: ThermalCameraDriver {
    @discardableResult func open() throws -> ThermalCameraInfo
}

/// The single place where camera drivers are registered. Add a factory here
/// when support for another USB camera is introduced.
public enum ThermalCameraRegistry {
    public static func openFirstAvailable() throws -> any ThermalCameraDriver {
        let factories: [() -> any OpenableThermalCamera] = [
            { P1Camera() },
        ]

        for factory in factories {
            let camera = factory()
            do {
                _ = try camera.open()
                return camera
            } catch ThermalCameraError.notFound {
                camera.close()
                continue
            } catch {
                camera.close()
                throw error
            }
        }
        throw ThermalCameraError.notFound
    }
}
