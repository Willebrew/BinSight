import SwiftUI
import AVFoundation
import Combine
import CoreLocation

struct CameraScreen: View {
    @StateObject private var camera = CameraModel()
    @StateObject private var location = LocationProvider()
    @StateObject private var flow = CaptureFlow()
    @State private var pulse = false
    @State private var captureFlash = false

    var body: some View {
        ZStack {
            backdrop
                .ignoresSafeArea()

            // Camera preview lives behind the chrome.
            if camera.isRunning {
                CameraPreview(session: camera.session)
                    .ignoresSafeArea()
                    .overlay(viewfinder.allowsHitTesting(false))
            } else if camera.permission == .denied {
                centerCard(
                    title: "Camera permission needed",
                    body: "Open Settings → BinSight to enable the camera so we can scan waste.",
                    systemImage: "camera.metering.unknown"
                )
            } else {
                centerCard(
                    title: "Point at any waste item",
                    body: "We'll classify it and tell you exactly how to dispose of it.",
                    systemImage: "leaf.circle.fill"
                )
            }

            VStack(spacing: 0) {
                topBadges
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                Spacer()
                shutterRow
                    .padding(.bottom, 130)
            }

            // Capture flash overlay.
            Color.white
                .opacity(captureFlash ? 0.55 : 0)
                .allowsHitTesting(false)
                .ignoresSafeArea()
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
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onReceive(Timer.publish(every: 1.4, on: .main, in: .common).autoconnect()) { _ in
            if camera.isRunning && !flow.isWorking {
                HapticEngine.tick()
                withAnimation(BinSightTokens.Motion.lift) { pulse.toggle() }
            }
        }
    }

    private var backdrop: some View {
        // Soft warm-to-cool gradient so the empty preview state isn't a flat black slab.
        LinearGradient(
            colors: [
                Color(red: 0.04, green: 0.07, blue: 0.10),
                Color(red: 0.02, green: 0.16, blue: 0.18),
                Color(red: 0.01, green: 0.05, blue: 0.07),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Top badges

    private var topBadges: some View {
        HStack {
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Image(systemName: "leaf.fill")
                    .imageScale(.small)
                    .foregroundStyle(BinSightTokens.Color.recycle)
                Text("Scan your waste")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(.white)
                if location.last != nil {
                    Circle()
                        .fill(BinSightTokens.Color.recycle)
                        .frame(width: 6, height: 6)
                        .padding(.leading, 4)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .glassSurface(Capsule(), variant: .regular)
            Spacer(minLength: 0)
        }
        .animation(BinSightTokens.Motion.snap, value: location.last == nil)
    }

    // MARK: - Viewfinder

    private var viewfinder: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height) * 0.62
            ZStack {
                // Corner brackets
                ViewfinderBrackets(corner: 28, thickness: 3)
                    .stroke(.white.opacity(0.85), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: size, height: size)
                    .scaleEffect(pulse ? 1.02 : 1.0)
                    .opacity(flow.isWorking ? 0.4 : 1.0)

                // Inner ring
                Circle()
                    .stroke(.white.opacity(0.18), lineWidth: 1)
                    .frame(width: size * 0.55, height: size * 0.55)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    // MARK: - Center card (no-camera states)

    private func centerCard(title: String, body: String, systemImage: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(BinSightTokens.Color.recycle)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(body)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white)
        .padding(24)
        .frame(maxWidth: 320)
        .glassSurface(RoundedRectangle(cornerRadius: 28, style: .continuous), variant: .regular)
        .padding(40)
    }

    // MARK: - Shutter

    private var shutterRow: some View {
        HStack(spacing: 28) {
            Spacer()
            ShutterButton(isWorking: flow.isWorking, isReady: camera.isRunning) {
                Task { await capture() }
            }
            Spacer()
        }
    }

    // MARK: - Capture flow

    private func capture() async {
        guard camera.isRunning, !flow.isWorking else { return }
        captureFlash = true
        withAnimation(.easeOut(duration: 0.18)) { captureFlash = false }
        HapticEngine.captured()
        do {
            let jpeg = try await camera.capturePhoto()
            let id = try await flow.classify(
                jpeg: jpeg,
                lat: location.last?.coordinate.latitude,
                lng: location.last?.coordinate.longitude,
                city: location.placemark?.locality,
                state: location.placemark?.administrativeArea,
                country: location.placemark?.country
            )
            HapticEngine.ok()
            await MainActor.run { flow.activeId = .init(value: id) }
        } catch {
            HapticEngine.failed()
        }
    }
}

// MARK: - Shutter button

private struct ShutterButton: View {
    let isWorking: Bool
    let isReady: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.95), lineWidth: 5)
                    .frame(width: 84, height: 84)

                Circle()
                    .fill(isWorking ? BinSightTokens.Color.accent : .white)
                    .frame(width: 68, height: 68)
                    .overlay {
                        if isWorking {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        }
                    }
                    .scaleEffect(isWorking ? 0.86 : 1.0)
                    .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isWorking)
            }
            .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 4)
            .opacity(isReady ? 1.0 : 0.55)
        }
        .buttonStyle(ShutterPressStyle())
        .disabled(!isReady || isWorking)
        .accessibilityLabel("Capture waste photo")
    }
}

private struct ShutterPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Viewfinder corner brackets

private struct ViewfinderBrackets: Shape {
    var corner: CGFloat
    var thickness: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = corner
        // Top-left
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + c))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + c, y: rect.minY))
        // Top-right
        p.move(to: CGPoint(x: rect.maxX - c, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + c))
        // Bottom-right
        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY - c))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - c, y: rect.maxY))
        // Bottom-left
        p.move(to: CGPoint(x: rect.minX + c, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - c))
        return p
    }
}
