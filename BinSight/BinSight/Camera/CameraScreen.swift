import SwiftUI
import CoreLocation

struct CameraScreen: View {
    @StateObject private var camera = CameraModel()
    @StateObject private var location = LocationProvider()
    @StateObject private var flow = CaptureFlow()
    @State private var pulse = false
    @State private var resultId: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if camera.isRunning {
                CameraPreview(session: camera.session)
                    .ignoresSafeArea()
            } else if camera.permission == .denied {
                permissionPlaceholder
            } else {
                ProgressView().tint(.white)
            }

            VStack {
                topBadges
                Spacer()
                shutterRow
                    .padding(.bottom, 96)
            }
        }
        .task {
            camera.start()
            location.start()
            HapticEngine.scanTick.prepare()
            HapticEngine.shutter.prepare()
        }
        .onDisappear { camera.stop(); location.stop() }
        .sheet(item: $flow.activeId) { id in
            ResultCardView(classificationId: id.value)
        }
        .onReceive(Timer.publish(every: 1.2, on: .main, in: .common).autoconnect()) { _ in
            if camera.isRunning && !flow.isWorking { HapticEngine.tick(); pulse.toggle() }
        }
    }

    private var topBadges: some View {
        HStack {
            Label("Scan your waste", systemImage: "leaf.fill")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .glassSurface(Capsule(), variant: .regular)
                .foregroundStyle(.white)
            Spacer()
            if let l = location.last {
                Text("\(l.coordinate.latitude, specifier: "%.2f"), \(l.coordinate.longitude, specifier: "%.2f")")
                    .font(.caption.monospaced())
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .glassSurface(Capsule(), variant: .clear)
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }

    private var shutterRow: some View {
        Button {
            Task { await capture() }
        } label: {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.18))
                    .frame(width: 96, height: 96)
                    .scaleEffect(pulse ? 1.04 : 1.0)
                    .animation(BinSightTokens.Motion.lift, value: pulse)
                Circle()
                    .stroke(.white, lineWidth: 4)
                    .frame(width: 78, height: 78)
                Circle()
                    .fill(flow.isWorking ? BinSightTokens.Color.accent : .white)
                    .frame(width: 64, height: 64)
                if flow.isWorking {
                    ProgressView().tint(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(flow.isWorking || !camera.isRunning)
        .glassSurface(Circle(), variant: .regular)
        .accessibilityLabel("Capture waste photo")
    }

    private var permissionPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.metering.unknown")
                .font(.system(size: 40))
            Text("Camera permission needed")
                .font(.headline)
            Text("Enable camera in Settings → BinSight to scan waste.")
                .multilineTextAlignment(.center)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.white)
        .padding(24)
        .glassSurface(RoundedRectangle(cornerRadius: 24, style: .continuous), variant: .regular)
        .padding(32)
    }

    private func capture() async {
        do {
            HapticEngine.captured()
            let jpeg = try await camera.capturePhoto()
            let id = try await flow.classify(
                jpeg: jpeg,
                lat: location.last?.coordinate.latitude,
                lng: location.last?.coordinate.longitude
            )
            HapticEngine.ok()
            await MainActor.run { flow.activeId = .init(value: id) }
        } catch {
            HapticEngine.failed()
        }
    }
}
