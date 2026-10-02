import AppKit
import Foundation

/// What the hint pill says after a note action; `dismissAfter` nil keeps it until it is replaced.
struct NoteFeedback: Equatable {
  let text: String
  var dismissAfter: Double?
}

/// Saves the frontmost application's selection as a note (`Design/spec/notes.md`).
///
/// It is Cida's shortest path: no panel, no request, no focus change. The selection comes from
/// the same reader ⌥A uses, so an application that cannot answer through Accessibility is still
/// read through a temporary ⌘C.
@MainActor
final class SelectionNote {
  private let defaultStore: NoteStore
  private let readSelection: @MainActor () async -> String?
  private let frontmostApplication: @MainActor () -> NoteSourceApplication?

  var onFeedback: (NoteFeedback?) -> Void = { _ in }
  var recordEvent: (String) -> Void = { _ in }
  private(set) var isSaving = false

  init(
    store: NoteStore = NoteStore(),
    readSelection: @escaping @MainActor () async -> String? = {
      await SelectedText.read(
        from: AccessibilitySelectedTextSource(), copyingWith: PasteboardSelectionCopier())
    },
    frontmostApplication: @escaping @MainActor () -> NoteSourceApplication? = {
      SelectionNote.currentApplication()
    }
  ) {
    self.defaultStore = store
    self.readSelection = readSelection
    self.frontmostApplication = frontmostApplication
  }

  /// The application the user is working in; nil in Cida itself.
  static func currentApplication(
    processIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier
  ) -> NoteSourceApplication? {
    guard let application = NSWorkspace.shared.frontmostApplication,
      application.processIdentifier != processIdentifier
    else { return nil }
    return NoteSourceApplication(
      name: application.localizedName, bundleIdentifier: application.bundleIdentifier)
  }

  /// Reads the selection and saves it. The file comes from the settings, so a change in Settings
  /// applies to the next press.
  func saveSelection(settings: CidaSettings) async {
    guard !isSaving else { return }
    isSaving = true
    defer { isSaving = false }

    // Read the source application before the selection: reading may ask another application to
    // copy, and the note should name where the user was working, not where the copy landed.
    let application = frontmostApplication()
    guard let selection = await readSelection() else {
      onFeedback(NoteFeedback(text: "请先选中要记下来的文字", dismissAfter: 2.5))
      recordEvent("note-no-selection")
      return
    }
    save(text: selection, application: application, settings: settings)
  }

  /// Saves text the caller already holds — the panel's ⌘S.
  func save(text: String, application: NoteSourceApplication?, settings: CidaSettings) {
    let store = store(for: settings)
    let draft = NoteDraft(text: text, source: "selection", application: application, note: nil)
    guard !store.isRecentDuplicate(draft) else {
      onFeedback(NoteFeedback(text: "刚刚已存过这条", dismissAfter: CidaHintPanel.briefSeconds))
      recordEvent("note-duplicate")
      return
    }
    do {
      try store.append(draft)
      let name = application?.name
      onFeedback(
        NoteFeedback(
          text: name.map { "已存入笔记 · \($0)" } ?? "已存入笔记",
          dismissAfter: CidaHintPanel.briefSeconds))
      recordEvent("note-saved source=\(draft.source)")
    } catch let error as NoteStoreError {
      onFeedback(NoteFeedback(text: "存入失败：\(error.message)", dismissAfter: 2.5))
      recordEvent("note-failed")
    } catch {
      onFeedback(NoteFeedback(text: "存入失败：\(error.localizedDescription)", dismissAfter: 2.5))
      recordEvent("note-failed")
    }
  }

  /// The file the settings name, or the one Cida was given.
  private func store(for settings: CidaSettings) -> NoteStore {
    let path = settings.noteFile.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !path.isEmpty else { return defaultStore }
    return NoteStore(fileURL: URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
  }
}
