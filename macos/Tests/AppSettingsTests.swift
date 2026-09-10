import AppKit
import ServiceManagement

final class FakeLoginService: LoginItemService {
    var status = SMAppService.Status.notRegistered
    var registrations = 0
    var removals = 0
    var failure: Error?
    func register() throws {
        if let failure { throw failure }
        registrations += 1; status = .enabled
    }
    func unregister() throws {
        if let failure { throw failure }
        removals += 1; status = .notRegistered
    }
}

@main struct AppSettingsTests {
    static func main() throws {
        let suite = "motif-preferences-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let oldQueue = Data("saved queue".utf8)
        defaults.set(0.25, forKey: "volume")
        AppPreferences.migrate(defaults: defaults, legacy: ["queue": oldQueue, "volume": 0.9])
        precondition(defaults.data(forKey: "queue") == oldQueue)
        precondition(defaults.double(forKey: "volume") == 0.25, "Migration must preserve existing Motif settings")
        defaults.removeObject(forKey: "queue")
        AppPreferences.migrate(defaults: defaults, legacy: ["queue": oldQueue])
        precondition(defaults.data(forKey: "queue") == nil, "Do not restore stale legacy data a second time")

        let service = FakeLoginService()
        let controller = LoginItemController(service: service)
        precondition(controller.menuState == .off)
        try controller.setEnabled(true)
        try controller.setEnabled(true)
        precondition(service.registrations == 1 && controller.menuState == .on)
        service.status = .requiresApproval
        precondition(controller.menuState == .mixed && controller.statusDescription == "requires-approval")
        try controller.setEnabled(true)
        precondition(service.registrations == 1, "Don't repeatedly register pending approval")
        try controller.setEnabled(false)
        precondition(service.removals == 1 && controller.menuState == .off)
        service.failure = NSError(domain: "test", code: 1)
        do {
            try controller.setEnabled(true)
            fatalError("Registration errors must reach the UI")
        } catch { precondition(controller.menuState == .off) }

        let event = NSAppleEventDescriptor(eventClass: kCoreEventClass, eventID: kAEOpenApplication,
                                          targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID),
                                          transactionID: AETransactionID(kAnyTransactionID))
        precondition(!LoginItemController.isLoginLaunch(event))
        event.setParam(NSAppleEventDescriptor(enumCode: keyAELaunchedAsLogInItem), forKeyword: keyAEPropData)
        precondition(LoginItemController.isLoginLaunch(event))
        precondition(!LoginItemController.isLoginLaunch(nil))
        print("PASS: preference migration, login-item states, registration errors, quiet login launch detection")
    }
}
