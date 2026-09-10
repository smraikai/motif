import AppKit

final class ArtworkView: NSImageView {
    private var request: URLSessionDataTask?
    private var artworkID = ""
    private static let cache = NSCache<NSString, NSImage>()
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
        imageScaling = .scaleProportionallyUpOrDown
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        guard let image, !image.isTemplate, image.size.height > 0 else { super.draw(dirtyRect); return }
        let targetRatio = bounds.width / max(1, bounds.height)
        let sourceRatio = image.size.width / image.size.height
        var source = NSRect(origin: .zero, size: image.size)
        if sourceRatio > targetRatio {
            source.size.width = source.height * targetRatio
            source.origin.x = (image.size.width - source.width) / 2
        } else {
            source.size.height = source.width / targetRatio
            source.origin.y = (image.size.height - source.height) / 2
        }
        image.draw(in: bounds, from: source, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
    func show(_ track: Track?) {
        guard artworkID != (track?.id ?? "empty") else { return }
        artworkID = track?.id ?? "empty"
        request?.cancel()
        image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "Album artwork")
        contentTintColor = .secondaryLabelColor
        guard let track else { return }
        if let cached = Self.cache.object(forKey: track.id as NSString) { image = cached; return }
        request = URLSession.shared.dataTask(with: track.artworkURL) { [weak self] data, _, _ in
            guard let data, let image = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                Self.cache.setObject(image, forKey: track.id as NSString)
                if self?.artworkID == track.id { self?.image = image }
            }
        }
        request?.resume()
    }
}

func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
    let view = NSTextField(labelWithString: text)
    view.font = .systemFont(ofSize: size, weight: weight)
    view.textColor = color
    view.lineBreakMode = .byTruncatingTail
    return view
}
func iconButton(_ symbol: String, _ help: String, target: AnyObject?, action: Selector) -> NSButton {
    let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: help)!, target: target, action: action)
    button.bezelStyle = .inline
    button.isBordered = false
    button.imageScaling = .scaleProportionallyDown
    button.toolTip = help
    button.setAccessibilityLabel(help)
    return button
}

final class TrackCell: NSTableCellView {
    let artwork = ArtworkView(frame: NSRect(x: 4, y: 8, width: 32, height: 32))
    let titleLabel = label("", size: 12, weight: .medium)
    let artistLabel = label("", size: 11, color: .secondaryLabelColor)
    let durationLabel = label("", size: 10, color: .secondaryLabelColor)
    var mixButton: NSButton!
    private var hoverArea: NSTrackingArea?
    var preparePlayback: (() -> Void)?
    private var hoverTimer: Timer?
    override init(frame: NSRect) {
        super.init(frame: frame)
        [artwork, titleLabel, artistLabel, durationLabel].forEach(addSubview)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        hoverArea = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(hoverArea!)
    }
    override func mouseEntered(with event: NSEvent) {
        mixButton?.alphaValue = 1
        hoverTimer?.invalidate()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: false) { [weak self] _ in self?.preparePlayback?() }
    }
    override func mouseExited(with event: NSEvent) { mixButton?.alphaValue = 0; hoverTimer?.invalidate() }
    override func layout() {
        super.layout()
        let artSize = bounds.height - 8
        artwork.frame = NSRect(x: 4, y: 4, width: artSize, height: artSize)
        let left = artSize + 12
        titleLabel.frame = NSRect(x: left, y: bounds.height / 2, width: bounds.width - left - 74, height: 16)
        artistLabel.frame = NSRect(x: left, y: 3, width: bounds.width - left - 74, height: 14)
        durationLabel.frame = NSRect(x: bounds.width - 70, y: (bounds.height - 16) / 2, width: 40, height: 16)
        durationLabel.alignment = .right
        mixButton?.frame = NSRect(x: bounds.width - 25, y: (bounds.height - 24) / 2, width: 24, height: 24)
    }
}

final class PlayerBackground: NSView {
    var clicked: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) { clicked?() }
}

class AccentSliderCell: NSSliderCell {
    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let track = NSRect(x: rect.minX, y: rect.midY - 1.5, width: rect.width, height: 3)
        NSColor(white: 0.32, alpha: 1).setFill()
        NSBezierPath(roundedRect: track, xRadius: 1.5, yRadius: 1.5).fill()
        let fraction = (doubleValue - minValue) / max(1, maxValue - minValue)
        let fill = NSRect(x: track.minX, y: track.minY, width: track.width * min(1, max(0, fraction)), height: 3)
        PlayerTheme.accent.setFill()
        NSBezierPath(roundedRect: fill, xRadius: 1.5, yRadius: 1.5).fill()
    }
    override func drawKnob(_ knobRect: NSRect) {
        NSColor.white.setFill()
        NSBezierPath(ovalIn: knobRect.insetBy(dx: 2, dy: 2)).fill()
    }
}
final class ProgressCell: AccentSliderCell {
    override func drawKnob(_ knobRect: NSRect) {}
}

final class PlayerRow: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        PlayerTheme.accent.withAlphaComponent(0.14).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6).fill()
    }
}

final class PlayerViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    let store: PlayerStore
    let searchField = NSTextField()
    private let searchPill = NSView()
    private var headerVisibleState: Bool?
    private var headerQuery: String?
    let table = NSTableView()
    let scroll = NSScrollView()
    let artwork = ArtworkView(frame: .zero)
    let audioLoading = ArtworkLoadingView(frame: .zero)
    let trackTitle = label("", size: 15, weight: .semibold)
    let artist = label("", size: 12, color: .secondaryLabelColor)
    let elapsed = label("0:00", size: 10, color: .secondaryLabelColor)
    let remaining = label("0:00", size: 10, color: .secondaryLabelColor)
    let status = label("", size: 10, color: .secondaryLabelColor)
    let heading = label("Up next", size: 12, weight: .semibold)
    let empty = label("Search for something worth hearing", size: 12, color: .secondaryLabelColor)
    let progress = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let name = label("Motif", size: 12, weight: .semibold)
    private let rule = NSBox()
    var play: NSButton!
    private var searchButton: NSButton!
    private var playerViews: [NSView] = []
    private var lastTracks: [Track] = []
    private var lastCurrent = ""
    private var lastSearchMode = false
    private var debounce: Timer?
    private(set) var searchExpanded = false
    var close: (() -> Void)?
    private var monitor: Any?

    init(store: PlayerStore) { self.store = store; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }
    override func loadView() {
        let background = PlayerBackground(frame: NSRect(x: 0, y: 0, width: 340, height: 460))
        background.clicked = { [weak self] in self?.collapseSearch() }
        view = background
        view.appearance = NSAppearance(named: .darkAqua)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(white: 0.07, alpha: 1).cgColor
        preferredContentSize = view.frame.size

        place(name, x: 14, y: 425, w: 230, h: 22)
        searchPill.wantsLayer = true
        searchPill.layer?.cornerRadius = 15
        searchPill.layer?.masksToBounds = true
        place(searchPill, x: 296, y: 421, w: 30, h: 30)
        searchField.placeholderString = "Search music…"
        searchField.font = .systemFont(ofSize: 12)
        searchField.isBezeled = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.maximumNumberOfLines = 1
        searchField.cell?.usesSingleLineMode = true
        searchField.cell?.isScrollable = true
        searchField.lineBreakMode = .byTruncatingTail
        searchField.delegate = self
        searchField.target = self; searchField.action = #selector(search)
        searchField.setAccessibilityLabel("Search music")
        // Keep the text field at its final width; the animated capsule clips it.
        // Frame animation can bypass NSView.setFrameSize, so child layout must
        // not depend on that override being called.
        searchField.frame = NSRect(x: 12, y: 7, width: 154, height: 18)
        searchField.alphaValue = 0
        searchPill.addSubview(searchField)
        searchButton = iconButton("magnifyingglass", "Search music, Command-K", target: self, action: #selector(searchClicked))
        searchButton.frame = NSRect(x: 0, y: 0, width: 30, height: 30)
        searchButton.autoresizingMask = .minXMargin
        searchPill.addSubview(searchButton)

        // Same vertical sequence as the plugin, scaled to the compact popup.
        place(artwork, x: 98, y: 270, w: 144, h: 144)
        audioLoading.frame = artwork.bounds
        audioLoading.autoresizingMask = [.width, .height]
        artwork.addSubview(audioLoading)
        place(trackTitle, x: 14, y: 243, w: 312, h: 21)
        place(artist, x: 14, y: 224, w: 312, h: 18)
        place(elapsed, x: 14, y: 198, w: 47, h: 16)
        remaining.alignment = .right
        place(remaining, x: 279, y: 198, w: 47, h: 16)
        progress.cell = ProgressCell()
        progress.target = self; progress.action = #selector(seek)
        progress.isContinuous = false
        progress.setAccessibilityLabel("Playback position")
        place(progress, x: 66, y: 196, w: 208, h: 20)

        let previous = iconButton("backward.end.fill", "Previous track", target: self, action: #selector(previousTrack))
        play = iconButton("play.fill", "Play or pause", target: self, action: #selector(togglePlayback))
        play.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        play.wantsLayer = true
        play.layer?.cornerRadius = 18
        play.layer?.borderWidth = 1
        play.layer?.borderColor = PlayerTheme.accent.cgColor
        play.contentTintColor = PlayerTheme.accent
        let next = iconButton("forward.end.fill", "Next track", target: self, action: #selector(nextTrack))
        let mix = iconButton("dot.radiowaves.left.and.right", "Build a mix from this track", target: self, action: #selector(currentMix))
        mix.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        place(previous, x: 110, y: 153, w: 26, h: 28)
        place(play, x: 152, y: 149, w: 36, h: 36)
        place(next, x: 204, y: 153, w: 26, h: 28)
        place(mix, x: 296, y: 153, w: 30, h: 28)
        rule.boxType = .separator
        place(rule, x: 14, y: 137, w: 312, h: 1)
        place(heading, x: 14, y: 111, w: 312, h: 18)
        playerViews = [artwork, trackTitle, artist, elapsed, remaining, progress, previous, play, next, mix, rule, heading]

        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("track"))
        column.width = 304; column.resizingMask = .autoresizingMask
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 38
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .regular
        table.style = .plain
        table.dataSource = self; table.delegate = self
        table.target = self; table.action = #selector(clickRow)
        table.setAccessibilityLabel("Tracks. Click or press Return to play.")
        scroll.documentView = table
        place(scroll, x: 10, y: 10, w: 320, h: 96)
        empty.alignment = .center
        empty.maximumNumberOfLines = 3
        place(empty, x: 20, y: 191, w: 300, h: 50)
        status.lineBreakMode = .byTruncatingTail
        place(status, x: 14, y: 1, w: 312, h: 13)
        searchExpanded = store.current == nil
        render()
    }
    private func place(_ child: NSView, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) {
        child.frame = NSRect(x: x, y: y, width: w, height: h)
        view.addSubview(child)
    }
    override func viewDidAppear() {
        super.viewDidAppear()
        if store.current == nil || store.showingSearch || !searchField.stringValue.isEmpty { focusSearch() }
        else { view.window?.makeFirstResponder(view) }
        if monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, event.window === self.view.window else { return event }
                if event.keyCode == 53 { self.close?(); return nil }
                if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "k" {
                    self.toggleSearch(); return nil
                }
                let editing = self.view.window?.firstResponder is NSTextView
                if !editing && event.keyCode == 49 { self.store.toggle(); return nil }
                if !editing && event.keyCode == 36 { self.activateRow(); return nil }
                if !editing && event.keyCode == 126 && self.table.selectedRow <= 0 { self.focusSearch(); return nil }
                if event.modifierFlags.contains(.command), event.keyCode == 124 { self.store.next(); return nil }
                if event.modifierFlags.contains(.command), event.keyCode == 123 { self.store.previous(); return nil }
                return event
            }
        }
    }
    override func viewDidDisappear() {
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        collapseSearch()
        audioLoading.setLoading(false)
        super.viewDidDisappear()
    }
    func focusSearch() {
        searchExpanded = true; updateSearchHeader(animated: true); render()
        view.window?.makeFirstResponder(searchField)
        styleSearchEditor()
    }
    func collapseSearch() {
        searchExpanded = false
        updateSearchHeader(animated: true)
        view.window?.makeFirstResponder(view)
        render()
    }
    func toggleSearch() { searchExpanded ? collapseSearch() : focusSearch() }

    private func updateSearchHeader(animated: Bool) {
        guard isViewLoaded else { return }
        let wasExpanded = headerVisibleState
        headerVisibleState = searchExpanded
        headerQuery = searchField.stringValue
        let query = searchField.stringValue.isEmpty ? (searchField.placeholderString ?? "") : searchField.stringValue
        let textWidth = (query as NSString).size(withAttributes: [.font: searchField.font!]).width
        let maximumWidth = 326 - 14 - max(48, ceil(name.intrinsicContentSize.width)) - 12
        let width: CGFloat = searchExpanded ? min(maximumWidth, max(160, ceil(textWidth) + 46)) : 30
        searchField.isEnabled = searchExpanded
        if searchExpanded {
            searchField.frame = NSRect(x: 12, y: 7, width: width - 46, height: 18)
        }
        searchPill.layer?.backgroundColor = (searchExpanded ? NSColor(white: 0.14, alpha: 1) : .clear).cgColor
        let changes = {
            self.searchPill.animator().frame = NSRect(x: 326 - width, y: 421, width: width, height: 30)
            self.name.animator().setFrameSize(NSSize(width: min(230, 326 - width - 14 - 12), height: 22))
            self.searchField.animator().alphaValue = self.searchExpanded ? 1 : 0
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated && wasExpanded != nil ? (self.searchExpanded ? 0.145 : 0.11) : 0
            changes()
        }
    }
    func render() {
        guard isViewLoaded else { return }
        let browsing = store.current == nil || store.showingSearch
        if headerVisibleState != searchExpanded || headerQuery != searchField.stringValue { updateSearchHeader(animated: false) }
        for child in playerViews { child.isHidden = browsing }
        scroll.frame = browsing ? NSRect(x: 10, y: 16, width: 320, height: 399) : NSRect(x: 10, y: 16, width: 320, height: 90)
        table.rowHeight = browsing ? 46 : 36
        artwork.show(store.current)
        audioLoading.setLoading(store.loading && !browsing)
        trackTitle.stringValue = store.current?.title ?? ""
        trackTitle.toolTip = store.current?.title
        artist.stringValue = store.current?.artist ?? ""
        elapsed.stringValue = clockTime(store.position)
        remaining.stringValue = store.current?.isLive == true ? "LIVE" : (store.duration > 0 ? clockTime(store.duration) : store.current?.durationLabel ?? "0:00")
        progress.maxValue = max(1, store.duration)
        progress.doubleValue = store.position
        progress.isEnabled = store.duration > 0
        play.image = NSImage(systemSymbolName: store.playing || store.loading ? "pause.fill" : "play.fill", accessibilityDescription: "Play or pause")
        play.isEnabled = store.current != nil
        heading.stringValue = store.mixing && !store.loading ? "Building mix…" : "Up next"
        status.stringValue = store.message
        status.isHidden = store.message.isEmpty
        status.toolTip = store.message
        empty.isHidden = !browsing || !store.displayedTracks.isEmpty
        empty.stringValue = store.searching ? "Searching YouTube…" : (!store.message.isEmpty ? store.message : (store.query.isEmpty ? "Search for something worth hearing" : "No tracks found"))
        if lastTracks != store.displayedTracks || lastCurrent != store.current?.id || lastSearchMode != store.showingSearch {
            lastTracks = store.displayedTracks; lastCurrent = store.current?.id ?? ""
            table.reloadData()
            if !browsing, store.queue.current != nil {
                table.selectRowIndexes(IndexSet(integer: store.queue.index), byExtendingSelection: false)
                table.scrollRowToVisible(store.queue.index)
            } else if !lastTracks.isEmpty {
                table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
                table.scrollRowToVisible(0)
            }
        }
        lastSearchMode = store.showingSearch
    }
    func numberOfRows(in tableView: NSTableView) -> Int { store.displayedTracks.count }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { PlayerRow() }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard store.displayedTracks.indices.contains(row) else { return nil }
        let track = store.displayedTracks[row]
        let cell = TrackCell(frame: NSRect(x: 0, y: 0, width: 304, height: table.rowHeight))
        cell.preparePlayback = { [weak store] in store?.prepareForSelection(track) }
        cell.artwork.show(track)
        cell.titleLabel.stringValue = track.title
        cell.titleLabel.textColor = track.id == store.current?.id ? PlayerTheme.accent : .labelColor
        cell.artistLabel.stringValue = track.artist
        cell.alphaValue = !store.showingSearch && row < store.queue.index ? 0.45 : 1
        cell.durationLabel.stringValue = track.durationLabel
        cell.toolTip = "\(track.title)\n\(track.artist)\nClick to play"
        cell.mixButton = iconButton("dot.radiowaves.left.and.right", "Start a mix", target: self, action: #selector(rowMix(_:)))
        cell.mixButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        cell.mixButton.tag = row
        cell.mixButton.alphaValue = 0
        cell.addSubview(cell.mixButton)
        return cell
    }
    func controlTextDidChange(_ notification: Notification) {
        debounce?.invalidate()
        updateSearchHeader(animated: true)
        store.editQuery(searchField.stringValue)
        guard store.query.count >= 2 else { return }
        debounce = Timer.scheduledTimer(withTimeInterval: 0.55, repeats: false) { [weak self] _ in self?.search() }
    }
    func controlTextDidBeginEditing(_ notification: Notification) { styleSearchEditor() }
    private func styleSearchEditor() {
        guard let editor = searchField.currentEditor() as? NSTextView else { return }
        editor.insertionPointColor = PlayerTheme.accent
        editor.selectedTextAttributes = [.backgroundColor: PlayerTheme.accent.withAlphaComponent(0.35),
                                         .foregroundColor: NSColor.labelColor]
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.moveDown(_:)), !store.displayedTracks.isEmpty {
            view.window?.makeFirstResponder(table)
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            return true
        }
        return false
    }
    @objc private func search() { debounce?.invalidate(); store.search(searchField.stringValue) }
    @objc private func searchClicked() {
        if searchExpanded { view.window?.makeFirstResponder(searchField); if !searchField.stringValue.isEmpty { search() } }
        else { focusSearch() }
    }
    @objc private func clickRow() { if table.clickedRow >= 0 { selectRow(table.clickedRow) } }
    func selectRow(_ index: Int) { debounce?.invalidate(); collapseSearch(); store.select(index) }
    @objc func activateRow() { if table.selectedRow >= 0 { selectRow(table.selectedRow) } }
    @objc private func togglePlayback() { collapseSearch(); store.toggle() }
    @objc private func previousTrack() { collapseSearch(); store.previous() }
    @objc private func nextTrack() { collapseSearch(); store.next() }
    @objc private func seek() { store.seek(progress.doubleValue) }
    @objc private func currentMix() { collapseSearch(); if let track = store.current { store.startMix(from: track) } }
    @objc private func rowMix(_ sender: NSButton) {
        guard store.displayedTracks.indices.contains(sender.tag) else { return }
        debounce?.invalidate(); collapseSearch()
        store.startMix(from: store.displayedTracks[sender.tag])
    }
}
