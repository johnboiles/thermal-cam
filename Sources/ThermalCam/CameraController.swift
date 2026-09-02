import Foundation
import ThermalCore

enum CameraConnectionState: Equatable {
    case disconnected
    case connecting
    case warmingUp
    case live
    case stopping
    case failed(String)

    var label: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting…"
        case .warmingUp: return "Warming camera…"
        case .live: return "Live"
        case .stopping: return "Stopping…"
        case let .failed(message): return message
        }
    }
}

final class CameraController {
    private let queue = DispatchQueue(label: "org.eastbaymakers.thermal-cam.capture")
    private let lock = NSLock()
    private var activeCamera: (any ThermalCameraDriver)?
    private var running = false

    func start(
        onState: @escaping (CameraConnectionState) -> Void,
        onInfo: @escaping (ThermalCameraInfo) -> Void,
        onFrame: @escaping (ThermalFrame) -> Void
    ) {
        lock.lock()
        guard !running else {
            lock.unlock()
            return
        }
        running = true
        lock.unlock()

        queue.async { [weak self] in
            guard let self else { return }
            onState(.connecting)
            let camera: any ThermalCameraDriver
            do {
                camera = try ThermalCameraRegistry.openFirstAvailable()
            } catch {
                onState(.failed(error.localizedDescription))
                self.lock.lock()
                self.running = false
                self.lock.unlock()
                return
            }
            self.setActiveCamera(camera)

            do {
                let info = camera.info
                onInfo(info)
                onState(.warmingUp)
                try camera.startStreaming()
                onState(.live)

                while true {
                    let frame = try camera.readFrame()
                    onFrame(frame)
                }
            } catch ThermalCameraError.stopped {
                onState(.disconnected)
            } catch {
                onState(.failed(error.localizedDescription))
            }

            camera.close()
            self.setActiveCamera(nil)
            self.lock.lock()
            self.running = false
            self.lock.unlock()
        }
    }

    func stop() {
        lock.lock()
        let camera = activeCamera
        lock.unlock()
        camera?.requestStop()
    }

    func requestShutterCalibration() {
        lock.lock()
        let camera = activeCamera
        lock.unlock()
        camera?.requestShutterCalibration()
    }

    private func setActiveCamera(_ camera: (any ThermalCameraDriver)?) {
        lock.lock()
        activeCamera = camera
        lock.unlock()
    }
}
