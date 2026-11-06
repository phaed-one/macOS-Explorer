import Foundation

enum ConfirmationPreference: String, CaseIterable {
    case moveToTrash = "confirmMoveToTrash"
    case clearTrash = "confirmClearTrash"

    var title: String {
        switch self {
        case .moveToTrash: return "Ask before moving items to Trash"
        case .clearTrash: return "Ask before clearing Trash"
        }
    }

    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: rawValue) as? Bool ?? true }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: rawValue) }
    }
}
