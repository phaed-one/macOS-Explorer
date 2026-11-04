import AppKit
import CoreServices

/// Owns the macOS file viewer preference that "Show in Finder" requests follow.
/// macOS 26 rejects every request to change the `public.folder` handler (OSStatus -50,
/// even for Finder itself), so folder opening stays with Finder.
enum DefaultFileManager {
    static let finderID = "com.apple.finder"
    static var bundleID: String { Bundle.main.bundleIdentifier ?? "local.pathfind.app" }
    static var viewerID: String? {
        CFPreferencesCopyValue("NSFileViewer" as CFString, kCFPreferencesAnyApplication,
                               kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? String
    }
    static var isDefault: Bool { viewerID == bundleID }
    static func useExplorer() throws {
        let status = LSRegisterURL(Bundle.main.bundleURL as CFURL, true)
        guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        try setViewer(bundleID)
    }
    static func restoreFinder() throws { try setViewer(finderID) }
    private static func setViewer(_ identifier: String) throws {
        CFPreferencesSetValue("NSFileViewer" as CFString, identifier as CFString,
                              kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        guard CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError,
                          userInfo: [NSLocalizedDescriptionKey: "macOS could not save the default file viewer."])
        }
    }
}

enum FileViewerRequest {
    static func urls(in event: NSAppleEventDescriptor) -> [URL] {
        guard let object = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject)) else { return [] }
        let items = object.descriptorType == typeAEList
            ? (0..<object.numberOfItems).compactMap { object.atIndex($0 + 1) } : [object]
        return items.compactMap { item in
            guard let descriptor = item.coerce(toDescriptorType: DescType(typeFileURL)),
                  let url = URL(dataRepresentation: descriptor.data, relativeTo: nil), url.isFileURL else { return nil }
            return url.standardizedFileURL
        }
    }
}
