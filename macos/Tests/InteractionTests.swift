import AppKit

final class InteractionClient: MusicClient {
    var available = true
    var requests: [(Result<[Track], Error>) -> Void] = []
    func search(_ query: String, completion: @escaping (Result<[Track], Error>) -> Void) -> Extraction {
        requests.append(completion); return Extraction()
    }
    func mix(_ seed: Track, completion: @escaping (Result<[Track], Error>) -> Void) -> Extraction { Extraction() }
    func stream(_ track: Track, completion: @escaping (Result<URL, Error>) -> Void) -> Extraction { Extraction() }
}

@main struct InteractionTests {
    static func main() throws {
        _ = NSApplication.shared
        let suite = "youtube-music-interaction-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let a = Track(id: "abcdefghijk", title: "A", artist: "Test", duration: 120, isLive: false)
        let b = Track(id: "lmnopqrstuv", title: "B", artist: "Test", duration: 120, isLive: false)
        defaults.set(try JSONEncoder().encode(QueueState(tracks: [a], index: 0)), forKey: "queue")
        let client = InteractionClient()
        let store = PlayerStore(client: client, defaults: defaults, enableMediaControls: false, enablePreloading: false)
        defer { store.shutdown() }
        let controller = PlayerViewController(store: store)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 460), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentViewController = controller
        _ = controller.view
        store.changed = { controller.render() }
        precondition(!controller.searchExpanded && !controller.artwork.isHidden)
        controller.toggleSearch()
        precondition(controller.searchExpanded && !controller.artwork.isHidden, "Revealing search must keep the player visible")
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        precondition(controller.searchField.superview!.frame.maxX == 326)
        precondition(controller.searchField.superview!.frame.width == 160)
        precondition(controller.searchField.frame.width > 100, "Search text must expand inside the capsule")
        let magnifier = controller.searchField.superview!.subviews.first { $0 is NSButton }!
        precondition(magnifier.frame.maxX == 160, "The magnifier must stay at the trailing edge")
        let capsule = controller.searchField.superview!
        controller.searchField.stringValue = "zelda 40th anniversary"
        controller.render()
        let mediumWidth = capsule.frame.width
        precondition(mediumWidth > 160, "The search capsule must grow with the query")
        controller.searchField.stringValue = "zelda 40th anniversary orchestra full concert original soundtrack"
        controller.render()
        precondition(capsule.frame.width > mediumWidth && capsule.frame.maxX == 326)
        let name = controller.view.subviews.compactMap { $0 as? NSTextField }.first { $0.stringValue == "Motif" }!
        precondition(capsule.frame.minX >= name.frame.maxX + 12, "Search must leave space for the app name")
        precondition(controller.searchField.frame.maxX <= magnifier.frame.minX && controller.searchField.frame.height == 18)
        precondition(controller.searchField.cell?.usesSingleLineMode == true && controller.searchField.lineBreakMode == .byTruncatingTail)
        window.makeFirstResponder(nil)
        controller.focusSearch()
        guard let editor = controller.searchField.currentEditor() as? NSTextView,
              let layout = editor.layoutManager, let container = editor.textContainer else { fatalError("Missing search editor") }
        layout.ensureLayout(for: container)
        var lines = 0
        layout.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: layout.numberOfGlyphs)) { _, _, _, _, _ in lines += 1 }
        precondition(lines == 1, "A long query must stay on one line while editing")
        precondition(editor.insertionPointColor == PlayerTheme.accent)
        window.makeFirstResponder(nil)
        controller.searchField.stringValue = ""
        controller.render()
        precondition(capsule.frame.width == 160, "Clearing the query must shrink the capsule")
        controller.toggleSearch()
        precondition(!controller.searchExpanded)
        controller.focusSearch()
        controller.searchField.stringValue = "ab"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        precondition(controller.artwork.isHidden && controller.scroll.frame.height == 399)
        precondition(client.requests.isEmpty, "Search must wait for the debounce")
        RunLoop.main.run(until: Date().addingTimeInterval(0.65))
        precondition(client.requests.count == 1)
        client.requests[0](.success([a, b]))
        controller.selectRow(1)
        precondition(store.current == b && !store.showingSearch)
        precondition(!controller.searchExpanded && !controller.artwork.isHidden)
        precondition(controller.scroll.frame.height == 90)
        precondition(controller.audioLoading.isAnimating && !controller.audioLoading.isHidden,
                     "Audio loading belongs over the artwork")
        precondition(controller.audioLoading.superview === controller.artwork)
        precondition(controller.status.stringValue.isEmpty && controller.status.isHidden,
                     "Do not show loading audio in the footer")
        store.pause()
        precondition(!controller.audioLoading.isAnimating && controller.audioLoading.isHidden)
        store.resume()
        precondition(controller.audioLoading.isAnimating, "Resuming a pending stream must restore the spinner")
        controller.focusSearch()
        store.search("later")
        store.editQuery("")
        client.requests[1](.success([a]))
        precondition(!store.showingSearch && store.current == b && store.results.isEmpty,
                     "Clearing search must restore the queue and reject the old request")
        precondition(!controller.artwork.isHidden && controller.searchExpanded)
        store.message = "Couldn't reach YouTube"
        controller.render()
        precondition(!controller.status.isHidden && controller.status.stringValue == store.message,
                     "Playback errors must remain visible")
        print("PASS: growing single-line search, truncation, red caret, search toggle, debounce, artwork spinner, playback selection, stale search rejection")
    }
}
