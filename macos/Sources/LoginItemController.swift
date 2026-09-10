import AppKit
import ServiceManagement

protocol LoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LoginItemService {}

final class LoginItemController {
    private let service: LoginItemService
    init(service: LoginItemService = SMAppService.mainApp) { self.service = service }
    var status: SMAppService.Status { service.status }
    var menuState: NSControl.StateValue {
        switch status {
        case .enabled: return .on
        case .requiresApproval: return .mixed
        default: return .off
        }
    }
    var statusDescription: String {
        switch status {
        case .enabled: return "enabled"
        case .requiresApproval: return "requires-approval"
        case .notRegistered: return "disabled"
        case .notFound: return "not-found"
        @unknown default: return "unknown"
        }
    }
    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if status != .enabled && status != .requiresApproval { try service.register() }
        } else if status == .enabled || status == .requiresApproval {
            try service.unregister()
        }
    }
    static func isLoginLaunch(_ event: NSAppleEventDescriptor?) -> Bool {
        event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
}
