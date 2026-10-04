import AppKit
import SwiftUI

/// The quick chat's floating window (`Design/spec/chat.md` §一): borderless, non-activating and
/// on top like the panel, so the application the reader came from keeps its focus. It has no
/// dynamic height — the transcript scrolls inside it — and it is not tied to the panel's
/// lifecycle: it stays until it is closed.
@MainActor
final class CidaChatPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  init(width: CGFloat, height: CGFloat) {
    super.init(
      contentRect: NSRect(x: 0, y: 0, width: width, height: height),
      styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    level = .floating
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    hidesOnDeactivate = false
    isMovableByWindowBackground = false
    isReleasedWhenClosed = false
    backgroundColor = .clear
    isOpaque = false
    hasShadow = true
    animationBehavior = .none
    title = "快速问答"
    setAccessibilityIdentifier("cida-chat")
    setAccessibilityLabel("快速问答")
  }
}

/// Owns the chat window (`Design/spec/chat.md` §五): where it appears, what opening it does to
/// the conversation, when it goes away, and the keys that belong to the window rather than to
/// the input.
@MainActor
final class ChatController {
  let panel: CidaChatPanel
  private let model: ChatModel
  private let hostingView: NSHostingView<ChatView>
  private let openSettings: @MainActor () -> Void
  private var keyMonitor: Any?

  init(model: ChatModel, openSettings: @escaping @MainActor () -> Void) {
    self.model = model
    self.openSettings = openSettings
    let size = Self.contentSize(on: PanelController.activeScreen() ?? NSScreen.main)
    panel = CidaChatPanel(width: size.width, height: size.height)
    hostingView = NSHostingView(rootView: ChatView(model: model, openSettings: openSettings))
    hostingView.setAccessibilityLabel("快速问答内容")
    hostingView.setAccessibilityIdentifier("chat-content")
    // The window never changes size while it is up; the content follows it when a show moves it
    // to a screen with less room.
    hostingView.autoresizingMask = [.width, .height]
    hostingView.frame = NSRect(origin: .zero, size: size)
    let container = PanelContentView(frame: NSRect(origin: .zero, size: size))
    container.addSubview(hostingView)
    panel.contentView = container
    installKeyMonitor()
  }

  /// The window lives as long as the app; tear the monitor down here if an owner ever lets it go.
  func invalidate() {
    if let keyMonitor {
      NSEvent.removeMonitor(keyMonitor)
      self.keyMonitor = nil
    }
  }

  var isVisible: Bool {
    panel.isVisible
  }

  /// Width `chat-width`, height the smaller of `chat-max-height` and `chat-max-ratio` of the
  /// screen's free height (`Design/spec/chat.md` §一).
  static func contentSize(on screen: NSScreen?) -> NSSize {
    let visibleHeight = screen?.visibleFrame.height ?? CidaDesign.Chat.maxHeight
    return NSSize(
      width: CidaDesign.Chat.width,
      height: min(CidaDesign.Chat.maxHeight, floor(visibleHeight * CidaDesign.Chat.maxRatio)))
  }

  /// Opens a new conversation (`Design/spec/chat.md` §五) at the panel's top edge on the screen
  /// under the pointer, and gives the input the keyboard.
  func show() {
    guard let screen = PanelController.activeScreen() else { return }
    // Read before the window takes the keyboard: the note names where the reader was working
    // (`Design/spec/notes.md` §三's rule).
    let sourceApplication = SelectionNote.currentApplication()
    model.reset()
    model.refreshConfiguration()
    model.sourceApplication = sourceApplication

    let size = Self.contentSize(on: screen)
    panel.setContentSize(size)
    let visible = screen.visibleFrame
    let topEdge = CidaDesign.Panel.topEdge(in: visible)
    panel.setFrame(
      NSRect(
        x: floor(visible.midX - size.width / 2), y: topEdge - size.height, width: size.width,
        height: size.height),
      display: true)
    hostingView.frame = NSRect(origin: .zero, size: size)
    panel.alphaValue = 1
    panel.makeKeyAndOrderFront(nil)
    model.requestInputFocus()
  }

  /// Closes the window without touching what is being generated: a running answer finishes and
  /// is kept in the notes (`Design/spec/chat.md` §一); the next open starts a new conversation.
  func hide() {
    guard panel.isVisible else { return }
    panel.orderOut(nil)
  }

  func toggle() {
    if panel.isVisible { hide() } else { show() }
  }

  #if DEBUG
    /// A design capture shows the window the board draws at the token's height, not the height
    /// this Mac's screen gives it — the same reason the panel's automation budget is a fixture.
    func setContentHeightForDesign(_ height: CGFloat) {
      let size = NSSize(width: CidaDesign.Chat.width, height: height)
      panel.setContentSize(size)
      hostingView.frame = NSRect(origin: .zero, size: size)
    }
  #endif

  /// Window-level keys (`Design/spec/chat.md` §二). Everything else, ⏎ included, belongs to the
  /// input; the input method sees every key first, as it does in the panel.
  private func installKeyMonitor() {
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, NSApp.keyWindow === self.panel else { return event }
      if InputMethodRouting.isComposing(in: self.panel) { return event }
      let modifiers = event.modifierFlags
        .intersection(.deviceIndependentFlagsMask)
        .subtracting(.capsLock)

      if modifiers == .command, event.charactersIgnoringModifiers == "." {
        self.model.stop()
        return nil
      }
      if modifiers == .command, event.charactersIgnoringModifiers == "," {
        self.openSettings()
        return nil
      }
      if modifiers.isEmpty, event.keyCode == 53 {
        self.hide()
        return nil
      }
      return event
    }
  }
}
