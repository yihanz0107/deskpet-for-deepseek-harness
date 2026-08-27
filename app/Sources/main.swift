import AppKit
import CoreGraphics
import Foundation
import ImageIO
import Network

private enum PetLanguage {
    static var isEnglish = Locale.preferredLanguages.first?.lowercased().hasPrefix("en") == true

    static func text(_ chinese: String, _ english: String) -> String {
        isEnglish ? english : chinese
    }
}

enum PetStatus: String, CaseIterable {
    case idle, waving, jumping, failed, waiting, running, review

    var row: Int {
        switch self {
        case .idle: 0
        case .waving: 3
        case .jumping: 4
        case .failed: 5
        case .waiting: 6
        case .running: 7
        case .review: 8
        }
    }
}

private func focusChromiumTab(applicationName: String, bundleIdentifier: String) -> Bool {
    guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty else { return false }
    let source = """
    tell application "\(applicationName)"
      set targetURL to "http://127.0.0.1:3080"
      repeat with w in windows
        set tabIndex to 0
        repeat with t in tabs of w
          set tabIndex to tabIndex + 1
          if (URL of t starts with targetURL) then
            set active tab index of w to tabIndex
            set index of w to 1
            activate
            return "focused"
          end if
        end repeat
      end repeat
      return "not-found"
    end tell
    """
    var error: NSDictionary?
    return NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue == "focused"
}

private func focusSafariTab() -> Bool {
    guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari").isEmpty else { return false }
    let source = """
    tell application "Safari"
      set targetURL to "http://127.0.0.1:3080"
      repeat with w in windows
        repeat with t in tabs of w
          if (URL of t starts with targetURL) then
            set current tab of w to t
            set index of w to 1
            activate
            return "focused"
          end if
        end repeat
      end repeat
      return "not-found"
    end tell
    """
    var error: NSDictionary?
    return NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue == "focused"
}

private func focusVisibleHarnessWindow() -> Bool {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return false }
    let titleMarkers = ["deepseek harness", "dsh local build"]
    for window in windows {
        guard
            let title = window[kCGWindowName as String] as? String,
            titleMarkers.contains(where: { title.localizedCaseInsensitiveContains($0) }),
            let processID = window[kCGWindowOwnerPID as String] as? pid_t,
            let application = NSRunningApplication(processIdentifier: processID)
        else { continue }
        application.activate(options: [.activateAllWindows])
        return true
    }
    return false
}

@discardableResult
private func focusHarnessWebUI() -> Bool {
    let chromiumBrowsers = [
        ("Google Chrome", "com.google.Chrome"),
        ("Google Chrome Beta", "com.google.Chrome.beta"),
        ("Google Chrome Canary", "com.google.Chrome.canary"),
        ("Microsoft Edge", "com.microsoft.edgemac"),
        ("Brave Browser", "com.brave.Browser"),
        ("Chromium", "org.chromium.Chromium"),
        ("Vivaldi", "com.vivaldi.Vivaldi"),
    ]
    if chromiumBrowsers.contains(where: { focusChromiumTab(applicationName: $0.0, bundleIdentifier: $0.1) }) { return true }
    if focusSafariTab() || focusVisibleHarnessWindow() { return true }

    guard let url = URL(string: "http://127.0.0.1:3080") else { return false }
    NSWorkspace.shared.open(url)
    return false
}

final class PetView: NSView {
    private static let frameCounts = [6, 8, 8, 4, 5, 8, 6, 6, 6]
    private var frames: [[CGImage]] = []
    private var timer: Timer?
    private var interactionTimer: Timer?
    private var frameIndex = 0
    private var status: PetStatus = .idle
    private var interactionStatus: PetStatus?
    private var dragRow: Int?
    private var dragStart: NSPoint?
    private var windowStart: NSPoint?
    private var didDrag = false
    private var trackingArea: NSTrackingArea?
    var taskLabel = "" { didSet { needsDisplay = true } }
    var onQuickPhrase: (() -> Void)?
    var onMoved: (() -> Void)?

    init(atlas: CGImage) {
        super.init(frame: NSRect(x: 0, y: 0, width: 250, height: 310))
        wantsLayer = true
        loadAtlas(atlas)
        timer = Timer.scheduledTimer(withTimeInterval: 0.13, repeats: true) { [weak self] _ in
            guard let self else { return }
            let row = self.dragRow ?? self.interactionStatus?.row ?? self.status.row
            guard row < self.frames.count, !self.frames[row].isEmpty else { return }
            self.frameIndex = (self.frameIndex + 1) % self.frames[row].count
            self.needsDisplay = true
        }
    }

    func loadAtlas(_ atlas: CGImage) {
        var nextFrames: [[CGImage]] = []
        for row in 0..<9 {
            nextFrames.append((0..<Self.frameCounts[row]).compactMap { column in
                atlas.cropping(to: CGRect(x: column * 192, y: row * 208, width: 192, height: 208))
            })
        }
        frames = nextFrames
        frameIndex = 0
        needsDisplay = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let next = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(next)
        trackingArea = next
    }

    func setStatus(_ next: PetStatus) {
        guard next != status else { return }
        status = next
        frameIndex = 0
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let graphics = NSGraphicsContext.current else { return }
        graphics.cgContext.clear(bounds)
        graphics.imageInterpolation = .none
        let topInset: CGFloat = 2
        let margin = max(2, bounds.width * 0.04)
        let availableWidth = max(1, bounds.width - margin * 2)
        let availableHeight = max(1, bounds.height - topInset - margin)
        let spriteWidth = min(availableWidth, availableHeight * 192 / 208)
        let spriteHeight = spriteWidth * 208 / 192
        let spriteRect = CGRect(x: (bounds.width - spriteWidth) / 2, y: topInset + (availableHeight - spriteHeight) / 2, width: spriteWidth, height: spriteHeight)
        let row = dragRow ?? interactionStatus?.row ?? status.row
        guard row < frames.count, !frames[row].isEmpty else { return }
        let index = frameIndex % frames[row].count
        NSImage(cgImage: frames[row][index], size: NSSize(width: 192, height: 208)).draw(in: spriteRect)

    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            dragStart = nil
            windowStart = nil
            didDrag = false
            focusHarnessWebUI()
            return
        }
        dragStart = NSEvent.mouseLocation
        windowStart = window?.frame.origin
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart, let windowStart, let window else { return }
        let point = NSEvent.mouseLocation
        let deltaX = point.x - dragStart.x
        let deltaY = point.y - dragStart.y
        if !didDrag, hypot(deltaX, deltaY) < 3 { return }
        if !didDrag {
            didDrag = true
            interactionTimer?.invalidate()
            interactionStatus = nil
        }
        window.setFrameOrigin(NSPoint(x: windowStart.x + deltaX, y: windowStart.y + deltaY))
        dragRow = deltaX >= 0 ? 1 : 2
        onMoved?()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if didDrag {
            UserDefaults.standard.set(window?.frame.origin.x, forKey: "petX")
            UserDefaults.standard.set(window?.frame.origin.y, forKey: "petY")
        } else if event.clickCount == 1 {
            playRandomInteraction()
            onQuickPhrase?()
        }
        dragStart = nil
        windowStart = nil
        dragRow = nil
        didDrag = false
        needsDisplay = true
    }

    override func mouseEntered(with event: NSEvent) {
        guard dragStart == nil else { return }
        playInteraction(.waving, duration: 1.1)
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(withTitle: PetLanguage.text("挥手", "Wave"), action: #selector(wave), keyEquivalent: "")
        menu.addItem(withTitle: PetLanguage.text("隐藏", "Hide"), action: #selector(hidePet), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: PetLanguage.text("退出桌宠", "Quit DeskPet"), action: #selector(quit), keyEquivalent: "")
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    private func playInteraction(_ next: PetStatus, duration: TimeInterval = 1.35) {
        interactionTimer?.invalidate()
        interactionStatus = next
        frameIndex = 0
        needsDisplay = true
        interactionTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.interactionStatus = nil
            self?.frameIndex = 0
            self?.needsDisplay = true
        }
    }

    private func playRandomInteraction() {
        let actions: [PetStatus] = [.waving, .jumping, .failed, .waiting, .running, .review]
        if let next = actions.randomElement() { playInteraction(next) }
    }

    @objc private func wave() { playInteraction(.waving) }
    @objc private func hidePet() { window?.orderOut(nil) }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
}

final class PetMessageView: NSView {
    var text = "" { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let background = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 14, yRadius: 14)
        NSColor.black.withAlphaComponent(0.82).setFill()
        background.fill()
        NSColor.white.withAlphaComponent(0.16).setStroke()
        background.lineWidth = 1
        background.stroke()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph,
        ]
        (text as NSString).draw(in: bounds.insetBy(dx: 13, dy: 12), withAttributes: attributes)
    }
}

final class PetMessagePanel {
    private let panel: NSPanel
    private let messageView: PetMessageView
    private var taskText: String?
    private var quickTimer: Timer?
    private var petVisible = true

    init() {
        let size = NSSize(width: 280, height: 58)
        messageView = PetMessageView(frame: NSRect(origin: .zero, size: size))
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.contentView = messageView
    }

    func setPetVisible(_ visible: Bool, above petPanel: NSPanel) {
        petVisible = visible
        if visible { restoreTask(above: petPanel) } else { panel.orderOut(nil) }
    }

    func setTask(_ text: String?, above petPanel: NSPanel) {
        let normalized = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        taskText = (normalized?.isEmpty == false) ? normalized : nil
        guard quickTimer == nil else { return }
        restoreTask(above: petPanel)
    }

    func showQuickPhrase(_ text: String, above petPanel: NSPanel) {
        quickTimer?.invalidate()
        messageView.text = text
        reposition(above: petPanel)
        if petVisible { panel.orderFrontRegardless() }
        quickTimer = Timer.scheduledTimer(withTimeInterval: 4.5, repeats: false) { [weak self, weak petPanel] _ in
            guard let self, let petPanel else { return }
            self.quickTimer = nil
            self.restoreTask(above: petPanel)
        }
    }

    func reposition(above petPanel: NSPanel) {
        let visible = petPanel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let size = panel.frame.size
        let centeredX = petPanel.frame.midX - size.width / 2
        let x = min(max(centeredX, visible.minX + 8), visible.maxX - size.width - 8)
        let aboveY = petPanel.frame.maxY + 8
        let y = aboveY + size.height <= visible.maxY - 8 ? aboveY : petPanel.frame.minY - size.height - 8
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func restoreTask(above petPanel: NSPanel) {
        guard petVisible, let taskText else {
            panel.orderOut(nil)
            return
        }
        messageView.text = PetLanguage.text("正在进行：\(taskText)", "In progress: \(taskText)")
        reposition(above: petPanel)
        panel.orderFrontRegardless()
    }

    func languageDidChange(above petPanel: NSPanel) {
        guard quickTimer == nil else { return }
        restoreTask(above: petPanel)
    }

    var snapshot: [String: Any] {
        ["visible": panel.isVisible, "task": taskText ?? "", "text": messageView.text]
    }
}

final class CompletionNoticeView: NSView {
    var onClick: (() -> Void)?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let background = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 13, yRadius: 13)
        NSColor.black.withAlphaComponent(0.84).setFill()
        background.fill()
        NSColor.white.withAlphaComponent(0.16).setStroke()
        background.lineWidth = 1
        background.stroke()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph,
        ]
        (PetLanguage.text("✓ 任务已完成 · 点击返回 DeepSeek", "✓ Task complete · Click to return to DeepSeek") as NSString).draw(
            in: NSRect(x: 12, y: 14, width: bounds.width - 24, height: 18),
            withAttributes: attributes
        )
    }

    override func mouseDown(with event: NSEvent) { onClick?() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

final class CompletionNotice {
    private let panel: NSPanel
    private let noticeView: CompletionNoticeView
    private var dismissTimer: Timer?

    init() {
        let size = NSSize(width: 260, height: 46)
        let view = CompletionNoticeView(frame: NSRect(origin: .zero, size: size))
        noticeView = view
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.contentView = view
        view.onClick = { [weak self] in
            focusHarnessWebUI()
            self?.hide()
        }
    }

    func show(below petPanel: NSPanel) {
        let visible = petPanel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let size = panel.frame.size
        let centeredX = petPanel.frame.midX - size.width / 2
        let x = min(max(centeredX, visible.minX + 8), visible.maxX - size.width - 8)
        let requestedY = petPanel.frame.minY - size.height - 8
        let y = requestedY >= visible.minY + 8 ? requestedY : petPanel.frame.maxY + 8
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.orderFrontRegardless()
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in self?.hide() }
    }

    func hide() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        panel.orderOut(nil)
    }

    func languageDidChange() {
        noticeView.needsDisplay = true
    }
}

enum PetLibraryError: LocalizedError {
    case invalidIdentifier, invalidManifest, invalidSpritesheet, downloadFailed

    var errorDescription: String? {
        switch self {
        case .invalidIdentifier: return PetLanguage.text("无效的宠物标识", "Invalid pet identifier")
        case .invalidManifest: return PetLanguage.text("宠物清单无效", "Invalid pet manifest")
        case .invalidSpritesheet: return PetLanguage.text("宠物动画图集无效", "Invalid pet spritesheet")
        case .downloadFailed: return PetLanguage.text("宠物下载失败", "Pet download failed")
        }
    }
}

final class PetLibrary {
    static let builtInID = "bongocat--ayangweb"
    static let legacyBuiltInID = "anya--chenxin-dlut"
    private let root: URL
    private let builtInAtlasURL: URL
    private let fileManager = FileManager.default
    private let petdexCacheLock = NSLock()
    private var petdexEntriesCache: (loadedAt: Date, entries: [[String: Any]])?
    private let remoteCatalogCacheLock = NSLock()
    private var remoteCatalogCaches: [String: (loadedAt: Date, entries: [[String: Any]])] = [:]

    init(builtInAtlasURL: URL) {
        self.builtInAtlasURL = builtInAtlasURL
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        root = support.appendingPathComponent("DeepSS Pet/pets", isDirectory: true)
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        seedBundledPets()
    }

    private func seedBundledPets() {
        guard let bundledRoot = Bundle.main.resourceURL?.appendingPathComponent("BundledPets", isDirectory: true),
              let directories = try? fileManager.contentsOfDirectory(at: bundledRoot, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return }
        for sourceDirectory in directories {
            let id = sourceDirectory.lastPathComponent
            guard valid(id) else { continue }
            let destination = root.appendingPathComponent(id, isDirectory: true)
            guard !fileManager.fileExists(atPath: destination.path) else { continue }
            try? fileManager.copyItem(at: sourceDirectory, to: destination)
        }
    }

    private func valid(_ id: String) -> Bool {
        !id.isEmpty && id.range(of: "^[a-z0-9][a-z0-9-]{0,120}$", options: .regularExpression) != nil
    }

    private func downloadWithRetry(_ url: URL, maxBytes: Int, attempts: Int = 3) throws -> Data {
        for attempt in 0..<attempts {
            if let data = try? Data(contentsOf: url), !data.isEmpty, data.count <= maxBytes { return data }
            if attempt + 1 < attempts { Thread.sleep(forTimeInterval: 0.25 * Double(attempt + 1)) }
        }
        throw PetLibraryError.downloadFailed
    }

    private func manifestURL(for id: String) -> URL { root.appendingPathComponent(id, isDirectory: true).appendingPathComponent("pet.json") }
    private func atlasURL(for id: String) -> URL { root.appendingPathComponent(id, isDirectory: true).appendingPathComponent("spritesheet.webp") }

    func atlas(for id: String) -> CGImage? {
        let installed = atlasURL(for: id)
        let url = fileManager.fileExists(atPath: installed.path) ? installed : (id == Self.builtInID ? builtInAtlasURL : installed)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width == 1536, [1872, 2288].contains(image.height) else { return nil }
        return image
    }

    func pets(selectedID: String) -> [[String: Any]] {
        var result: [[String: Any]] = []
        let directories = (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        for directory in directories.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let id = directory.lastPathComponent
            guard valid(id),
                  let data = try? Data(contentsOf: manifestURL(for: id)),
                  let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  atlas(for: id) != nil else { continue }
            var pet: [String: Any] = [
                "id": id,
                "displayName": manifest["displayName"] as? String ?? id,
                "description": manifest["description"] as? String ?? "",
                "spriteVersionNumber": manifest["spriteVersionNumber"] as? Int ?? 1,
                "selected": id == selectedID,
                "builtIn": false,
            ]
            for key in ["source", "sourcePetID", "previewURL", "ownerHandle"] {
                if let value = manifest[key] as? String { pet[key] = value }
            }
            result.append(pet)
        }
        if !result.contains(where: { ($0["id"] as? String) == Self.builtInID }) {
            result.insert([
                "id": Self.builtInID,
                "displayName": "BongoCat",
                "description": "会敲键盘、拍桌面并陪伴 DeepSeek 工作的白色 BongoCat",
                "spriteVersionNumber": 2,
                "selected": selectedID == Self.builtInID,
                "builtIn": true,
                "source": "bongocat",
                "sourcePetID": "ayangweb/bongocat",
                "previewURL": "https://raw.githubusercontent.com/ayangweb/bongocat/main/src-tauri/assets/models/standard/resources/cover.png",
            ], at: 0)
        }
        return result
    }

    private func save(manifest originalManifest: [String: Any], atlasData: Data, localID: String) throws -> [String: Any] {
        guard valid(localID), atlasData.count < 20_000_000,
              let source = CGImageSourceCreateWithData(atlasData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width == 1536, [1872, 2288].contains(image.height) else { throw PetLibraryError.invalidSpritesheet }

        var manifest = originalManifest
        manifest["id"] = localID
        manifest["spritesheetPath"] = "spritesheet.webp"
        manifest["spriteVersionNumber"] = image.height == 2288 ? 2 : 1
        let normalized = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        guard normalized.count < 128_000 else { throw PetLibraryError.invalidManifest }
        let directory = root.appendingPathComponent(localID, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try atlasData.write(to: atlasURL(for: localID), options: .atomic)
        try normalized.write(to: manifestURL(for: localID), options: .atomic)
        return manifest
    }

    private func installAwesome(slug: String) throws -> (String, [String: Any]) {
        guard valid(slug) else { throw PetLibraryError.invalidIdentifier }
        let base = "https://raw.githubusercontent.com/legeling/awesome-codex-pet/main/pets/\(slug)"
        guard let manifestRemote = URL(string: "\(base)/pet.json"),
              let atlasRemote = URL(string: "\(base)/spritesheet.webp"),
              let manifestData = try? Data(contentsOf: manifestRemote),
              let atlasData = try? Data(contentsOf: atlasRemote),
              manifestData.count < 128_000 else { throw PetLibraryError.downloadFailed }
        guard var manifest = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
              (manifest["id"] as? String) == slug else { throw PetLibraryError.invalidManifest }
        manifest["source"] = "awesome-codex-pet"
        manifest["sourcePetID"] = slug
        manifest["previewURL"] = "https://codexpet.top/assets/previews/\(slug)/thumbnail.webp"
        return (slug, try save(manifest: manifest, atlasData: atlasData, localID: slug))
    }

    private func installCodexPets(id remoteID: String) throws -> (String, [String: Any]) {
        guard valid(remoteID), let detailURL = URL(string: "https://codex-pets.net/api/pets/\(remoteID)"),
              let detailData = try? Data(contentsOf: detailURL), detailData.count < 256_000,
              let response = try? JSONSerialization.jsonObject(with: detailData) as? [String: Any],
              let pet = response["pet"] as? [String: Any], (pet["id"] as? String) == remoteID,
              let spritesheetString = pet["spritesheetUrl"] as? String,
              let spritesheetURL = URL(string: spritesheetString),
              spritesheetURL.scheme == "https", spritesheetURL.host == "codex-pets.net",
              spritesheetURL.path.hasPrefix("/assets/pets/"),
              let atlasData = try? Data(contentsOf: spritesheetURL) else { throw PetLibraryError.downloadFailed }

        let localID = "codex-pets--\(remoteID)"
        var manifest: [String: Any] = [
            "id": localID,
            "displayName": pet["displayName"] as? String ?? remoteID,
            "description": pet["description"] as? String ?? "",
            "source": "codex-pets",
            "sourcePetID": remoteID,
        ]
        if let preview = (pet["posterUrl"] as? String) ?? (pet["previewUrl"] as? String) { manifest["previewURL"] = preview }
        if let owner = pet["ownerHandle"] as? String { manifest["ownerHandle"] = owner }
        return (localID, try save(manifest: manifest, atlasData: atlasData, localID: localID))
    }

    private func petdexEntries() throws -> [[String: Any]] {
        petdexCacheLock.lock()
        if let cached = petdexEntriesCache, Date().timeIntervalSince(cached.loadedAt) < 600 {
            petdexCacheLock.unlock()
            return cached.entries
        }
        petdexCacheLock.unlock()
        guard let url = URL(string: "https://assets.petdex.dev/manifests/petdex-v2.json") else { throw PetLibraryError.downloadFailed }
        let data = try downloadWithRetry(url, maxBytes: 2_000_000)
        guard
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (manifest["assetBase"] as? String) == "https://assets.petdex.dev",
              let fields = manifest["fields"] as? [String],
              let rows = manifest["pets"] as? [[Any]] else { throw PetLibraryError.downloadFailed }
        let indexes = Dictionary(uniqueKeysWithValues: fields.enumerated().map { ($0.element, $0.offset) })
        func value(_ row: [Any], _ key: String) -> Any? {
            guard let index = indexes[key], index < row.count else { return nil }
            return row[index]
        }
        let entries: [[String: Any]] = rows.compactMap { row -> [String: Any]? in
            guard let slug = value(row, "slug") as? String, valid(slug),
                  let displayName = value(row, "displayName") as? String,
                  let spritesheet = value(row, "spritesheet") as? String,
                  let petJson = value(row, "petJson") as? String else { return nil }
            return [
                "id": slug,
                "displayName": displayName,
                "kind": value(row, "kind") as? String ?? "",
                "spritesheetPath": spritesheet,
                "petJsonPath": petJson,
                "spriteVersionNumber": value(row, "spriteVersionNumber") as? Int ?? 1,
                "previewURL": "https://assets.petdex.dev/pets/\(slug)/preview.webp",
            ]
        }
        petdexCacheLock.lock()
        petdexEntriesCache = (Date(), entries)
        petdexCacheLock.unlock()
        return entries
    }

    private func petdexAssetURL(path: String) -> URL? {
        guard !path.contains(".."), let url = URL(string: "https://assets.petdex.dev/\(path)"),
              url.scheme == "https", url.host == "assets.petdex.dev",
              url.path.hasPrefix("/pets/") || url.path.hasPrefix("/curated/") || url.path.hasPrefix("/community/") else { return nil }
        return url
    }

    private func installPetdex(id remoteID: String) throws -> (String, [String: Any]) {
        guard valid(remoteID), let entry = try petdexEntries().first(where: { ($0["id"] as? String) == remoteID }),
              let manifestPath = entry["petJsonPath"] as? String,
              let spritesheetPath = entry["spritesheetPath"] as? String,
              let manifestURL = petdexAssetURL(path: manifestPath),
              let spritesheetURL = petdexAssetURL(path: spritesheetPath) else { throw PetLibraryError.downloadFailed }
        let atlasData = try downloadWithRetry(spritesheetURL, maxBytes: 20_000_000)
        var manifest: [String: Any] = [
            "displayName": entry["displayName"] as? String ?? remoteID,
            "description": "来自 PetDex 的桌面宠物",
        ]
        if let manifestData = try? downloadWithRetry(manifestURL, maxBytes: 128_000),
           let remoteManifest = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any] {
            manifest = remoteManifest
        }
        let localID = "petdex--\(remoteID)"
        manifest["displayName"] = manifest["displayName"] as? String ?? entry["displayName"] as? String ?? remoteID
        manifest["description"] = manifest["description"] as? String ?? "来自 PetDex 的桌面宠物"
        manifest["source"] = "petdex"
        manifest["sourcePetID"] = remoteID
        manifest["previewURL"] = entry["previewURL"]
        return (localID, try save(manifest: manifest, atlasData: atlasData, localID: localID))
    }

    private func cachedEntries(key: String, maxAge: TimeInterval = 600, loader: () throws -> [[String: Any]]) throws -> [[String: Any]] {
        remoteCatalogCacheLock.lock()
        if let cached = remoteCatalogCaches[key], Date().timeIntervalSince(cached.loadedAt) < maxAge {
            remoteCatalogCacheLock.unlock()
            return cached.entries
        }
        remoteCatalogCacheLock.unlock()
        let entries = try loader()
        remoteCatalogCacheLock.lock()
        remoteCatalogCaches[key] = (Date(), entries)
        remoteCatalogCacheLock.unlock()
        return entries
    }

    private func pagedCatalog(entries: [[String: Any]], page requestedPage: Int, pageSize requestedPageSize: Int, query: String) -> [String: Any] {
        let page = min(10_000, max(1, requestedPage))
        let pageSize = min(48, max(1, requestedPageSize))
        let normalized = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)).lowercased()
        let filtered = normalized.isEmpty ? entries : entries.filter { entry in
            [entry["id"], entry["displayName"], entry["description"], entry["kind"]].contains { value in
                String(describing: value ?? "").lowercased().contains(normalized)
            }
        }
        let start = min(filtered.count, (page - 1) * pageSize)
        let end = min(filtered.count, start + pageSize)
        return ["pets": Array(filtered[start..<end]), "page": page, "pageSize": pageSize, "total": filtered.count]
    }

    private func agentBroEntries() throws -> [[String: Any]] {
        try cachedEntries(key: "agentbro") {
            guard let url = URL(string: "https://api.agentbro.net/api/manifest") else { throw PetLibraryError.downloadFailed }
            let data = try downloadWithRetry(url, maxBytes: 4_000_000)
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let pets = object["pets"] as? [[String: Any]] else { throw PetLibraryError.downloadFailed }
            return pets.compactMap { pet in
                guard let slug = pet["slug"] as? String, self.valid(slug),
                      (pet["status"] as? String ?? "approved") == "approved",
                      let spritesheetURL = pet["spritesheetUrl"] as? String else { return nil }
                return [
                    "id": slug,
                    "displayName": pet["displayName"] as? String ?? slug,
                    "description": pet["description"] as? String ?? "",
                    "kind": pet["kind"] as? String ?? "",
                    "previewURL": spritesheetURL,
                    "spritesheetURL": spritesheetURL,
                    "manifestURL": pet["petJsonUrl"] as? String ?? "",
                ]
            }
        }
    }

    private func spriteYardEntries() throws -> [[String: Any]] {
        try cachedEntries(key: "spriteyard") {
            guard let url = URL(string: "https://www.spriteyard.com/") else { throw PetLibraryError.downloadFailed }
            let data = try downloadWithRetry(url, maxBytes: 4_000_000)
            guard let html = String(data: data, encoding: .utf8) else { throw PetLibraryError.downloadFailed }
            let pattern = #"\\\"creator\\\":\\\".*?\\\",\\\"description\\\":\\\"(.*?)\\\".*?\\\"galleryPreviewUrl\\\":\\\"(.*?)\\\",\\\"name\\\":\\\"(.*?)\\\".*?\\\"previewUrl\\\":\\\"(.*?)\\\".*?\\\"slug\\\":\\\"([a-z0-9-]+)\\\""#
            guard let expression = try? NSRegularExpression(pattern: pattern) else { throw PetLibraryError.downloadFailed }
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            return expression.matches(in: html, range: range).compactMap { match in
                func value(_ index: Int) -> String? {
                    guard let range = Range(match.range(at: index), in: html) else { return nil }
                    return String(html[range]).replacingOccurrences(of: #"\\n"#, with: " ").replacingOccurrences(of: #"\\\""#, with: "\"")
                }
                guard let slug = value(5), self.valid(slug) else { return nil }
                return [
                    "id": slug,
                    "displayName": value(3) ?? slug,
                    "description": value(1) ?? "",
                    "previewURL": value(2) ?? "https://assets.spriteyard.com/pets/\(slug)/preview.png",
                    "spritesheetURL": value(4) ?? "https://assets.spriteyard.com/pets/\(slug)/spritesheet.webp",
                ]
            }
        }
    }

    private func animePetEntries() throws -> [[String: Any]] {
        try cachedEntries(key: "codex-anime-pets", maxAge: 1800) {
            guard let url = URL(string: "https://api.github.com/repos/chenxin-dlut/codex-anime-pets/contents/pets?ref=main") else { throw PetLibraryError.downloadFailed }
            let data = try downloadWithRetry(url, maxBytes: 1_000_000)
            guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw PetLibraryError.downloadFailed }
            return rows.compactMap { row in
                guard row["type"] as? String == "dir", let slug = row["name"] as? String, self.valid(slug) else { return nil }
                return [
                    "id": slug,
                    "displayName": slug.split(separator: "-").map { $0.capitalized }.joined(separator: " "),
                    "description": PetLanguage.text("来自 Codex Anime Pets 的动漫桌宠（仅限个人非商业使用）", "Anime pet from Codex Anime Pets (personal, non-commercial use only)"),
                    "previewURL": "https://raw.githubusercontent.com/chenxin-dlut/codex-anime-pets/main/assets/previews/\(slug).png",
                    "spritesheetURL": "https://raw.githubusercontent.com/chenxin-dlut/codex-anime-pets/main/pets/\(slug)/spritesheet.webp",
                    "manifestURL": "https://raw.githubusercontent.com/chenxin-dlut/codex-anime-pets/main/pets/\(slug)/pet.json",
                ]
            }
        }
    }

    private func openPetsEntries() throws -> [[String: Any]] {
        try cachedEntries(key: "openpets", maxAge: 900) {
            var entries: [[String: Any]] = []
            for page in 0..<13 {
                guard let url = URL(string: String(format: "https://openpets.dev/pets/catalog.v3/page-%03d.json", page)) else { continue }
                let data = try self.downloadWithRetry(url, maxBytes: 4_000_000)
                guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let pets = object["pets"] as? [[String: Any]] else { continue }
                entries.append(contentsOf: pets.compactMap { pet in
                    guard let id = pet["id"] as? String, self.valid(id), let sheet = pet["spritesheet"] as? String else { return nil }
                    return [
                        "id": id,
                        "displayName": pet["displayName"] as? String ?? id,
                        "description": pet["description"] as? String ?? "",
                        "kind": pet["subcategory"] as? String ?? pet["category"] as? String ?? "",
                        "previewURL": pet["thumbnail"] as? String ?? sheet,
                        "spritesheetURL": sheet,
                    ]
                })
            }
            guard !entries.isEmpty else { throw PetLibraryError.downloadFailed }
            return entries
        }
    }

    private func installDirectCatalog(source: String, remoteID: String, entries: [[String: Any]]) throws -> (String, [String: Any]) {
        guard valid(remoteID), let entry = entries.first(where: { ($0["id"] as? String) == remoteID }),
              let sheetString = entry["spritesheetURL"] as? String,
              let sheetURL = URL(string: sheetString), sheetURL.scheme == "https" else { throw PetLibraryError.downloadFailed }
        let atlasData = try downloadWithRetry(sheetURL, maxBytes: 20_000_000)
        var manifest: [String: Any] = [
            "displayName": entry["displayName"] as? String ?? remoteID,
            "description": entry["description"] as? String ?? "",
        ]
        if let manifestString = entry["manifestURL"] as? String, let manifestURL = URL(string: manifestString), manifestURL.scheme == "https",
           let manifestData = try? downloadWithRetry(manifestURL, maxBytes: 128_000),
           let remoteManifest = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any] {
            manifest.merge(remoteManifest) { _, remote in remote }
        }
        let localID = "\(source)--\(remoteID)"
        manifest["source"] = source
        manifest["sourcePetID"] = remoteID
        manifest["previewURL"] = entry["previewURL"] as? String ?? sheetString
        return (localID, try save(manifest: manifest, atlasData: atlasData, localID: localID))
    }

    func install(source: String, id: String) throws -> (String, [String: Any]) {
        switch source {
        case "codex-pets": return try installCodexPets(id: id)
        case "petdex": return try installPetdex(id: id)
        case "awesome-codex-pet", "awesome": return try installAwesome(slug: id)
        case "agentbro": return try installDirectCatalog(source: source, remoteID: id, entries: agentBroEntries())
        case "spriteyard": return try installDirectCatalog(source: source, remoteID: id, entries: spriteYardEntries())
        case "openpets": return try installDirectCatalog(source: source, remoteID: id, entries: openPetsEntries())
        case "codex-anime-pets": return try installDirectCatalog(source: source, remoteID: id, entries: animePetEntries())
        default: throw PetLibraryError.invalidIdentifier
        }
    }

    func codexPetsCatalog(page requestedPage: Int, pageSize requestedPageSize: Int, query: String) throws -> [String: Any] {
        var components = URLComponents(string: "https://codex-pets.net/api/pets")!
        let page = min(10_000, max(1, requestedPage))
        let pageSize = min(48, max(1, requestedPageSize))
        var items = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "pageSize", value: String(pageSize)),
            URLQueryItem(name: "sort", value: "popular"),
        ]
        let trimmed = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        if !trimmed.isEmpty { items.append(URLQueryItem(name: "q", value: trimmed)) }
        components.queryItems = items
        guard let url = components.url, let data = try? Data(contentsOf: url), data.count < 2_000_000,
              let catalog = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              catalog["pets"] is [[String: Any]] else { throw PetLibraryError.downloadFailed }
        return catalog
    }

    func petdexCatalog(page requestedPage: Int, pageSize requestedPageSize: Int, query: String) throws -> [String: Any] {
        let page = min(10_000, max(1, requestedPage))
        let pageSize = min(48, max(1, requestedPageSize))
        let trimmed = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        var components = URLComponents(string: "https://petdex.dev/api/pets/search")!
        var items = [
            URLQueryItem(name: "sort", value: "popular"),
            URLQueryItem(name: "cursor", value: String((page - 1) * pageSize)),
            URLQueryItem(name: "limit", value: String(pageSize)),
            URLQueryItem(name: "includeMeta", value: "1"),
        ]
        if !trimmed.isEmpty { items.append(URLQueryItem(name: "q", value: trimmed)) }
        components.queryItems = items
        if let url = components.url,
           let data = try? downloadWithRetry(url, maxBytes: 2_000_000),
           let catalog = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let remotePets = catalog["pets"] as? [[String: Any]] {
            let pets: [[String: Any]] = remotePets.compactMap { pet in
                guard let slug = pet["slug"] as? String, valid(slug) else { return nil }
                return [
                    "id": slug,
                    "displayName": pet["displayName"] as? String ?? slug,
                    "description": pet["description"] as? String ?? "来自 PetDex 的桌面宠物",
                    "kind": pet["kind"] as? String ?? "",
                    "spriteVersionNumber": pet["spriteVersionNumber"] as? Int ?? 1,
                    "previewURL": "https://assets.petdex.dev/pets/\(slug)/preview.webp",
                ]
            }
            return ["pets": pets, "page": page, "pageSize": pageSize, "total": catalog["total"] as? Int ?? pets.count]
        }

        let normalized = trimmed.lowercased()
        let entries = try petdexEntries()
        let filtered = normalized.isEmpty ? entries : entries.filter { entry in
            [entry["id"], entry["displayName"], entry["kind"]].contains { value in String(describing: value ?? "").lowercased().contains(normalized) }
        }
        let start = min(filtered.count, (page - 1) * pageSize)
        let end = min(filtered.count, start + pageSize)
        let fallback = Array(filtered[start..<end]).map { entry -> [String: Any] in
            var pet = entry
            pet["description"] = "来自 PetDex 的桌面宠物"
            return pet
        }
        return ["pets": fallback, "page": page, "pageSize": pageSize, "total": filtered.count]
    }

    func catalog(source: String, page: Int, pageSize: Int, query: String) throws -> [String: Any] {
        switch source {
        case "codex-pets": return try codexPetsCatalog(page: page, pageSize: pageSize, query: query)
        case "petdex": return try petdexCatalog(page: page, pageSize: pageSize, query: query)
        case "agentbro": return pagedCatalog(entries: try agentBroEntries(), page: page, pageSize: pageSize, query: query)
        case "spriteyard": return pagedCatalog(entries: try spriteYardEntries(), page: page, pageSize: pageSize, query: query)
        case "openpets": return pagedCatalog(entries: try openPetsEntries(), page: page, pageSize: pageSize, query: query)
        case "codex-anime-pets": return pagedCatalog(entries: try animePetEntries(), page: page, pageSize: pageSize, query: query)
        default: throw PetLibraryError.invalidIdentifier
        }
    }

    func preview(source: String, id: String) throws -> (data: Data, contentType: String) {
        guard valid(id) else { throw PetLibraryError.invalidIdentifier }
        let url: URL?
        switch source {
        case "petdex":
            url = URL(string: "https://assets.petdex.dev/pets/\(id)/preview.webp")
        case "awesome-codex-pet", "awesome":
            url = URL(string: "https://codexpet.top/assets/previews/\(id)/thumbnail.webp")
        default:
            throw PetLibraryError.invalidIdentifier
        }
        guard let url else { throw PetLibraryError.downloadFailed }
        let data = try downloadWithRetry(url, maxBytes: 2_000_000)
        guard
              let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else { throw PetLibraryError.downloadFailed }
        if source == "petdex", image.width >= 384, image.height >= 208,
           let firstFrame = image.cropping(to: CGRect(x: 0, y: 0, width: 192, height: 208)) {
            let output = NSMutableData()
            if let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) {
                CGImageDestinationAddImage(destination, firstFrame, nil)
                if CGImageDestinationFinalize(destination) { return (output as Data, "image/png") }
            }
        }
        return (data, "image/webp")
    }

    @discardableResult
    func remove(id: String) throws -> Bool {
        guard valid(id) else { throw PetLibraryError.invalidIdentifier }
        let directory = root.appendingPathComponent(id, isDirectory: true)
        guard fileManager.fileExists(atPath: directory.path) else { return false }
        try fileManager.removeItem(at: directory)
        return true
    }
}

final class PetController {
    private static let baseSize = NSSize(width: 250, height: 310)
    private static let chineseQuickPhrases = [
        "主人～坐久了，站起来休息休息吧",
        "主人～喝口水，我们再继续",
        "今天也要记得照顾好自己哦",
        "我在这里陪你一起完成任务",
    ]
    private static let englishQuickPhrases = [
        "You've been sitting for a while—time to stand up and stretch!",
        "Take a sip of water, then let's keep going.",
        "Remember to take good care of yourself today.",
        "I'm right here, working through this task with you.",
    ]
    private static var defaultQuickPhrases: [String] {
        PetLanguage.isEnglish ? englishQuickPhrases : chineseQuickPhrases
    }
    let panel: NSPanel
    let view: PetView
    let library: PetLibrary
    private let completionNotice = CompletionNotice()
    private let petMessage = PetMessagePanel()
    private(set) var status: PetStatus = .idle
    private(set) var scale: CGFloat
    private(set) var selectedPetID: String
    private(set) var quickPhrases: [String]

    init(library: PetLibrary) {
        self.library = library
        let savedScale = UserDefaults.standard.double(forKey: "petScale")
        scale = savedScale >= 0.2 && savedScale <= 1.5 ? savedScale : 0.5
        let savedPetID = UserDefaults.standard.string(forKey: "selectedPetID")
        selectedPetID = savedPetID == PetLibrary.legacyBuiltInID ? PetLibrary.builtInID : (savedPetID ?? PetLibrary.builtInID)
        let savedPhrases = UserDefaults.standard.stringArray(forKey: "quickPhrases") ?? []
        quickPhrases = savedPhrases.isEmpty ? Self.defaultQuickPhrases : savedPhrases
        if savedPetID == PetLibrary.legacyBuiltInID {
            UserDefaults.standard.set(PetLibrary.builtInID, forKey: "selectedPetID")
        }
        guard let atlas = library.atlas(for: selectedPetID) ?? library.atlas(for: PetLibrary.builtInID) else {
            fatalError("Missing built-in spritesheet")
        }
        if library.atlas(for: selectedPetID) == nil { selectedPetID = PetLibrary.builtInID }
        view = PetView(atlas: atlas)
        let savedX = UserDefaults.standard.object(forKey: "petX") as? CGFloat
        let savedY = UserDefaults.standard.object(forKey: "petY") as? CGFloat
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let size = NSSize(width: Self.baseSize.width * scale, height: Self.baseSize.height * scale)
        let origin = NSPoint(x: savedX ?? screen.maxX - size.width - 20, y: savedY ?? screen.minY + 20)
        panel = NSPanel(contentRect: NSRect(origin: origin, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.acceptsMouseMovedEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false
        panel.contentView = view
        view.frame = NSRect(origin: .zero, size: size)
        view.onQuickPhrase = { [weak self] in self?.speakRandomPhrase() }
        view.onMoved = { [weak self] in
            guard let self else { return }
            self.petMessage.reposition(above: self.panel)
        }
        panel.orderFrontRegardless()
    }

    func setScale(_ requested: Double) {
        let value = CGFloat(min(1.5, max(0.2, requested)))
        guard abs(value - scale) > 0.0001 else { return }
        let oldFrame = panel.frame
        scale = value
        let size = NSSize(width: Self.baseSize.width * value, height: Self.baseSize.height * value)
        let origin = NSPoint(x: oldFrame.midX - size.width / 2, y: oldFrame.minY)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        view.frame = NSRect(origin: .zero, size: size)
        petMessage.reposition(above: panel)
        UserDefaults.standard.set(Double(value), forKey: "petScale")
    }

    @discardableResult
    func selectPet(_ id: String) -> Bool {
        guard let atlas = library.atlas(for: id) else { return false }
        selectedPetID = id
        UserDefaults.standard.set(id, forKey: "selectedPetID")
        view.loadAtlas(atlas)
        return true
    }

    @discardableResult
    func removePet(_ id: String) throws -> Bool {
        let removed = try library.remove(id: id)
        if removed, selectedPetID == id {
            _ = selectPet(PetLibrary.builtInID)
        }
        return removed
    }

    func apply(_ body: [String: Any]) {
        if let locale = body["locale"] as? String { setLanguage(locale) }
        if let visible = body["visible"] as? Bool {
            visible ? panel.orderFrontRegardless() : panel.orderOut(nil)
            petMessage.setPetVisible(visible, above: panel)
        }
        if let raw = body["status"] as? String, let next = PetStatus(rawValue: raw) {
            let previous = status
            status = next
            view.setStatus(next)
            if next == .review && (previous == .running || previous == .waiting) {
                completionNotice.show(below: panel)
            }
        }
        if let label = body["label"] as? String { view.taskLabel = String(label.prefix(60)) }
        if let requestedScale = body["scale"] as? Double { setScale(requestedScale) }
        let currentTask = (status == .running || status == .waiting) ? view.taskLabel : nil
        petMessage.setTask(currentTask, above: panel)
    }

    func setQuickPhrases(_ values: [String]) {
        let normalized = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(30)
            .map { String($0.prefix(100)) }
        quickPhrases = normalized.isEmpty ? Self.defaultQuickPhrases : normalized
        UserDefaults.standard.set(quickPhrases, forKey: "quickPhrases")
    }

    private func setLanguage(_ locale: String) {
        let shouldUseEnglish = locale.lowercased().hasPrefix("en")
        guard shouldUseEnglish != PetLanguage.isEnglish else { return }
        let previousDefaults = Self.defaultQuickPhrases
        PetLanguage.isEnglish = shouldUseEnglish
        if quickPhrases == previousDefaults {
            quickPhrases = Self.defaultQuickPhrases
            UserDefaults.standard.set(quickPhrases, forKey: "quickPhrases")
        }
        petMessage.languageDidChange(above: panel)
        completionNotice.languageDidChange()
    }

    private func speakRandomPhrase() {
        guard let phrase = quickPhrases.randomElement() else { return }
        petMessage.showQuickPhrase(phrase, above: panel)
    }

    var snapshot: [String: Any] {
        ["ok": true, "visible": panel.isVisible, "status": status.rawValue, "label": view.taskLabel, "scale": scale, "petId": selectedPetID, "locale": PetLanguage.isEnglish ? "en" : "zh-CN", "message": petMessage.snapshot]
    }

    var petsSnapshot: [String: Any] {
        ["ok": true, "selectedPetId": selectedPetID, "pets": library.pets(selectedID: selectedPetID), "scale": scale, "visible": panel.isVisible]
    }

    var phrasesSnapshot: [String: Any] { ["ok": true, "phrases": quickPhrases] }
}

final class LocalControlServer {
    private let listener: NWListener
    private let controller: PetController

    init(controller: PetController) throws {
        self.controller = controller
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: 3081)
        listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
        listener.start(queue: DispatchQueue(label: "deepss.pet.http"))
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: DispatchQueue(label: "deepss.pet.connection"))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else { connection.cancel(); return }
            let headerEnd = request.range(of: "\r\n\r\n")
            let head = headerEnd.map { String(request[..<$0.lowerBound]) } ?? request
            let bodyText = headerEnd.map { String(request[$0.upperBound...]) } ?? ""
            let first = head.split(separator: "\r\n").first?.split(separator: " ") ?? []
            let method = first.first.map(String.init) ?? "GET"
            let requestTarget = first.count > 1 ? String(first[1]) : "/"
            let path = requestTarget.split(separator: "?").first.map(String.init) ?? "/"
            let query = URLComponents(string: "http://127.0.0.1\(requestTarget)")?.queryItems ?? []
            let queryValue: (String) -> String? = { name in query.first(where: { $0.name == name })?.value }
            let json = bodyText.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            if method == "GET", path == "/preview", let source = queryValue("source"), let id = queryValue("id") {
                do {
                    let preview = try self.controller.library.preview(source: source, id: id)
                    let response = "HTTP/1.1 200 OK\r\nContent-Type: \(preview.contentType)\r\nAccess-Control-Allow-Origin: http://127.0.0.1:3080\r\nCache-Control: public, max-age=86400\r\nContent-Length: \(preview.data.count)\r\nConnection: close\r\n\r\n"
                    connection.send(content: Data(response.utf8) + preview.data, completion: .contentProcessed { _ in connection.cancel() })
                } catch {
                    let response = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                    connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
                }
                return
            }
            var result: [String: Any] = ["ok": true]
            if method == "POST", path == "/install", let id = (json?["id"] as? String) ?? (json?["slug"] as? String) {
                do {
                    let source = json?["source"] as? String ?? "awesome-codex-pet"
                    let (localID, _) = try self.controller.library.install(source: source, id: id)
                    let shouldSelect = json?["select"] as? Bool ?? true
                    if shouldSelect { DispatchQueue.main.sync { _ = self.controller.selectPet(localID) } }
                    result = self.controller.petsSnapshot
                } catch {
                    result = ["ok": false, "error": error.localizedDescription]
                }
            } else if method == "POST", path == "/catalog" {
                do {
                    let page = json?["page"] as? Int ?? 1
                    let pageSize = json?["pageSize"] as? Int ?? 48
                    let query = json?["query"] as? String ?? ""
                    let source = json?["source"] as? String ?? "codex-pets"
                    result = try self.controller.library.catalog(source: source, page: page, pageSize: pageSize, query: query)
                    result["ok"] = true
                } catch {
                    result = ["ok": false, "error": error.localizedDescription]
                }
            } else if method == "POST", path == "/delete", let id = json?["id"] as? String {
                do {
                    try DispatchQueue.main.sync { _ = try self.controller.removePet(id) }
                    result = self.controller.petsSnapshot
                } catch {
                    result = ["ok": false, "error": error.localizedDescription]
                }
            } else {
                DispatchQueue.main.sync {
                    if method == "POST", path == "/control", let json {
                        self.controller.apply(json)
                        result = self.controller.snapshot
                    } else if method == "POST", path == "/select", let id = json?["id"] as? String {
                        result = self.controller.selectPet(id) ? self.controller.petsSnapshot : ["ok": false, "error": "未找到已安装的宠物"]
                    } else if method == "GET", path == "/pets" {
                        result = self.controller.petsSnapshot
                    } else if method == "GET", path == "/phrases" {
                        result = self.controller.phrasesSnapshot
                    } else if method == "POST", path == "/phrases", let phrases = json?["phrases"] as? [String] {
                        self.controller.setQuickPhrases(phrases)
                        result = self.controller.phrasesSnapshot
                    } else if method == "POST", path == "/focus" {
                        result = ["ok": true, "reused": focusHarnessWebUI()]
                    } else if method == "POST", path == "/quit" {
                        result = ["ok": true]
                        DispatchQueue.main.async { NSApplication.shared.terminate(nil) }
                    } else {
                        result = self.controller.snapshot
                    }
                }
            }
            let responseData = (try? JSONSerialization.data(withJSONObject: result)) ?? Data("{}".utf8)
            let response = "HTTP/1.1 200 OK\r\nContent-Type: application/json; charset=utf-8\r\nAccess-Control-Allow-Origin: http://127.0.0.1:3080\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type\r\nContent-Length: \(responseData.count)\r\nConnection: close\r\n\r\n"
            connection.send(content: Data(response.utf8) + responseData, completion: .contentProcessed { _ in connection.cancel() })
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: PetController?
    private var server: LocalControlServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        guard let url = Bundle.main.url(forResource: "spritesheet", withExtension: "png") else {
            fatalError("Missing spritesheet.png")
        }
        let library = PetLibrary(builtInAtlasURL: url)
        let controller = PetController(library: library)
        self.controller = controller
        self.server = try? LocalControlServer(controller: controller)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
