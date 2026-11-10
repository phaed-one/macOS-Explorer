import AppKit
import PathfindCore
import QuickLookThumbnailing

final class FilePreviewImageView: NSImageView {
    private var request: QLThumbnailGenerator.Request?

    deinit {
        if let request { QLThumbnailGenerator.shared.cancel(request) }
    }

    func configure(for entry: FileEntry, size: CGFloat, scale: CGFloat) {
        if let request { QLThumbnailGenerator.shared.cancel(request) }
        request = nil
        image = NSWorkspace.shared.icon(forFile: entry.url.path)
        imageScaling = .scaleProportionallyUpOrDown
        alphaValue = entry.isHidden ? 0.5 : 1
        guard !entry.isDirectory else { return }

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
                if let thumbnail { self.image = thumbnail.nsImage }
            }
        }
    }
}
