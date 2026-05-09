import SwiftUI
import AVFoundation
import Combine
import CoreLocation

struct CameraScreen: View {
    let captureRequests: Int

    @StateObject private var camera = CameraModel()
    @StateObject private var location = LocationProvider()
    @StateObject private var flow = CaptureFlow()
    @State private var pulse = false
    @State private var captureFlash = false
    @State private var handledCaptureRequests = 0
    @State private var visibleError: String?

    var body: some View {
        ZStack {
            backdrop
                .ignoresSafeArea()

            // Camera preview lives behind the chrome.
            if camera.isRunning {
                CameraPreview(session: camera.session)
                    .ignoresSafeArea()
                    .overlay(Color.black.opacity(0.12).ignoresSafeArea())
                    .overlay(viewfinder.allowsHitTesting(false))
            } else if camera.permission == .denied {
                centerCard(
                    title: "Camera permission needed",
                    body: "Open Settings > BinSight to enable the camera so we can scan waste.",
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
        .onChange(of: captureRequests) { _, newValue in
            guard newValue != handledCaptureRequests else { return }
            handledCaptureRequests = newValue
            Task { await capture() }
        }
        .alert("Couldn't classify",
               isPresented: Binding(
                get: { visibleError != nil },
                set: { if !$0 { visibleError = nil } }
               )) {
            Button("OK", role: .cancel) { visibleError = nil }
        } message: {
            Text(visibleError ?? "")
        }
    }

    private var backdrop: some View {
        LinearGradient(
            colors: [
                BinSightTokens.Color.sky,
                BinSightTokens.Color.mint,
                BinSightTokens.Color.recycle.opacity(0.42),
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
                Image(systemName: flow.isWorking ? "sparkles" : "leaf.fill")
                    .imageScale(.small)
                    .foregroundStyle(flow.isWorking ? BinSightTokens.Color.xp : BinSightTokens.Color.recycle)
                Text(flow.isWorking ? "Classifying…" : "Scan your waste")
                    .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(BinSightTokens.Color.ink)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.white.opacity(0.82), in: Capsule())
            .overlay(Capsule().stroke(.white, lineWidth: 1.5))
            .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 5)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Viewfinder

    private var viewfinder: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height) * 0.62
            ZStack {
                // Corner brackets
                ViewfinderBrackets(corner: 28, thickness: 3)
                    .stroke(BinSightTokens.Color.recycle.opacity(0.95), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: size, height: size)
                    .scaleEffect(pulse ? 1.02 : 1.0)
                    .opacity(flow.isWorking ? 0.4 : 1.0)

                // Inner ring
                Circle()
                    .stroke(.white.opacity(0.42), lineWidth: 2)
                    .frame(width: size * 0.55, height: size * 0.55)

                VStack(spacing: 8) {
                    Spacer()
                    DuoBadge(text: flow.isWorking ? "Working…" : "Center the item",
                             systemImage: flow.isWorking ? "sparkles" : "scope",
                             color: flow.isWorking ? BinSightTokens.Color.accent : BinSightTokens.Color.recycle,
                             filled: true)
                        .padding(.bottom, 188)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    // MARK: - Center card (no-camera states)

    private func centerCard(title: String, body: String, systemImage: String) -> some View {
        VStack(spacing: 14) {
            MascotArtView(mood: camera.permission == .denied ? .sleepy : .happy,
                          size: 112,
                          accessory: systemImage)
            Text(title)
                .font(.system(.title2, design: .rounded).weight(.heavy))
                .foregroundStyle(BinSightTokens.Color.ink)
            Text(body)
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .foregroundStyle(BinSightTokens.Color.softInk)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: 320)
        .background(.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(BinSightTokens.Color.stroke, lineWidth: 2))
        .padding(40)
    }

    // MARK: - Capture flow

    private func capture() async {
        guard !flow.isWorking else {
            visibleError = "Already classifying — hang tight."
            return
        }
        guard camera.isRunning else {
            visibleError = camera.permission == .denied
                ? "Camera permission denied. Enable it in Settings → BinSight."
                : "Camera not ready yet."
            HapticEngine.failed()
            return
        }
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
            visibleError = flow.lastError ?? error.localizedDescription
        }
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
