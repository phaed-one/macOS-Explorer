import AppKit
import CoreServices

/// Owns the macOS preferences for opening folders and revealing files.
enum DefaultFileManager {
    static let finderID = "com.apple.finder"
    static var bundleID: String { Bundle.main.bundleIdentifier ?? "local.pathfind.app" }
    static var viewerID: String? {
        CFPreferencesCopyValue("NSFileViewer" as CFString, kCFPreferencesAnyApplication,
                               kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? String
    }
    static var folderHandlerID: String? {
        LSCopyDefaultRoleHandlerForContentType("public.folder" as CFString, .all)?.takeRetainedValue() as String?
    }
    static var isDefault: Bool { viewerID == bundleID && folderHandlerID == bundleID }
    static func useExplorer() throws {
        let status = LSRegisterURL(Bundle.main.bundleURL as CFURL, true)
        guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        try setHandler(bundleID)
    }
    static func restoreFinder() throws { try setHandler(finderID) }
    private static func setHandler(_ identifier: String) throws {
        let previous = folderHandlerID ?? finderID
        let status = LSSetDefaultRoleHandlerForContentType("public.folder" as CFString, .all, identifier as CFString)
        guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        CFPreferencesSetValue("NSFileViewer" as CFString, identifier as CFString,
                              kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        guard CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else {
            LSSetDefaultRoleHandlerForContentType("public.folder" as CFString, .all, previous as CFString)
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
