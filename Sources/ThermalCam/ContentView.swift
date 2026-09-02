import SwiftUI
import ThermalCore

struct ContentView: View {
    @ObservedObject var model: CameraViewModel

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            cameraArea
            Divider()
            metrics
        }
        .frame(minWidth: 760, idealWidth: 920, minHeight: 610, idealHeight: 720)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { model.connect() }
        .onDisappear { model.disconnect() }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            statusDot
            VStack(alignment: .leading, spacing: 1) {
                Text(model.state.label)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .lineLimit(1)
                if let info = model.deviceInfo {
                    Text("\(info.displayName) · firmware \(info.firmware)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Picker("Palette", selection: $model.palette) {
                ForEach(ThermalPalette.allCases) { palette in
                    Text(palette.rawValue).tag(palette)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 150)

            Button {
                model.calibrateShutter()
            } label: {
                Label("Calibrate", systemImage: "camera.aperture")
            }
            .disabled(!model.isLive)

            Button {
                model.saveSnapshot()
            } label: {
                Label("Snapshot", systemImage: "camera")
            }
            .disabled(model.image == nil)
            .keyboardShortcut("s", modifiers: [.command])

            if model.canConnect {
                Button("Reconnect") { model.connect() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 10, height: 10)
            .shadow(color: statusColor.opacity(0.45), radius: 4)
    }

    private var statusColor: Color {
        switch model.state {
        case .live: return .green
        case .connecting, .warmingUp, .stopping: return .orange
        case .failed: return .red
        case .disconnected: return .secondary
        }
    }

    private var cameraArea: some View {
        ZStack(alignment: .bottom) {
            ThermalImageView(image: model.image, frame: model.frame)
                .padding(18)

            if let notice = model.notice {
                Text(notice)
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.ultraThickMaterial, in: Capsule())
                    .padding(.bottom, 28)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .underPageBackgroundColor))
        .animation(.easeOut(duration: 0.2), value: model.notice)
    }

    private var metrics: some View {
        HStack(spacing: 28) {
            metric("Minimum", temperature(model.frame?.minimumCelsius))
            metric("Center", temperature(model.frame?.centerCelsius))
            metric("Maximum", temperature(model.frame?.maximumCelsius))

            Spacer()

            if let info = model.deviceInfo, !info.serial.isEmpty {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(info.serial)
                        .font(.system(.caption, design: .monospaced))
                    Text("Serial number")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .trailing, spacing: 2) {
                Text(model.framesPerSecond > 0 ? String(format: "%.1f fps", model.framesPerSecond) : "— fps")
                    .font(.system(.callout, design: .rounded).weight(.medium))
                Text(resolutionLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 76, alignment: .leading)
    }

    private func temperature(_ value: Float?) -> String {
        guard let value else { return "— °C" }
        return String(format: "%.1f °C", value)
    }

    private var resolutionLabel: String {
        guard let frame = model.frame else { return "Radiometric stream" }
        return "\(frame.width) × \(frame.height) radiometric"
    }
}
