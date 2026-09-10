import AppKit

@main struct Render {
    static func main() throws {
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        let fixture = URL(fileURLWithPath: CommandLine.arguments[2])
        let tracks = try Track.parse(Data(contentsOf: fixture))
        let suite = "youtube-music-render-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(try JSONEncoder().encode(QueueState(tracks: tracks, index: min(2, max(0, tracks.count - 1)))), forKey: "queue")
        let store = PlayerStore(client: YouTubeClient(tools: URL(fileURLWithPath: CommandLine.arguments[3])), defaults: defaults, enableMediaControls: false, enablePreloading: false)
        defer { store.shutdown() }
        let controller = PlayerViewController(store: store)
        store.changed = { controller.render() }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 460), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentViewController = controller
        controller.view.appearance = window.appearance
        controller.render()
        if CommandLine.arguments.contains("--search") {
            controller.focusSearch()
            controller.searchField.stringValue = "Tycho Awake"
            store.search("Tycho Awake")
        }
        RunLoop.main.run(until: Date().addingTimeInterval(CommandLine.arguments.contains("--search") ? 7 : 3))
        window.displayIfNeeded()
        controller.view.layoutSubtreeIfNeeded()
        let image = controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds)!
        controller.view.cacheDisplay(in: controller.view.bounds, to: image)
        try image.representation(using: .png, properties: [:])!.write(to: output)
        print("Rendered the native player view to \(output.path)")
    }
}
