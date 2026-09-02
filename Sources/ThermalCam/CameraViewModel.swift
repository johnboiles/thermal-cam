import AppKit
import Combine
import CoreGraphics
import Foundation
import ThermalCore
import UniformTypeIdentifiers

@MainActor
final class CameraViewModel: ObservableObject {
    @Published private(set) var state: CameraConnectionState = .disconnected
    @Published private(set) var frame: ThermalFrame?
    @Published private(set) var image: CGImage?
    @Published private(set) var deviceInfo: ThermalCameraInfo?
    @Published private(set) var framesPerSecond: Double = 0
    @Published var palette: ThermalPalette = .iron {
        didSet { renderCurrentFrame() }
    }
    @Published var notice: String?

    private let controller = CameraController()
    private var firstFrameTime: CFAbsoluteTime?
    private var frameCount = 0

    var isLive: Bool { state == .live }
    var canConnect: Bool {
        switch state {
        case .disconnected, .failed: return true
        default: return false
        }
    }

    func connect() {
        guard canConnect else { return }
        frame = nil
        image = nil
        deviceInfo = nil
        framesPerSecond = 0
        firstFrameTime = nil
        frameCount = 0
        notice = nil

        controller.start(
            onState: { [weak self] state in
                DispatchQueue.main.async {
                    self?.state = state
                }
            },
            onInfo: { [weak self] info in
                DispatchQueue.main.async {
                    self?.deviceInfo = info
                }
            },
            onFrame: { [weak self] frame in
                DispatchQueue.main.async {
                    self?.accept(frame)
                }
            }
        )
    }

    func disconnect() {
        guard state != .disconnected else { return }
        state = .stopping
        controller.stop()
    }

    func calibrateShutter() {
        guard isLive else { return }
        notice = "Shutter calibration requested"
        controller.requestShutterCalibration()
        dismissNoticeSoon()
    }

    func saveSnapshot() {
        guard let image else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = Self.snapshotFilename()
        panel.title = "Save Thermal Snapshot"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            let representation = NSBitmapImageRep(cgImage: image)
            guard let data = representation.representation(using: .png, properties: [:]) else {
                self?.notice = "Could not encode snapshot"
                return
            }
            do {
                try data.write(to: url, options: .atomic)
                self?.notice = "Saved \(url.lastPathComponent)"
                self?.dismissNoticeSoon()
            } catch {
                self?.notice = "Save failed: \(error.localizedDescription)"
            }
        }
    }

    private func accept(_ newFrame: ThermalFrame) {
        frame = newFrame
        image = Self.makeImage(frame: newFrame, palette: palette)

        let now = CFAbsoluteTimeGetCurrent()
        if firstFrameTime == nil { firstFrameTime = now }
        frameCount += 1
        if let firstFrameTime, now - firstFrameTime >= 1 {
            framesPerSecond = Double(frameCount) / (now - firstFrameTime)
            self.firstFrameTime = now
            frameCount = 0
        }
    }

    private func renderCurrentFrame() {
        guard let frame else { return }
        image = Self.makeImage(frame: frame, palette: palette)
    }

    private func dismissNoticeSoon() {
        let currentNotice = notice
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            if self?.notice == currentNotice {
                self?.notice = nil
            }
        }
    }

    private static func makeImage(frame: ThermalFrame, palette: ThermalPalette) -> CGImage? {
        let bytes = palette.rgbaPixels(for: frame)
        let data = Data(bytes) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)
        return CGImage(
            width: frame.width,
            height: frame.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: frame.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    private static func snapshotFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "thermal-cam-\(formatter.string(from: Date())).png"
    }
}
