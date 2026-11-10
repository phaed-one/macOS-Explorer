import AppKit
import PathfindCore
import QuickLookThumbnailing

final class FilePreviewImageView: NSImageView {
    // App activation refreshes the folder and can recreate both list and grid items.
    private static let thumbnails: NSCache<NSArray, NSImage> = {
        let cache = NSCache<NSArray, NSImage>()
        cache.countLimit = 2_048
        cache.totalCostLimit = 32 * 1_024 * 1_024
        return cache
    }()
    private var request: QLThumbnailGenerator.Request?

    deinit {
        if let request { QLThumbnailGenerator.shared.cancel(request) }
    }

    func configure(for entry: FileEntry, size: CGFloat, scale: CGFloat) {
        if let request { QLThumbnailGenerator.shared.cancel(request) }
        request = nil
        imageScaling = .scaleProportionallyUpOrDown
        alphaValue = entry.isHidden ? 0.5 : 1
        guard !entry.isDirectory else {
            image = NSWorkspace.shared.icon(forFile: entry.url.path)
            return
        }

        let key = [entry.url, entry.modified, entry.size, size, scale] as NSArray
        if let thumbnail = Self.thumbnails.object(forKey: key) {
            image = thumbnail
            return
        }
        image = NSWorkspace.shared.icon(forFile: entry.url.path)

        let request = QLThumbnailGenerator.Request(
            fileAt: entry.url, size: CGSize(width: size, height: size), scale: scale,
            representationTypes: [.thumbnail, .lowQualityThumbnail]
        )
        request.iconMode = true
        self.request = request
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] thumbnail, _ in
            DispatchQueue.main.async {
                // Collection view items can represent a different file by the time Quick Look replies.
                guard let self, self.request === request else { return }
                self.request = nil
                guard let thumbnail else { return }
                let image = thumbnail.nsImage
                let pixels = Int(ceil(size * scale))
                Self.thumbnails.setObject(image, forKey: key, cost: pixels * pixels * 4)
                self.image = image
            }
        }
    }
}
