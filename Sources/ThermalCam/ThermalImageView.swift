import CoreGraphics
import SwiftUI
import ThermalCore

struct ThermalImageView: View {
    let image: CGImage?
    let frame: ThermalFrame?

    @State private var hoverLocation: CGPoint?

    var body: some View {
        GeometryReader { proxy in
            let fitted = fittedRect(in: proxy.size)
            ZStack(alignment: .topLeading) {
                Color.black

                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: fitted.width, height: fitted.height)
                        .position(x: fitted.midX, y: fitted.midY)

                    centerReticle(in: fitted)

                    if let hover = hoverReading(in: fitted) {
                        hoverOverlay(hover, in: fitted)
                    }
                } else {
                    VStack(spacing: 14) {
                        Image(systemName: "thermometer.medium")
                            .font(.system(size: 48, weight: .light))
                        Text("Connect a supported thermal camera")
                            .font(.title3.weight(.medium))
                        Text("The first image appears after a short sensor warm-up.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .foregroundStyle(.white.opacity(0.8))
                }

                Color.clear
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case let .active(location): hoverLocation = location
                        case .ended: hoverLocation = nil
                        }
                    }
            }
        }
        .aspectRatio(frame.map { CGFloat($0.width) / CGFloat($0.height) } ?? (4.0 / 3.0), contentMode: .fit)
        .background(.black)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func centerReticle(in rect: CGRect) -> some View {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        Path { path in
            path.move(to: CGPoint(x: center.x - 9, y: center.y))
            path.addLine(to: CGPoint(x: center.x + 9, y: center.y))
            path.move(to: CGPoint(x: center.x, y: center.y - 9))
            path.addLine(to: CGPoint(x: center.x, y: center.y + 9))
        }
        .stroke(.white.opacity(0.9), lineWidth: 1)
        .shadow(color: .black, radius: 1)
    }

    @ViewBuilder
    private func hoverOverlay(_ hover: HoverReading, in rect: CGRect) -> some View {
        let point = CGPoint(
            x: rect.minX + (CGFloat(hover.x) + 0.5) / CGFloat(frame?.width ?? 1) * rect.width,
            y: rect.minY + (CGFloat(hover.y) + 0.5) / CGFloat(frame?.height ?? 1) * rect.height
        )

        Circle()
            .stroke(.white, lineWidth: 1.5)
            .background(Circle().fill(.black.opacity(0.25)))
            .frame(width: 11, height: 11)
            .position(point)

        Text(String(format: "%.1f °C", hover.temperature))
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(.black.opacity(0.72), in: Capsule())
            .foregroundStyle(.white)
            .position(
                x: min(max(point.x + 44, rect.minX + 45), rect.maxX - 45),
                y: max(point.y - 22, rect.minY + 14)
            )
    }

    private func fittedRect(in container: CGSize) -> CGRect {
        let aspect = frame.map { CGFloat($0.width) / CGFloat($0.height) } ?? (4.0 / 3.0)
        let width: CGFloat
        let height: CGFloat
        if container.width / max(container.height, 1) > aspect {
            height = container.height
            width = height * aspect
        } else {
            width = container.width
            height = width / aspect
        }
        return CGRect(
            x: (container.width - width) / 2,
            y: (container.height - height) / 2,
            width: width,
            height: height
        )
    }

    private func hoverReading(in rect: CGRect) -> HoverReading? {
        guard let hoverLocation, rect.contains(hoverLocation), let frame else { return nil }
        let x = min(
            max(Int((hoverLocation.x - rect.minX) / rect.width * CGFloat(frame.width)), 0),
            frame.width - 1
        )
        let y = min(
            max(Int((hoverLocation.y - rect.minY) / rect.height * CGFloat(frame.height)), 0),
            frame.height - 1
        )
        guard let temperature = frame.temperature(x: x, y: y) else { return nil }
        return HoverReading(x: x, y: y, temperature: temperature)
    }

    private struct HoverReading {
        let x: Int
        let y: Int
        let temperature: Float
    }
}
