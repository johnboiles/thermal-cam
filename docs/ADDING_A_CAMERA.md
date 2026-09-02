# Adding a camera driver

Thermal Cam keeps the app independent from any manufacturer. Each supported
camera converts its native USB/video frames into the shared `ThermalFrame` type.

## Driver boundary

Create a type in `Sources/ThermalCore` that implements `OpenableThermalCamera`:

```swift
public final class ExampleCamera: OpenableThermalCamera, @unchecked Sendable {
    public private(set) var info: ThermalCameraInfo

    public func open() throws -> ThermalCameraInfo { /* discover and claim */ }
    public func startStreaming() throws { /* initialize stream */ }
    public func readFrame() throws -> ThermalFrame { /* read and decode */ }
    public func requestShutterCalibration() { /* enqueue, if supported */ }
    public func requestStop() { /* interrupt the read loop safely */ }
    public func stopStreaming() { /* return the device to idle */ }
    public func close() { /* release interfaces and resources */ }
}
```

The implementation is called from one background capture queue. `requestStop`
and `requestShutterCalibration` may be called by the main thread and therefore
must be thread-safe.

## Frame requirements

Return a `ThermalFrame` with:

- Native width and height
- One Celsius value for every pixel
- Minimum and maximum temperatures for that frame
- A frame counter when the protocol provides one
- A brightness plane when available (the current UI colorizes temperatures)

Do protocol-specific parsing in a separate decoder, following the existing
`P1FrameDecoder` pattern. Unit-test the decoder with synthetic or recorded wire
frames before connecting it to the live transport.

## Register the driver

Add a factory to `ThermalCameraRegistry.openFirstAvailable()`. A driver should
throw `ThermalCameraError.notFound` only when its USB device is absent; other
errors should describe a present device that could not be opened.

The first factory that opens successfully becomes the active camera. The SwiftUI
app automatically adapts its image aspect ratio, resolution label, hover mapping,
temperature metrics, palettes, and snapshots to the returned frame dimensions.
