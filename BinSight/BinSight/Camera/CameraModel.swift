@preconcurrency import AVFoundation
import Combine
import CoreImage
import CoreLocation
import SwiftUI
import UIKit

@MainActor
final class CameraModel: NSObject, ObservableObject {
    @Published private(set) var permission: AVAuthorizationStatus = .notDetermined
    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "binsight.camera.session")
    private let photoOutput = AVCapturePhotoOutput()
    private var photoContinuation: CheckedContinuation<Data, Error>?

    func start() {
        permission = AVCaptureDevice.authorizationStatus(for: .video)
        switch permission {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    self?.permission = granted ? .authorized : .denied
                    if granted { self?.configureAndRun() }
                }
            }
        case .authorized:
            configureAndRun()
        default:
            lastError = "Camera permission denied. Enable it in Settings."
        }
    }

    func stop() {
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
        isRunning = false
    }

    private func configureAndRun() {
        queue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo
            self.session.inputs.forEach { self.session.removeInput($0) }
            self.session.outputs.forEach { self.session.removeOutput($0) }
            guard
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                let input = try? AVCaptureDeviceInput(device: device),
                self.session.canAddInput(input)
            else {
                Task { @MainActor in self.lastError = "No back camera available" }
                self.session.commitConfiguration()
                return
            }
            self.session.addInput(input)
            if self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
                self.photoOutput.maxPhotoQualityPrioritization = .balanced
            }
            self.session.commitConfiguration()
            self.session.startRunning()
            Task { @MainActor in self.isRunning = true }
        }
    }

    func capturePhoto() async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            self.photoContinuation = cont
            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .balanced
            queue.async { [photoOutput] in
                photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }
}

extension CameraModel: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        Task { @MainActor in
            defer { self.photoContinuation = nil }
            if let error = error {
                self.photoContinuation?.resume(throwing: error)
                return
            }
            guard let raw = photo.fileDataRepresentation() else {
                self.photoContinuation?.resume(throwing: NSError(
                    domain: "Camera", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "No image data"]
                ))
                return
            }
            let downsized = downsizeJPEG(data: raw, maxLongEdge: 1600, quality: 0.82) ?? raw
            self.photoContinuation?.resume(returning: downsized)
        }
    }
}

private func downsizeJPEG(data: Data, maxLongEdge: CGFloat, quality: CGFloat) -> Data? {
    guard let image = UIImage(data: data) else { return nil }
    let longEdge = max(image.size.width, image.size.height)
    let scale = min(1, maxLongEdge / longEdge)
    if scale >= 0.999 { return image.jpegData(compressionQuality: quality) }
    let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    let renderer = UIGraphicsImageRenderer(size: target)
    let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
    return resized.jpegData(compressionQuality: quality)
}
