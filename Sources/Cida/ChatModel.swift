import Foundation

/// One round of the quick chat (`Design/spec/chat.md` §二): what was asked and what came back.
/// A round stays in the window until the conversation is reset; the answer is what is being
/// streamed into it while it arrives.
struct ChatRound: Identifiable, Equatable, Sendable {
  let id: UUID
  let question: String
  var answer: String
  var phase: ChatAnswerPhase
  /// The script the answer is drawn in, settled once its first characters arrive (`spec/panel.md`
  /// §七's rule, so the paper does not switch fonts under the reader on every chunk).
  var outputLanguage: Language = .chinese
  var languageSettled = false

  init(
    id: UUID = UUID(),
    question: String,
    answer: String = "",
    phase: ChatAnswerPhase = .streaming
  ) {
    self.id = id
    self.question = question
    self.answer = answer
    self.phase = phase
  }

  /// The round as the transcript writes it (`Design/spec/chat.md` §四).
  var transcript: String {
    "问：\(question)\n\n答：\(answer.trimmingCharacters(in: .whitespacesAndNewlines))"
  }
}

enum ChatAnswerPhase: Equatable, Sendable {
  case streaming
  case completed
  case stopped
  case failed(message: String)

  var isTerminal: Bool { self != .streaming }
}

/// Where a conversation goes (`Design/spec/chat.md` §三). The default talks to the configured
/// model service through the same client the panel uses, so a chat fails and streams exactly
/// like a translation does; tests hand in their own.
protocol ChatService: Sendable {
  func stream(
    systemPrompt: String, turns: [ModelPromptMessage], settings: CidaSettings
  ) -> AsyncThrowingStream<String, Error>

  /// Whether `settings` hold everything this service needs to send a request.
  func isConfigured(by settings: CidaSettings) -> Bool
}

extension ChatService {
  func isConfigured(by settings: CidaSettings) -> Bool { true }
}

struct ModelChatService: ChatService {
  var client = ModelServiceClient()

  func isConfigured(by settings: CidaSettings) -> Bool {
    settings.isModelServiceComplete
  }

  func stream(
    systemPrompt: String, turns: [ModelPromptMessage], settings: CidaSettings
  ) -> AsyncThrowingStream<String, Error> {
    client.stream(
      prompt: .conversation(systemMessage: systemPrompt, messages: turns), settings: settings)
  }
}

/// The quick chat window's conversation (`Design/spec/chat.md`).
///
/// It owns one conversation at a time: the rounds on screen, the draft in the input, and the
/// request that is running. Opening the window calls `reset()`, so reopening it is a new
/// conversation; every completed answer is handed to `saveNote` as the whole conversation up to
/// that round, which is what the notes file keeps.
@MainActor
@Observable
final class ChatModel {
  /// The rounds of this conversation, in the order they were asked.
  private(set) var rounds: [ChatRound] = []
  /// What is typed in the input; cleared when its question is sent.
  var inputText = ""
  /// An answer is streaming: the input's pill is 停止 and ⏎ does not send.
  private(set) var isAnswering = false
  /// The window shows 还没有配置模型服务 in place of the transcript (`spec/chat.md` §三);
  /// refreshed when the window opens.
  private(set) var needsModelConfiguration = false
  /// The application the window was summoned from; the notes name it (`spec/chat.md` §四).
  var sourceApplication: NoteSourceApplication?
  /// Bumped whenever what is on screen changes, so the view can follow the bottom of the
  /// transcript while an answer streams.
  private(set) var presentationRevision = 0
  /// Bumped when the input should take keyboard focus, once per appearance.
  private(set) var inputFocusRequestID = 0
  /// Bumped when the input is emptied for the model rather than by the reader, so the editor
  /// drops a document too large to live in the binding (`ComposerNativeTextView`).
  private(set) var inputReplacementRevision = 0
  /// The document behind the input while the editor virtualizes a very large paste; the
  /// question is this, not the binding's placeholder.
  @ObservationIgnored private var stagedInputDocument: String?

  private let service: any ChatService
  private let settings: @MainActor () -> CidaSettings
  /// Hands the whole conversation so far to the note store (`spec/chat.md` §四); the owner
  /// decides whether and how it lands.
  private let saveNote: @MainActor (String) -> Void
  private var answerTask: Task<Void, Never>?
  /// Identifies the conversation a running answer belongs to, so a request that outlives its
  /// conversation cannot write into the next one.
  private var generation = 0

  /// How often the streaming answer is handed to the view. The panel appends every delta to a
  /// TextKit storage that lays out only the suffix; the chat's paper is plain SwiftUI text, so
  /// it takes the answer in steps of about a frame instead of re-laying out per chunk
  /// (`Design/spec/chat.md` §二).
  static let presentationInterval = Duration.milliseconds(33)

  init(
    service: any ChatService = ModelChatService(),
    settings: @escaping @MainActor () -> CidaSettings = { CidaSettings() },
    saveNote: @escaping @MainActor (String) -> Void = { _ in }
  ) {
    self.service = service
    self.settings = settings
    self.saveNote = saveNote
  }

  /// What the reader has typed (or pasted): a document too large for the editor's binding is
  /// reported separately and stands in for it.
  var currentInputDocument: String {
    stagedInputDocument ?? inputText
  }

  var hasSubmittableInput: Bool {
    (currentInputDocument as NSString).rangeOfCharacter(from: .whitespacesAndNewlines.inverted)
      .location != NSNotFound
  }

  /// The editor reports the document it holds when it virtualizes one, and nil when it does not.
  func stageInputDocument(_ document: String?) {
    stagedInputDocument = document
  }

  /// What the input's pill offers (`spec/chat.md` §二): 发送 with a question typed and nothing
  /// running, 停止 while an answer streams, nothing otherwise.
  var inputAction: ChatInputAction {
    if isAnswering { return .stop }
    return hasSubmittableInput && !needsModelConfiguration ? .send : .none
  }

  /// Re-reads the model service: the window asks nothing until one is configured.
  func refreshConfiguration() {
    needsModelConfiguration = !service.isConfigured(by: settings())
  }

  func requestInputFocus() {
    inputFocusRequestID &+= 1
  }

  /// ⏎ or 发送: appends the question and asks the model (`Design/spec/chat.md` §三).
  @discardableResult
  func send() -> Bool {
    guard !isAnswering, !needsModelConfiguration else { return false }
    let question = currentInputDocument.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !question.isEmpty else { return false }
    clearInput()
    rounds.append(ChatRound(question: question))
    presentationRevision &+= 1
    isAnswering = true

    let index = rounds.count - 1
    let turns = conversationForRequest()
    let prompt = settings().chatPrompt
    let requestSettings = settings()
    let generation = self.generation
    answerTask = Task { [weak self] in
      await self?.answer(
        index: index, generation: generation, systemPrompt: prompt, turns: turns,
        settings: requestSettings)
    }
    return true
  }

  /// ⌘.: the streaming answer stops where it is (`spec/chat.md` §三). What arrived stays in the
  /// window and is marked 已停止; nothing is written to the notes.
  func stop() {
    answerTask?.cancel()
  }

  /// A new conversation (`Design/spec/chat.md` §五): the rounds, the draft, the failure state and
  /// any running request go; the notes already written stay.
  func reset() {
    generation &+= 1
    answerTask?.cancel()
    answerTask = nil
    isAnswering = false
    rounds = []
    clearInput()
    sourceApplication = nil
    presentationRevision &+= 1
  }

  /// Empties the input for the next question, whichever way the text got there.
  private func clearInput() {
    inputText = ""
    stagedInputDocument = nil
    inputReplacementRevision &+= 1
  }

  /// The whole conversation up to and including round `index`, as the note file keeps it
  /// (`Design/spec/chat.md` §四): the rounds so far, each a 问 block and a 答 block. Every
  /// finished round writes this again, so the last line of a conversation holds all of it.
  func transcript(through index: Int) -> String {
    rounds.prefix(index + 1).map(\.transcript).joined(separator: "\n\n")
  }

  /// The conversation as the model sees it (`spec/chat.md` §三): every earlier round in order,
  /// then the question just asked. An answer that was stopped or failed is sent as the text the
  /// reader saw; a round whose answer never arrived contributes only its question, since no
  /// service accepts an empty message.
  private func conversationForRequest() -> [ModelPromptMessage] {
    var messages: [ModelPromptMessage] = []
    for (index, round) in rounds.enumerated() {
      messages.append(ModelPromptMessage(role: .user, text: round.question))
      guard index < rounds.count - 1 else { continue }
      let answer = round.answer.trimmingCharacters(in: .whitespacesAndNewlines)
      if !answer.isEmpty {
        messages.append(ModelPromptMessage(role: .assistant, text: answer))
      }
    }
    return messages
  }

  private func answer(
    index: Int, generation: Int, systemPrompt: String, turns: [ModelPromptMessage],
    settings: CidaSettings
  ) async {
    var text = ""
    var lastPublication = ContinuousClock.now.advanced(by: .seconds(-1))
    do {
      for try await chunk in service.stream(
        systemPrompt: systemPrompt, turns: turns, settings: settings)
      {
        try Task.checkCancellation()
        text += chunk
        let now = ContinuousClock.now
        if now - lastPublication >= Self.presentationInterval {
          update(index, answer: text, generation: generation)
          lastPublication = now
        }
      }
      try Task.checkCancellation()
      guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw ModelServiceError.emptyResult
      }
      update(index, answer: text, generation: generation)
      finish(index, phase: .completed, generation: generation)
      // Only a finished answer is worth keeping: the reader asked, and the answer is the note.
      saveNote(transcript(through: index))
    } catch is CancellationError {
      finish(index, phase: .stopped, generation: generation)
    } catch {
      finish(index, phase: .failed(message: error.localizedDescription), generation: generation)
    }
  }

  private func update(_ index: Int, answer: String, generation: Int) {
    guard generation == self.generation, rounds.indices.contains(index) else { return }
    rounds[index].answer = answer
    if !rounds[index].languageSettled, answer.utf16.count >= 12 {
      rounds[index].languageSettled = true
      if let typography = TextLanguageDetector.typography(of: answer) {
        rounds[index].outputLanguage = typography
      }
    }
    presentationRevision &+= 1
  }

  private func finish(_ index: Int, phase: ChatAnswerPhase, generation: Int) {
    guard generation == self.generation, rounds.indices.contains(index) else { return }
    rounds[index].phase = phase
    if !rounds[index].languageSettled {
      rounds[index].languageSettled = true
      if let typography = TextLanguageDetector.typography(of: rounds[index].answer) {
        rounds[index].outputLanguage = typography
      }
    }
    if index == rounds.count - 1 { isAnswering = false }
    // A stopped or failed round hands its question back to the input, so ⏎ asks it again
    // (`Design/spec/chat.md` §三); whatever the reader has already typed is left alone.
    if phase != .completed, !hasSubmittableInput {
      inputText = rounds[index].question
      stagedInputDocument = nil
      inputReplacementRevision &+= 1
    }
    presentationRevision &+= 1
  }

  #if DEBUG
    /// The states `Design/boards/chat.html` draws (`--design-state chat-*`).
    func setRoundsForDesign(_ rounds: [ChatRound], input: String = "") {
      self.rounds = rounds
      inputText = input
      presentationRevision &+= 1
    }
  #endif
}

#if DEBUG
  extension ChatRound {
    /// The rounds and the draft `Design/boards/chat.html` draws, word for word.
    static let designQuestion = "tar 的 -p 是什么意思？"
    static let designAnswer =
      "-p 是 --preserve-permissions 的缩写：解开归档时保留文件原本的权限位，而不是按 umask 重新计算。它一般用于以 root 解包系统备份；普通用户解自己的包时不需要。"
    static let designStreamingAnswer = "-p 是 --preserve-permissions 的缩写：解开归档时保留文件原本的权限位，而不是按 umask 重新计算。"
    static let designFollowUpQuestion = "那 -m 呢？"
    static let designFollowUpAnswer =
      "-m 是 --touch：解包时不恢复文件时间，而是把 mtime 设为解包的那一刻。GNU tar 里它主要用于做可复现的归档。"
    static let designFailedAnswer = "-p 是 --preserve-permissions 的缩写：解开归档时保留文件原本的权限位，"
    static let designDraft = "那解包到 /tmp 呢？"

    static func designCompleted(question: String, answer: String) -> ChatRound {
      designRound(question: question, answer: answer, phase: .completed)
    }

    static func designStreaming(question: String, partial: String) -> ChatRound {
      designRound(question: question, answer: partial, phase: .streaming)
    }

    static func designFailed(question: String, partial: String) -> ChatRound {
      designRound(
        question: question, answer: partial,
        phase: .failed(message: "401 Unauthorized（deepseek-chat）"))
    }

    private static func designRound(
      question: String, answer: String, phase: ChatAnswerPhase
    ) -> ChatRound {
      var round = ChatRound(question: question, answer: answer, phase: phase)
      round.languageSettled = true
      round.outputLanguage = .chinese
      return round
    }
  }
#endif

/// What the input's pill offers (`Design/spec/chat.md` §二).
enum ChatInputAction: Equatable, Sendable {
  case none
  case send
  case stop

  var title: String? {
    switch self {
    case .none: nil
    case .send: "发送"
    case .stop: "停止"
    }
  }

  var key: String? {
    switch self {
    case .none: nil
    case .send: "⏎"
    case .stop: "⌘."
    }
  }
}
