import UIKit

/// Two-layer image cache: NSCache (in-memory) + disk (Caches directory).
/// Thread-safe via actor isolation.
actor ImageCacheService {
    static let shared = ImageCacheService()

    private let memoryCache = NSCache<NSString, UIImage>()
    private let diskCacheURL: URL
    private let maxDiskSize: Int = 200 * 1024 * 1024 // 200MB
    private let session: URLSession
    private let memoryPressureObserver: any NSObjectProtocol

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.diskCacheURL = caches.appendingPathComponent("ImageCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)

        memoryCache.countLimit = 150
        memoryCache.totalCostLimit = 80 * 1024 * 1024 // 80MB

        let config = URLSessionConfiguration.default
        config.urlCache = nil // We handle caching ourselves
        self.session = URLSession(configuration: config)

        // Flush memory cache on memory pressure
        nonisolated(unsafe) let cache = memoryCache
        self.memoryPressureObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: nil
        ) { _ in
            cache.removeAllObjects()
        }
    }

    /// Returns cached image or downloads, caches, and returns it.
    func image(for url: URL) async throws -> UIImage {
        let key = cacheKey(for: url)

        // 1. Memory cache
        if let cached = memoryCache.object(forKey: key as NSString) {
            return cached
        }

        // 2. Disk cache
        var diskURL = diskCacheURL.appendingPathComponent(key)
        if let data = try? Data(contentsOf: diskURL),
           let image = UIImage(data: data) {
            let cost = data.count
            memoryCache.setObject(image, forKey: key as NSString, cost: cost)
            // Touch file for LRU
            try? FileManager.default.setAttributes(
                [.modificationDate: Date()],
                ofItemAtPath: diskURL.path
            )
            return image
        }

        // 3. Download
        let (data, _) = try await session.data(from: url)
        guard let image = UIImage(data: data) else {
            throw ImageCacheError.invalidImageData
        }

        // Store in memory
        memoryCache.setObject(image, forKey: key as NSString, cost: data.count)

        // Store on disk (fire-and-forget, excluded from backup)
        try? data.write(to: diskURL, options: .atomic)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? diskURL.setResourceValues(resourceValues)
        evictDiskIfNeeded()

        return image
    }

    /// Returns a pre-blurred, downsampled background image for `url`.
    /// Blurring happens here on the actor (off the main thread) so the immersive
    /// background never runs a live SwiftUI `.blur` during layout — see
    /// `BackgroundBlur` for why that hung the main thread (DUMPERT-APPLE-TV-4).
    /// The blurred bitmap is cached separately so repeated focus hops are free.
    func blurredBackgroundImage(for url: URL) async throws -> UIImage {
        let blurKey = "blur:\(cacheKey(for: url))" as NSString
        if let cached = memoryCache.object(forKey: blurKey) {
            return cached
        }
        let source = try await image(for: url)
        let blurred = BackgroundBlur.apply(to: source)
        // Downsampled bitmap: ~480px longest edge, so ~1MB cost at most.
        memoryCache.setObject(blurred, forKey: blurKey, cost: 480 * 480 * 4)
        return blurred
    }

    func clearAll() {
        memoryCache.removeAllObjects()
        try? FileManager.default.removeItem(at: diskCacheURL)
        try? FileManager.default.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
    }

    func diskSize() -> Int {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: diskCacheURL, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total = 0
        for case let fileURL as URL in enumerator {
            total += (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        }
        return total
    }

    // MARK: - Private

    private func cacheKey(for url: URL) -> String {
        // SHA256-like stable key from URL string
        let str = url.absoluteString
        var hash: UInt64 = 5381
        for byte in str.utf8 {
            hash = 127 &* (hash & 0x00ffffffffffffff) &+ UInt64(byte)
        }
        let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
        return "\(hash).\(ext)"
    }

    /// Evicts oldest disk cache files on a background thread to avoid blocking image loading.
    private func evictDiskIfNeeded() {
        let cacheURL = diskCacheURL
        let maxSize = maxDiskSize
        Task.detached(priority: .utility) {
            let fm = FileManager.default
            let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
            guard let allFiles = try? fm.contentsOfDirectory(
                at: cacheURL,
                includingPropertiesForKeys: keys
            ) else { return }

            var currentSize = 0
            var files: [(url: URL, date: Date, size: Int)] = []
            for fileURL in allFiles {
                let values = try? fileURL.resourceValues(forKeys: Set(keys))
                let size = values?.fileSize ?? 0
                currentSize += size
                files.append((
                    url: fileURL,
                    date: values?.contentModificationDate ?? .distantPast,
                    size: size
                ))
            }
            guard currentSize > maxSize else { return }

            files.sort { $0.date < $1.date }

            let targetSize = maxSize * 3 / 4
            var freed = 0
            let bytesToFree = currentSize - targetSize

            for file in files {
                guard freed < bytesToFree else { break }
                try? fm.removeItem(at: file.url)
                freed += file.size
            }
        }
    }
}

enum ImageCacheError: Error {
    case invalidImageData
}
