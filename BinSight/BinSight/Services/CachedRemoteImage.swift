import SwiftUI
import UIKit
import Combine

private let imageMemoryCache: NSCache<NSURL, UIImage> = {
    let c = NSCache<NSURL, UIImage>()
    c.countLimit = 200
    c.totalCostLimit = 64 * 1024 * 1024
    return c
}()

private let imageURLCache: URLCache = {
    let mem = 32 * 1024 * 1024
    let disk = 256 * 1024 * 1024
    return URLCache(memoryCapacity: mem, diskCapacity: disk, directory: nil)
}()

private let imageURLSession: URLSession = {
    let cfg = URLSessionConfiguration.default
    cfg.urlCache = imageURLCache
    cfg.requestCachePolicy = .returnCacheDataElseLoad
    cfg.timeoutIntervalForRequest = 20
    cfg.waitsForConnectivity = true
    return URLSession(configuration: cfg)
}()

enum BinSightImageCache {
    static func cachedImage(for url: URL) -> UIImage? {
        if let mem = imageMemoryCache.object(forKey: url as NSURL) { return mem }
        let req = URLRequest(url: url)
        if let resp = imageURLCache.cachedResponse(for: req),
           let img = UIImage(data: resp.data) {
            imageMemoryCache.setObject(img, forKey: url as NSURL, cost: resp.data.count)
            return img
        }
        return nil
    }

    static func loadImage(for url: URL) async -> UIImage? {
        if let cached = cachedImage(for: url) { return cached }
        do {
            let req = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20)
            let (data, _) = try await imageURLSession.data(for: req)
            guard let ui = UIImage(data: data) else { return nil }
            imageMemoryCache.setObject(ui, forKey: url as NSURL, cost: data.count)
            return ui
        } catch {
            return nil
        }
    }
}

@MainActor
final class CachedImageLoader: ObservableObject {
    @Published var image: UIImage?
    @Published var isLoading = false
    private var task: Task<Void, Never>?
    private var currentURL: URL?

    func load(_ url: URL?) {
        guard let url else {
            image = nil; isLoading = false; currentURL = nil
            task?.cancel(); task = nil
            return
        }
        if currentURL == url, image != nil { return }
        currentURL = url
        if let cached = imageMemoryCache.object(forKey: url as NSURL) {
            image = cached; isLoading = false; return
        }
        task?.cancel()
        isLoading = true
        task = Task { [weak self] in
            do {
                let req = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20)
                let (data, _) = try await imageURLSession.data(for: req)
                if Task.isCancelled { return }
                guard let ui = UIImage(data: data) else {
                    await MainActor.run { self?.isLoading = false }
                    return
                }
                imageMemoryCache.setObject(ui, forKey: url as NSURL, cost: data.count)
                await MainActor.run {
                    guard let self else { return }
                    if self.currentURL == url {
                        self.image = ui
                        self.isLoading = false
                    }
                }
            } catch {
                await MainActor.run { self?.isLoading = false }
            }
        }
    }
}

struct CachedRemoteImage<Placeholder: View>: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: () -> Placeholder
    @StateObject private var loader = CachedImageLoader()

    var body: some View {
        Group {
            if let img = loader.image {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else {
                placeholder()
            }
        }
        .animation(.easeOut(duration: 0.18), value: loader.image)
        .onAppear { loader.load(url) }
        .onChange(of: url) { _, newValue in loader.load(newValue) }
    }
}
