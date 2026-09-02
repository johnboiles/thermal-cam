import CLibusb
import Foundation

public enum GainMode: String, CaseIterable, Identifiable, Sendable {
    case high = "High sensitivity"
    case low = "Extended range"

    public var id: String { rawValue }
}

public enum ThermalCameraError: LocalizedError, Sendable {
    case notFound
    case notOpen
    case stopped
    case usb(operation: String, code: Int32)
    case shortTransfer(operation: String, expected: Int, actual: Int)
    case malformedFrame(String)

    public var errorDescription: String? {
        switch self {
        case .notFound:
            return "No supported thermal camera was found. Connect one over USB and try again."
        case .notOpen:
            return "The camera is not open."
        case .stopped:
            return "Capture stopped."
        case let .usb(operation, code):
            let name = String(cString: libusb_error_name(code))
            return "USB \(operation) failed: \(name) (\(code))"
        case let .shortTransfer(operation, expected, actual):
            return "USB \(operation) returned \(actual) bytes; expected \(expected)."
        case let .malformedFrame(message):
            return "Malformed thermal frame: \(message)"
        }
    }
}

/// Synchronous low-level driver for the Thermal Master P1 (3474:45C2).
/// Call open/start/read/close from one background queue. The request methods
/// are thread-safe and may be called by the UI while capture is running.
public final class P1Camera: OpenableThermalCamera, @unchecked Sendable {
    public static let vendorID: UInt16 = 0x3474
    public static let productID: UInt16 = 0x45C2

    public private(set) var info = ThermalCameraInfo(
        manufacturer: "Thermal Master",
        model: "P1",
        firmware: "",
        serial: "",
        width: P1FrameDecoder.width,
        height: P1FrameDecoder.height
    )

    private var context: OpaquePointer?
    private var handle: OpaquePointer?
    private var claimedInterfaces: Set<Int32> = []
    private var isStreaming = false

    private let requestLock = NSLock()
    private var stopRequested = false
    private var pendingCommands: [PendingCommand] = []

    private enum PendingCommand {
        case shutter
        case gain(GainMode)
    }

    private enum Command {
        static let readName = bytes("0101810001000000000000001e0000004f90")
        static let readVersion = bytes("0101810002000000000000000c0000001f63")
        static let readSerial = bytes("01018100070000000000000040000000104c")
        static let startStream = bytes("012f81000000000000000000010000004930")
        static let gainLow = bytes("012f41000000000000000000000000003c3a")
        static let gainHigh = bytes("012f41000100000000000000000000004939")
        static let shutter = bytes("01364300000000000000000000000000cd0b")
    }

    public init() {}

    deinit {
        close()
    }

    public func open() throws -> ThermalCameraInfo {
        close()

        var newContext: OpaquePointer?
        let initResult = libusb_init(&newContext)
        guard initResult == 0 else {
            throw ThermalCameraError.usb(operation: "initialization", code: initResult)
        }
        context = newContext

        guard let opened = libusb_open_device_with_vid_pid(
            newContext,
            Self.vendorID,
            Self.productID
        ) else {
            close()
            throw ThermalCameraError.notFound
        }
        handle = opened

        // set_configuration can return BUSY when configuration 1 is already active.
        let configureResult = libusb_set_configuration(opened, 1)
        if configureResult != 0 && configureResult != LIBUSB_ERROR_BUSY.rawValue {
            throw ThermalCameraError.usb(operation: "configuration", code: configureResult)
        }

        for interface in [Int32(0), Int32(1)] {
            let claimResult = libusb_claim_interface(opened, interface)
            guard claimResult == 0 else {
                throw ThermalCameraError.usb(
                    operation: "claim interface \(interface)",
                    code: claimResult
                )
            }
            claimedInterfaces.insert(interface)
        }

        let model = try readRegister(command: Command.readName, length: 30)
        let firmware = try readRegister(command: Command.readVersion, length: 12)
        let serial = try readRegister(command: Command.readSerial, length: 64)
        let deviceInfo = ThermalCameraInfo(
            manufacturer: "Thermal Master",
            model: model,
            firmware: firmware,
            serial: serial,
            width: P1FrameDecoder.width,
            height: P1FrameDecoder.height
        )
        info = deviceInfo
        return deviceInfo
    }

    public func close() {
        if isStreaming, let handle {
            _ = libusb_set_interface_alt_setting(handle, 1, 0)
        }
        isStreaming = false

        if let handle {
            for interface in claimedInterfaces.sorted(by: >) {
                _ = libusb_release_interface(handle, interface)
            }
            libusb_close(handle)
        }
        claimedInterfaces.removeAll()
        handle = nil

        if let context {
            libusb_exit(context)
        }
        context = nil
    }

    public func startStreaming() throws {
        guard let handle else { throw ThermalCameraError.notOpen }
        setStopRequested(false)

        try startStreamCommand()
        Thread.sleep(forTimeInterval: 1.0)

        let altResult = libusb_set_interface_alt_setting(handle, 1, 1)
        guard altResult == 0 else {
            throw ThermalCameraError.usb(operation: "enable stream interface", code: altResult)
        }

        let enableResult = libusb_control_transfer(handle, 0x40, 0xEE, 0, 1, nil, 0, 1_000)
        guard enableResult >= 0 else {
            throw ThermalCameraError.usb(operation: "enable stream", code: enableResult)
        }

        Thread.sleep(forTimeInterval: 2.0)

        // The official application primes the bulk endpoint once before the
        // final stream command. A timeout here is normal and intentionally ignored.
        var primeBuffer = [UInt8](repeating: 0, count: P1FrameDecoder.pixelDataSize)
        _ = try? bulkRead(into: &primeBuffer, timeoutMilliseconds: 100)

        try startStreamCommand()
        isStreaming = true
    }

    public func stopStreaming() {
        requestStop()
        if let handle, isStreaming {
            _ = libusb_set_interface_alt_setting(handle, 1, 0)
        }
        isStreaming = false
    }

    public func requestStop() {
        setStopRequested(true)
    }

    public func requestShutterCalibration() {
        requestLock.lock()
        pendingCommands.append(.shutter)
        requestLock.unlock()
    }

    public func requestGainMode(_ mode: GainMode) {
        requestLock.lock()
        pendingCommands.removeAll {
            if case .gain = $0 { return true }
            return false
        }
        pendingCommands.append(.gain(mode))
        requestLock.unlock()
    }

    public func readFrame() throws -> ThermalFrame {
        guard handle != nil, isStreaming else { throw ThermalCameraError.notOpen }

        var frameBuffer = [UInt8](repeating: 0, count: P1FrameDecoder.wireSize)
        var chunkBuffer = [UInt8](repeating: 0, count: 16_384)

        while !shouldStop {
            try performPendingCommands()
            var position = 0

            while position < P1FrameDecoder.wireSize, !shouldStop {
                let count: Int
                do {
                    count = try bulkRead(into: &chunkBuffer, timeoutMilliseconds: 500)
                } catch let ThermalCameraError.usb(_, code)
                    where code == LIBUSB_ERROR_TIMEOUT.rawValue {
                    continue
                }

                let nextPosition = position + count
                // The device terminates each frame with a dedicated 12-byte
                // transfer. These checks re-synchronize if capture starts midway.
                if (count == P1FrameDecoder.markerSize && nextPosition < P1FrameDecoder.wireSize)
                    || (nextPosition >= P1FrameDecoder.wireSize && count != P1FrameDecoder.markerSize)
                    || nextPosition > P1FrameDecoder.wireSize {
                    position = 0
                    continue
                }

                frameBuffer.replaceSubrange(
                    position..<nextPosition,
                    with: chunkBuffer[0..<count]
                )
                position = nextPosition
            }

            if shouldStop { throw ThermalCameraError.stopped }

            let endOffset = P1FrameDecoder.wireSize - P1FrameDecoder.markerSize
            guard frameBuffer[0] == UInt8(P1FrameDecoder.markerSize),
                  frameBuffer[1] == 0x8C || frameBuffer[1] == 0x8D,
                  frameBuffer[endOffset] == UInt8(P1FrameDecoder.markerSize),
                  frameBuffer[endOffset + 1] == 0x8E || frameBuffer[endOffset + 1] == 0x8F else {
                continue
            }

            let startCounter = littleEndianUInt32(frameBuffer, at: 2)
            let endCounter = littleEndianUInt32(frameBuffer, at: endOffset + 2)
            guard startCounter == endCounter else { continue }

            return try P1FrameDecoder.decode(wireBytes: frameBuffer)
        }

        throw ThermalCameraError.stopped
    }

    private var shouldStop: Bool {
        requestLock.lock()
        defer { requestLock.unlock() }
        return stopRequested
    }

    private func setStopRequested(_ value: Bool) {
        requestLock.lock()
        stopRequested = value
        requestLock.unlock()
    }

    private func performPendingCommands() throws {
        requestLock.lock()
        let commands = pendingCommands
        pendingCommands.removeAll()
        requestLock.unlock()

        for command in commands {
            switch command {
            case .shutter:
                try sendCommand(Command.shutter)
                _ = try readStatus()
            case let .gain(mode):
                try sendCommand(mode == .high ? Command.gainHigh : Command.gainLow)
                _ = try readStatus()
            }
        }
    }

    private func startStreamCommand() throws {
        try sendCommand(Command.startStream)
        _ = try readStatus()
        _ = try readResponse(length: 1)
        _ = try readStatus()
    }

    private func readRegister(command: [UInt8], length: Int) throws -> String {
        try sendCommand(command)
        _ = try readStatus()
        let response = try readResponse(length: length)
        _ = try readStatus()
        let content = response.prefix { $0 != 0 }
        return String(bytes: content, encoding: .utf8) ?? ""
    }

    private func sendCommand(_ command: [UInt8]) throws {
        guard let handle else { throw ThermalCameraError.notOpen }
        var bytes = command
        let byteCount = bytes.count
        let result = bytes.withUnsafeMutableBytes { buffer in
            libusb_control_transfer(
                handle,
                0x41,
                0x20,
                0,
                0,
                buffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
                UInt16(byteCount),
                1_000
            )
        }
        guard result >= 0 else {
            throw ThermalCameraError.usb(operation: "send command", code: result)
        }
        guard result == byteCount else {
            throw ThermalCameraError.shortTransfer(
                operation: "send command",
                expected: byteCount,
                actual: Int(result)
            )
        }
    }

    private func readResponse(length: Int) throws -> [UInt8] {
        try controlRead(request: 0x21, length: length, operation: "read response")
    }

    private func readStatus() throws -> UInt8 {
        try controlRead(request: 0x22, length: 1, operation: "read status")[0]
    }

    private func controlRead(
        request: UInt8,
        length: Int,
        operation: String
    ) throws -> [UInt8] {
        guard let handle else { throw ThermalCameraError.notOpen }
        var bytes = [UInt8](repeating: 0, count: length)
        let result = bytes.withUnsafeMutableBytes { buffer in
            libusb_control_transfer(
                handle,
                0xC1,
                request,
                0,
                0,
                buffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
                UInt16(length),
                1_000
            )
        }
        guard result >= 0 else {
            throw ThermalCameraError.usb(operation: operation, code: result)
        }
        guard result == length else {
            throw ThermalCameraError.shortTransfer(
                operation: operation,
                expected: length,
                actual: Int(result)
            )
        }
        return bytes
    }

    private func bulkRead(
        into buffer: inout [UInt8],
        timeoutMilliseconds: UInt32
    ) throws -> Int {
        guard let handle else { throw ThermalCameraError.notOpen }
        var transferred: Int32 = 0
        let bufferCount = buffer.count
        let result = buffer.withUnsafeMutableBytes { pointer in
            libusb_bulk_transfer(
                handle,
                0x81,
                pointer.baseAddress?.assumingMemoryBound(to: UInt8.self),
                Int32(bufferCount),
                &transferred,
                timeoutMilliseconds
            )
        }
        guard result == 0 else {
            throw ThermalCameraError.usb(operation: "bulk read", code: result)
        }
        return Int(transferred)
    }
}

private func bytes(_ hex: String) -> [UInt8] {
    var result: [UInt8] = []
    result.reserveCapacity(hex.count / 2)
    var index = hex.startIndex
    while index < hex.endIndex {
        let next = hex.index(index, offsetBy: 2)
        result.append(UInt8(hex[index..<next], radix: 16)!)
        index = next
    }
    return result
}
