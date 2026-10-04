import AppKit
import SwiftUI

/// The quick chat window's content (`Design/spec/chat.md` §二): the conversation's rounds over
/// the input line. A round is drawn the way the panel draws its two panes — the question on the
/// pane's surface in the interface face, the answer on paper in the result face — so one round
/// reads as the text that was sent and the text that came back.
struct ChatView: View {
  @Bindable var model: ChatModel
  var openSettings: @MainActor () -> Void = {}
  @State private var metrics: ComposerTextMetrics
  /// The end of the transcript, which the view keeps in sight while an answer streams.
  private static let bottomAnchor = "chat-transcript-bottom"

  init(model: ChatModel, openSettings: @escaping @MainActor () -> Void = {}) {
    self.model = model
    self.openSettings = openSettings
    _metrics = State(initialValue: ComposerTextMetrics(text: model.inputText))
  }

  var body: some View {
    VStack(spacing: 0) {
      transcript
      inputBar
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(CidaDesign.surface)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("chat-window")
  }

  // MARK: - Transcript

  private var transcript: some View {
    ScrollViewReader { proxy in
      GeometryReader { geometry in
        ScrollView {
          VStack(spacing: 0) {
            if model.needsModelConfiguration {
              ChatNoteRow(
                text: "还没有配置模型服务 · ⌘, 打开设置", icon: .circleAlert,
                identifier: "chat-unconfigured"
              )
              .padding(.horizontal, CidaDesign.Spacing.windowHorizontal)
              .padding(.vertical, CidaDesign.Spacing.paneVertical)
              .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(model.rounds) { round in
              ChatRoundView(round: round)
            }
            Color.clear
              .frame(height: 1)
              .id(Self.bottomAnchor)
          }
          // A conversation shorter than the window sits on the input line, the way a chat does:
          // it grows upward as it is written (`Design/spec/chat.md` §二).
          .frame(minHeight: geometry.size.height, alignment: .bottom)
        }
        .scrollBounceBehavior(.basedOnSize)
        // Every change on screen is one more step of the answer; the reader follows the end of
        // the transcript.
        .onChange(of: model.presentationRevision) {
          proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
        }
        .onAppear {
          proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .accessibilityIdentifier("chat-transcript")
  }

  // MARK: - Input

  /// The input line (`Design/spec/chat.md` §二): the panel's composer, its placeholder, and the
  /// pill that sends or stops. It grows with the text up to `chat-input-max-height`.
  private var inputBar: some View {
    VStack(spacing: 0) {
      Hairline()
      HStack(alignment: .bottom, spacing: 12) {
        ZStack(alignment: .topLeading) {
          if !metrics.hasText {
            Text("问一句，回车发送…")
              .font(CidaDesign.body(CidaDesign.Typography.bodySize))
              .foregroundStyle(CidaDesign.textTertiary)
              .frame(height: CidaDesign.Panel.composerLineHeight)
              .allowsHitTesting(false)
          }
          ComposerTextEditor(
            text: $model.inputText,
            metrics: $metrics,
            horizontalInset: 0,
            maxVisibleHeight: CidaDesign.Chat.inputMaxHeight,
            focusRevision: model.inputFocusRequestID,
            replacementRevision: model.inputReplacementRevision,
            onSubmit: { model.send() },
            onVirtualDocumentChange: { document, _, _ in model.stageInputDocument(document) }
          )
          .frame(height: editorHeight)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        ChatActionPill(model: model)
      }
      .padding(.horizontal, CidaDesign.Spacing.windowHorizontal)
      .padding(.vertical, CidaDesign.Spacing.paneVertical)
    }
    .background(CidaDesign.surface)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("chat-input")
  }

  /// The editor takes the height of its text up to the input's cap, like the panel's source
  /// editor does; a document too large to measure takes the cap outright.
  private var editorHeight: CGFloat {
    guard let natural = metrics.naturalHeight else {
      if metrics.isDocument { return CidaDesign.Chat.inputMaxHeight }
      let lines = CGFloat(max(1, metrics.lineCount))
      let estimated = max(
        CidaDesign.Panel.compactEditorHeight, lines * CidaDesign.Panel.composerLineHeight)
      return min(CidaDesign.Chat.inputMaxHeight, estimated)
    }
    return min(
      CidaDesign.Chat.inputMaxHeight,
      max(CidaDesign.Panel.compactEditorHeight, ceil(natural)))
  }
}

// MARK: - One round

/// A question and its answer (`Design/spec/chat.md` §二): the question on `surface`, the answer
/// on `surface-paper`, a hairline between rounds.
private struct ChatRoundView: View {
  let round: ChatRound

  var body: some View {
    VStack(spacing: 0) {
      question
      answer
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("chat-round")
  }

  private var question: some View {
    Text(round.question)
      .font(CidaDesign.body(CidaDesign.Typography.bodySize))
      .foregroundStyle(CidaDesign.textPrimary)
      .lineSpacing(ChatTypography.sourceLineSpacing)
      .frame(maxWidth: .infinity, alignment: .leading)
      .textSelection(.enabled)
      .padding(.top, CidaDesign.Spacing.paneVertical + ChatTypography.sourceLineSpacing / 2)
      .padding(.bottom, CidaDesign.Spacing.paneVertical + ChatTypography.sourceLineSpacing / 2)
      .padding(.horizontal, CidaDesign.Spacing.windowHorizontal)
      .background(CidaDesign.surface)
  }

  private var answer: some View {
    VStack(alignment: .leading, spacing: 10) {
      ChatAnswerText(round: round)
      switch round.phase {
      case .failed(let message):
        ChatNoteRow(
          text: "请求失败：\(message)", icon: .circleAlert, identifier: "chat-failed")
      case .stopped:
        ChatNoteRow(text: "已停止", icon: .circleStop, identifier: "chat-stopped")
      case .streaming, .completed:
        EmptyView()
      }
    }
    .padding(.horizontal, CidaDesign.Spacing.windowHorizontal)
    .padding(.vertical, CidaDesign.Spacing.resultVertical)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(CidaDesign.surfacePaper)
  }
}

/// The answer in the result face, with the accent caret while it streams: the same typography
/// and the same caret as the panel's result pane, and the same rule for which script decides the
/// face (`ChatRound.outputLanguage` settles it once the first characters have arrived).
private struct ChatAnswerText: View {
  let round: ChatRound
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    if round.phase == .streaming, !reduceMotion {
      TimelineView(.animation) { context in
        text(
          caretOpacity: Double(
            StatusItemMark.caretOpacity(after: context.date.timeIntervalSinceReferenceDate)))
      }
    } else {
      text(caretOpacity: round.phase == .streaming ? 1 : nil)
    }
  }

  private func text(caretOpacity: Double?) -> some View {
    var composed = Text(round.answer).foregroundStyle(CidaDesign.textInk)
    if let caretOpacity {
      composed =
        composed
        + Text(Image(nsImage: PaperCaret.image(opacity: caretOpacity)))
        .baselineOffset(-ResultTextStyle.caretDescent)
    }
    let font = ChatTypography.resultFont(for: round.outputLanguage)
    let lineSpacing = ChatTypography.resultLineSpacing(for: round.outputLanguage)
    return composed
      .font(Font(font))
      .lineSpacing(lineSpacing)
      .frame(maxWidth: .infinity, alignment: .leading)
      .textSelection(.enabled)
      // CSS centres a line's glyphs in its line box; the first and last lines carry their half
      // of the leading too, as the panel's paper does.
      .padding(.top, lineSpacing / 2)
      .padding(.bottom, lineSpacing / 2 - (caretOpacity == nil ? 0 : ResultTextStyle.caretDescent))
  }
}

/// The two faces the chat's round is set in, and what each adds to reach the design's line
/// heights (`tokens.css` 26 / 29 / 31).
@MainActor
private enum ChatTypography {
  static let sourceFont = CidaDesign.appKitBody(CidaDesign.Typography.bodySize)
  static let sourceLineSpacing = max(
    0, CidaDesign.Panel.composerLineHeight - NSLayoutManager().defaultLineHeight(for: sourceFont))

  private static let latinFont = CidaDesign.appKitResult(for: .english)
  private static let cjkFont = CidaDesign.appKitResult(for: .chinese)

  static func resultFont(for language: Language) -> NSFont {
    language == .chinese ? cjkFont : latinFont
  }

  static func resultLineSpacing(for language: Language) -> CGFloat {
    let lineHeight =
      language == .chinese
      ? CidaDesign.Typography.resultLineHeightCJK : CidaDesign.Typography.resultLineHeight
    return max(0, lineHeight - NSLayoutManager().defaultLineHeight(for: resultFont(for: language)))
  }
}

/// One line under the answer or in an empty transcript: the panel's note row, in the chat's
/// own words.
private struct ChatNoteRow: View {
  let text: String
  let icon: LucideIconName
  let identifier: String

  var body: some View {
    HStack(spacing: 8) {
      LucideIcon(icon, size: 13)
        .foregroundStyle(CidaDesign.textTertiary)
      Text(text)
        .font(CidaDesign.mainUI(13))
        .foregroundStyle(CidaDesign.textSecondary)
        .lineLimit(1)
    }
    .frame(height: ResultNoteRow.height)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier(identifier)
  }
}

/// 发送 ⏎ / 停止 ⌘., in the control bar's pill (`Design/spec/chat.md` §二).
private struct ChatActionPill: View {
  let model: ChatModel

  var body: some View {
    if let title = model.inputAction.title, let key = model.inputAction.key {
      Button {
        switch model.inputAction {
        case .send: model.send()
        case .stop: model.stop()
        case .none: break
        }
      } label: {
        HStack(spacing: 8) {
          if model.inputAction == .stop {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
              .fill(CidaDesign.textControl)
              .frame(width: 10, height: 10)
          }
          Text(title)
            .font(CidaDesign.mainUI(11.5, weight: .semibold))
            .foregroundStyle(CidaDesign.textControl)
          Text(key)
            .font(CidaDesign.mainUI(11))
            .foregroundStyle(CidaDesign.textTertiary)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background {
          RoundedRectangle(cornerRadius: CidaDesign.Radius.card, style: .continuous)
            .fill(CidaDesign.surface)
            .overlay {
              RoundedRectangle(cornerRadius: CidaDesign.Radius.card, style: .continuous)
                .strokeBorder(CidaDesign.border, lineWidth: 1)
            }
        }
      }
      .buttonStyle(HoverFadeButtonStyle())
      .accessibilityLabel(title)
      .accessibilityIdentifier(model.inputAction == .stop ? "chat-action-stop" : "chat-action-send")
    }
  }
}
