//
//  CachedAsyncImage.swift
//  Droppy
//
//  A cached version of AsyncImage that persists images across view recreations
//  to prevent fallback icons from flashing during reloads.
//

import SwiftUI
import ImageIO
import CryptoKit

/// A cached async image that stores loaded images to prevent re-fetching
/// and fallback icon flashing on view recreation.
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder
    
    @State private var image: NSImage?
    @State private var isLoading = false
    @State private var hasFailed = false
    @State private var loadTask: Task<Void, Never>?
    @State private var loadingURL: URL?

    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
        _image = State(initialValue: url.flatMap { ExtensionIconCache.shared.memoryImage(for: $0) })
    }
    
    var body: some View {
        Group {
            if let image = image {
                content(Image(nsImage: image))
            } else if hasFailed {
                placeholder()
            } else {
                // Loading state - show subtle placeholder, not the fallback icon
                RoundedRectangle(cornerRadius: DroppyRadius.ms, style: .continuous)
                    .fill(AdaptiveColors.buttonBackgroundAuto)
                    .overlay(
                        ProgressView()
                            .scaleEffect(0.5)
                            .opacity(0.5)
                    )
            }
        }
        .onAppear {
            startLoading()
        }
        .onChange(of: url) { previousURL, newURL in
            guard previousURL != newURL else { return }
            loadTask?.cancel()
            loadTask = nil
            loadingURL = nil
            isLoading = false
            image = newURL.flatMap { ExtensionIconCache.shared.memoryImage(for: $0) }
            hasFailed = newURL == nil
            startLoading()
        }
    }
    
    private func startLoading() {
        guard let url = url else {
            loadTask?.cancel()
            loadTask = nil
            loadingURL = nil
            isLoading = false
            image = nil
            hasFailed = true
            return
        }
        
        // Fast path: in-memory cache on main thread.
        if let cached = ExtensionIconCache.shared.memoryImage(for: url) {
            self.image = cached
            self.hasFailed = false
            self.isLoading = false
            self.loadingURL = nil
            self.loadTask = nil
            return
        }
        
        if let task = loadTask, isLoading, loadingURL == url, !task.isCancelled {
            return
        }

        if loadingURL != url {
            loadTask?.cancel()
            loadTask = nil
            isLoading = false
        }

        isLoading = true
        hasFailed = false
        loadingURL = url
        
        loadTask = Task.detached(priority: .utility) {
            let loadedImage = await ExtensionIconCache.shared.loadImage(for: url)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard self.loadingURL == url else { return }
                self.image = loadedImage
                self.hasFailed = loadedImage == nil
                self.isLoading = false
                self.loadTask = nil
                self.loadingURL = nil
            }
        }
    }
}

/// Thread-safe, bounded in-memory cache for extension icons.
/// Also deduplicates concurrent loads for the same URL.
final class ExtensionIconCache {
    static let shared = ExtensionIconCache()

    private let cache = NSCache<NSURL, NSImage>()
    private let fileManager = FileManager.default
    private let diskCacheDirectory: URL
    private let diskCacheSizeLimit = 256 * 1024 * 1024
    private var inFlightTasks: [URL: Task<NSImage?, Never>] = [:]
    private let lock = NSLock()

    private init() {
        cache.countLimit = 2_000
        cache.totalCostLimit = 256 * 1024 * 1024

        let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        diskCacheDirectory = cachesDirectory.appendingPathComponent("ExtensionIconCache", isDirectory: true)
        try? fileManager.createDirectory(at: diskCacheDirectory, withIntermediateDirectories: true)
    }

    func memoryImage(for url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    func cachedImage(for url: URL) -> NSImage? {
        memoryImage(for: url)
    }

    func clearCache() {
        lock.lock()
        let tasks = Array(inFlightTasks.values)
        inFlightTasks.removeAll()
        lock.unlock()
        for task in tasks {
            task.cancel()
        }
        cache.removeAllObjects()
        try? fileManager.removeItem(at: diskCacheDirectory)
        try? fileManager.createDirectory(at: diskCacheDirectory, withIntermediateDirectories: true)
    }

    func loadImage(for url: URL) async -> NSImage? {
        if let cached = memoryImage(for: url) {
            return cached
        }

        if let existingTask = existingInFlightTask(for: url) {
            return await existingTask.value
        }

        let task = Task<NSImage?, Never> { [weak self] in
            defer { self?.removeInFlightTask(for: url) }

            if let cached = self?.memoryImage(for: url) {
                return cached
            }

            if let diskCached = self?.diskImage(for: url) {
                return diskCached
            }

            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            request.timeoutInterval = 15

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard !Task.isCancelled else { return nil }

                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    return nil
                }

                guard let image = Self.decodeImage(from: data) else {
                    return nil
                }

                self?.store(image, for: url)
                self?.persistToDisk(data, for: url)
                return image
            } catch {
                return nil
            }
        }

        setInFlightTask(task, for: url)
        return await task.value
    }

    func prewarm(urls: [URL]) async {
        let uniqueURLs = Array(Set(urls))
        await withTaskGroup(of: Void.self) { group in
            for url in uniqueURLs {
                group.addTask { [weak self] in
                    guard let self else { return }
                    _ = await self.loadImage(for: url)
                }
            }
        }
    }

    func prewarm(urlStrings: [String]) async {
        await prewarm(urls: urlStrings.compactMap(URL.init(string:)))
    }

    private func existingInFlightTask(for url: URL) -> Task<NSImage?, Never>? {
        lock.lock()
        defer { lock.unlock() }
        return inFlightTasks[url]
    }

    private func setInFlightTask(_ task: Task<NSImage?, Never>, for url: URL) {
        lock.lock()
        defer { lock.unlock() }
        inFlightTasks[url] = task
    }

    private func removeInFlightTask(for url: URL) {
        lock.lock()
        defer { lock.unlock() }
        inFlightTasks.removeValue(forKey: url)
    }

    private func store(_ image: NSImage, for url: URL) {
        let pixelWidth = Int(max(image.size.width, 1))
        let pixelHeight = Int(max(image.size.height, 1))
        let estimatedCost = max(pixelWidth * pixelHeight * 4, 1)
        cache.setObject(image, forKey: url as NSURL, cost: estimatedCost)
    }

    private func persistToDisk(_ data: Data, for url: URL) {
        let fileURL = diskFileURL(for: url)
        if
            fileManager.fileExists(atPath: fileURL.path),
            let existingData = try? Data(contentsOf: fileURL),
            Self.decodeImage(from: existingData) != nil
        {
            return
        }
        try? data.write(to: fileURL, options: .atomic)
        pruneDiskCacheIfNeeded(maxBytes: diskCacheSizeLimit)
    }

    private func diskFileURL(for url: URL) -> URL {
        diskCacheDirectory.appendingPathComponent(Self.diskCacheKey(for: url), isDirectory: false)
    }

    private static func diskCacheKey(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func diskImage(for url: URL) -> NSImage? {
        let fileURL = diskFileURL(for: url)
        guard
            let data = try? Data(contentsOf: fileURL),
            let image = Self.decodeImage(from: data)
        else {
            return nil
        }
        store(image, for: url)
        return image
    }

    private func pruneDiskCacheIfNeeded(maxBytes: Int) {
        guard
            let fileURLs = try? fileManager.contentsOfDirectory(
                at: diskCacheDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return
        }

        var entries: [(url: URL, size: Int, modified: Date)] = []
        var totalSize = 0

        for fileURL in fileURLs {
            let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let size = values?.fileSize ?? 0
            let modified = values?.contentModificationDate ?? .distantPast
            totalSize += size
            entries.append((fileURL, size, modified))
        }

        guard totalSize > maxBytes else { return }

        for entry in entries.sorted(by: { $0.modified < $1.modified }) {
            try? fileManager.removeItem(at: entry.url)
            totalSize -= entry.size
            if totalSize <= maxBytes {
                break
            }
        }
    }

    private static func decodeImage(from data: Data) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return NSImage(data: data)
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 960
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return NSImage(data: data)
        }

        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
    }
}
