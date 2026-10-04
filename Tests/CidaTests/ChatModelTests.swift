import XCTest

@testable import Cida

/// The quick chat (`Design/spec/chat.md`): the conversation in the window, the request that
/// carries it, and the whole conversation being written to the notes after every finished round.
@MainActor
final class ChatModelTests: XCTestCase {
  // MARK: - The window

  func testSendingPutsTheQuestionInTheWindowAndAsksTheModel() async throws {
    let service = StubChatService(answers: [["-p 是 --preserve-permissions。"]])
    let model = makeModel(service: service)
    model.inputText = "tar 的 -p 是什么意思？"

    XCTAssertTrue(model.send())
    XCTAssertEqual(model.inputText, "", "the draft is what was sent")
    XCTAssertEqual(model.rounds.count, 1)
    XCTAssertEqual(model.rounds[0].question, "tar 的 -p 是什么意思？")
    XCTAssertEqual(model.inputAction, .stop, "one request at a time")

    try await waitUntil { !model.isAnswering }
    XCTAssertEqual(model.rounds[0].answer, "-p 是 --preserve-permissions。")
    XCTAssertEqual(model.rounds[0].phase, .completed)
    XCTAssertEqual(model.inputAction, .none, "an empty input offers nothing")
  }

  func testAFollowUpCarriesEveryEarlierTurnAndGetsItsOwnPlaceInTheWindow() async throws {
    let service = StubChatService(answers: [["A1"], ["A2"]])
    let model = makeModel(service: service)

    model.inputText = "Q1"
    model.send()
    try await waitUntil { !model.isAnswering }
    model.inputText = "  Q2  "
    model.send()
    try await waitUntil { !model.isAnswering }

    XCTAssertEqual(model.rounds.map(\.question), ["Q1", "Q2"], "the question is trimmed")
    XCTAssertEqual(model.rounds.map(\.answer), ["A1", "A2"])

    let requests = service.recordedRequests
    XCTAssertEqual(requests.count, 2)
    XCTAssertEqual(requests[0].turns, [ModelPromptMessage(role: .user, text: "Q1")])
    XCTAssertEqual(
      requests[1].turns,
      [
        ModelPromptMessage(role: .user, text: "Q1"),
        ModelPromptMessage(role: .assistant, text: "A1"),
        ModelPromptMessage(role: .user, text: "Q2"),
      ],
      "the model sees the conversation, not just the last question")
  }

  func testTheSystemPromptIsWhatTheSettingsHold() async throws {
    var settings = CidaSettings()
    settings.chatSystemPrompt = "你是我的笔记助手。"
    let service = StubChatService(answers: [["好。"]])
    let model = makeModel(service: service, settings: { settings })

    model.inputText = "在吗"
    model.send()
    try await waitUntil { !model.isAnswering }

    XCTAssertEqual(service.recordedRequests.first?.systemPrompt, "你是我的笔记助手。")
    settings.chatSystemPrompt = "   "
    XCTAssertEqual(settings.chatPrompt, CidaSettings.defaultChatPrompt, "an empty field means the default")
  }

  func testStoppingKeepsWhatArrivedAndAsksNothingOfTheNotes() async throws {
    let service = StubChatService(answers: [["前半段"]], holds: true)
    let notes = NoteRecorder()
    let model = makeModel(service: service, saveNote: notes.record)

    model.inputText = "Q1"
    model.send()
    try await waitUntil { model.rounds.first?.answer == "前半段" }
    model.stop()
    try await waitUntil { !model.isAnswering }

    XCTAssertEqual(model.rounds[0].phase, .stopped)
    XCTAssertEqual(model.rounds[0].answer, "前半段", "what arrived stays on the paper")
    XCTAssertEqual(model.inputText, "Q1", "the question comes back to the input")
    XCTAssertEqual(notes.transcripts, [], "a stopped answer is not a note")
  }

  func testFailingSaysWhyOnThePaperAndAsksNothingOfTheNotes() async throws {
    let service = StubChatService(answers: [["前半段"]], failure: .http503)
    let notes = NoteRecorder()
    let model = makeModel(service: service, saveNote: notes.record)

    model.inputText = "Q1"
    model.send()
    try await waitUntil { !model.isAnswering }

    guard case .failed(let message) = model.rounds[0].phase else {
      return XCTFail("expected a failed round, got \(model.rounds[0].phase)")
    }
    XCTAssertEqual(message, ModelServiceError.http(status: 503, providerMessage: nil, body: "").localizedDescription)
    XCTAssertEqual(model.rounds[0].answer, "前半段")
    XCTAssertEqual(model.inputText, "Q1")
    XCTAssertEqual(notes.transcripts, [])
  }

  func testTheWindowAsksNothingUntilAModelServiceIsConfigured() async throws {
    let service = StubChatService(answers: [["never sent"]], isReady: false)
    let model = makeModel(service: service)

    model.refreshConfiguration()
    XCTAssertTrue(model.needsModelConfiguration)
    model.inputText = "Q1"
    XCTAssertEqual(model.inputAction, .none)
    XCTAssertFalse(model.send())
    XCTAssertEqual(model.rounds, [])
  }

  // MARK: - The quoted selection

  func testASelectionIsQuotedWithABlankLineUnderIt() {
    let model = makeModel(service: StubChatService(answers: []))

    model.insertQuote("第一行\n\n第二行")
    XCTAssertEqual(
      model.inputText, "> 第一行\n>\n> 第二行\n\n",
      "every line carries its mark, and the instruction has its own paragraph")

    model.insertQuote("一句话")
    XCTAssertEqual(model.inputText, "> 一句话\n\n")

    model.insertQuote("a\r\nb")
    XCTAssertEqual(model.inputText, "> a\n> b\n\n", "a Windows line ending is one line")
  }

  func testTheInstructionUnderTheQuoteIsPartOfTheQuestion() async throws {
    let service = StubChatService(answers: [["是 --preserve-permissions。"], ["因为解包要保留权限位。"]])
    let notes = NoteRecorder()
    let model = makeModel(service: service, saveNote: notes.record)

    model.insertQuote("-p, --preserve-permissions\n    extract information about permissions")
    model.inputText += "这是什么意思？"
    model.send()
    try await waitUntil { notes.transcripts.count == 1 }

    XCTAssertEqual(
      model.rounds[0].question,
      "> -p, --preserve-permissions\n>     extract information about permissions\n\n这是什么意思？")
    XCTAssertEqual(
      service.recordedRequests.first?.turns,
      [
        ModelPromptMessage(
          role: .user,
          text: "> -p, --preserve-permissions\n>     extract information about permissions\n\n这是什么意思？")
      ])
    XCTAssertEqual(
      notes.transcripts.first,
      "问：> -p, --preserve-permissions\n>     extract information about permissions\n\n这是什么意思？\n\n答：是 --preserve-permissions。")
  }

  // MARK: - The notes

  func testEveryFinishedRoundWritesTheWholeConversationSoFar() async throws {
    let service = StubChatService(answers: [["A1"], ["A2"]])
    let notes = NoteRecorder()
    let model = makeModel(service: service, saveNote: notes.record)

    model.inputText = "Q1"
    model.send()
    try await waitUntil { notes.transcripts.count == 1 }
    model.inputText = "Q2"
    model.send()
    try await waitUntil { notes.transcripts.count == 2 }

    XCTAssertEqual(
      notes.transcripts,
      [
        "问：Q1\n\n答：A1",
        "问：Q1\n\n答：A1\n\n问：Q2\n\n答：A2",
      ],
      "each round is written again with everything before it")
    XCTAssertEqual(model.transcript(through: 0), notes.transcripts[0])
    XCTAssertEqual(model.transcript(through: 1), notes.transcripts[1])
  }

  // MARK: - Reopening

  func testResetIsANewConversationAndCancelsWhatIsRunning() async throws {
    let service = StubChatService(answers: [["前半段", "后半段"]], holds: true)
    let notes = NoteRecorder()
    let model = makeModel(service: service, saveNote: notes.record)

    model.inputText = "Q1"
    model.send()
    try await waitUntil { model.rounds.first?.answer == "前半段" }

    model.reset()
    XCTAssertEqual(model.rounds, [])
    XCTAssertEqual(model.inputText, "")
    XCTAssertFalse(model.isAnswering)
    XCTAssertNil(model.sourceApplication)

    // Whatever the abandoned request does next must not reach the new conversation.
    service.release()
    try await Task.sleep(for: .milliseconds(80))
    XCTAssertEqual(model.rounds, [])
    XCTAssertEqual(notes.transcripts, [], "the cancelled answer is not a note")
  }

  func testTheWindowRemembersWhereItWasSummonedFrom() async throws {
    let service = StubChatService(answers: [["A1"]])
    let notes = NoteRecorder()
    let model = makeModel(service: service, saveNote: notes.record)
    model.sourceApplication = NoteSourceApplication(name: "Safari", bundleIdentifier: "com.apple.Safari")

    model.inputText = "Q1"
    model.send()
    try await waitUntil { notes.transcripts.count == 1 }

    model.reset()
    XCTAssertNil(model.sourceApplication, "the next conversation names its own application")
  }

  // MARK: - The settings it takes

  func testOlderSettingsGetTheChatDefaultsAndNeverASecondOptionC() throws {
    let optionC = String(
      decoding: try JSONEncoder().encode(GlobalShortcut.optionC), as: UTF8.self)

    // A file written before the chat has no chat keys: it gets ⌥C and the default prompt.
    let plain = try JSONDecoder().decode(CidaSettings.self, from: Data("{}".utf8))
    XCTAssertEqual(plain.chatShortcut, .optionC)
    XCTAssertEqual(plain.chatSystemPrompt, CidaSettings.defaultChatPrompt)

    // A file that already gave ⌥C to another action keeps that one; the chat has no shortcut
    // until the user records one, as improvementShortcut does on first upgrade.
    let taken = try JSONDecoder().decode(
      CidaSettings.self, from: Data("{\"shortcut\":\(optionC)}".utf8))
    XCTAssertNil(taken.chatShortcut)

    // A null is a shortcut the user cleared, not a missing key.
    let cleared = try JSONDecoder().decode(
      CidaSettings.self, from: Data(#"{"chatShortcut":null}"#.utf8))
    XCTAssertNil(cleared.chatShortcut)

    // And what is written back is what is read again.
    var settings = CidaSettings()
    settings.chatSystemPrompt = "你是我的笔记助手。"
    settings.chatShortcut = nil
    let roundTripped = try JSONDecoder().decode(
      CidaSettings.self, from: try JSONEncoder().encode(settings))
    XCTAssertEqual(roundTripped.chatSystemPrompt, "你是我的笔记助手。")
    XCTAssertNil(roundTripped.chatShortcut)
  }

  // MARK: - The request the three formats are given

  func testAConversationIsSentAsMessagesInEveryFormat() throws {
    let prompt = ModelPrompt.conversation(
      systemMessage: "SYSTEM",
      messages: [
        ModelPromptMessage(role: .user, text: "Q1"),
        ModelPromptMessage(role: .assistant, text: "A1"),
        ModelPromptMessage(role: .user, text: "Q2"),
      ])

    let chat = try ModelRequestBuilder.build(
      prompt: prompt,
      configuration: ModelConfiguration(
        endpoint: "https://api.example.com/v1/x", format: .chatCompletions, model: "m"),
      apiKey: "sk-secret-1234")
    XCTAssertEqual(
      chat.body.compactText,
      #"{"model":"m","stream":true,"messages":[{"role":"system","content":"SYSTEM"},{"role":"user","content":"Q1"},{"role":"assistant","content":"A1"},{"role":"user","content":"Q2"}]}"#
    )

    let responses = try ModelRequestBuilder.build(
      prompt: prompt,
      configuration: ModelConfiguration(
        endpoint: "https://api.example.com/v1/x", format: .responses, model: "m"),
      apiKey: "sk-secret-1234")
    XCTAssertEqual(
      responses.body.compactText,
      #"{"model":"m","stream":true,"store":false,"instructions":"SYSTEM","input":[{"role":"user","content":"Q1"},{"role":"assistant","content":"A1"},{"role":"user","content":"Q2"}]}"#
    )

    let anthropic = try ModelRequestBuilder.build(
      prompt: prompt,
      configuration: ModelConfiguration(
        endpoint: "https://api.example.com/v1/x", format: .anthropicMessages, model: "m"),
      apiKey: "sk-secret-1234")
    XCTAssertEqual(
      anthropic.body.compactText,
      #"{"model":"m","max_tokens":8192,"stream":true,"system":"SYSTEM","messages":[{"role":"user","content":"Q1"},{"role":"assistant","content":"A1"},{"role":"user","content":"Q2"}]}"#
    )
  }

  func testAnOrdinaryRequestStillCarriesItsSingleMessage() throws {
    let prompt = ModelPrompt(
      systemMessage: "SYSTEM",
      userMessage: "hello",
      parameters: ModelTaskParameters(
        request: ProcessingRequest(
          text: "hello", mode: .translate, myLanguage: "简体中文", foreignLanguage: "English")))
    let request = try ModelRequestBuilder.build(
      prompt: prompt,
      configuration: ModelConfiguration(
        endpoint: "https://api.example.com/v1/x", format: .chatCompletions, model: "m"),
      apiKey: "sk-secret-1234")
    XCTAssertEqual(
      request.body.compactText,
      #"{"model":"m","stream":true,"messages":[{"role":"system","content":"SYSTEM"},{"role":"user","content":"hello"}]}"#
    )
  }

  // MARK: - Support

  private func makeModel(
    service: StubChatService,
    settings: @escaping @MainActor () -> CidaSettings = { CidaSettings() },
    saveNote: @escaping @MainActor (String) -> Void = { _ in }
  ) -> ChatModel {
    let model = ChatModel(service: service, settings: settings, saveNote: saveNote)
    model.refreshConfiguration()
    return model
  }

  private func waitUntil(
    timeout: Duration = .seconds(2),
    file: StaticString = #filePath,
    line: UInt = #line,
    _ condition: @MainActor () -> Bool
  ) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition() {
      if clock.now >= deadline {
        XCTFail("Timed out waiting for the chat", file: file, line: line)
        return
      }
      try await Task.sleep(for: .milliseconds(5))
    }
  }
}

/// The transcripts a conversation handed to the note store, in order.
@MainActor
private final class NoteRecorder {
  private(set) var transcripts: [String] = []

  func record(_ transcript: String) {
    transcripts.append(transcript)
  }
}

/// A chat service the test drives: every request is recorded, and each round answers with the
/// next group of chunks. `holds` keeps the stream open until `release()`, which is how a
/// streaming answer is stopped or left behind by a reset.
private final class StubChatService: ChatService, @unchecked Sendable {
  private let lock = NSLock()
  private var answers: [[String]]
  private var requests: [(systemPrompt: String, turns: [ModelPromptMessage])] = []
  private var pending: AsyncThrowingStream<String, Error>.Continuation?
  private let failure: Error?
  private let isReady: Bool
  private let holds: Bool

  init(answers: [[String]], failure: Error? = nil, isReady: Bool = true, holds: Bool = false) {
    self.answers = answers
    self.failure = failure
    self.isReady = isReady
    self.holds = holds
  }

  var recordedRequests: [(systemPrompt: String, turns: [ModelPromptMessage])] {
    lock.withLock { requests }
  }

  /// Lets a held stream finish, so whatever it does lands after the test's own step.
  func release() {
    lock.withLock { pending }?.finish()
  }

  func isConfigured(by settings: CidaSettings) -> Bool { isReady }

  func stream(
    systemPrompt: String, turns: [ModelPromptMessage], settings: CidaSettings
  ) -> AsyncThrowingStream<String, Error> {
    let chunks = lock.withLock { answers.isEmpty ? [] : answers.removeFirst() }
    lock.withLock { requests.append((systemPrompt, turns)) }
    return AsyncThrowingStream { continuation in
      lock.withLock { pending = continuation }
      let task = Task { [failure, holds] in
        for chunk in chunks {
          continuation.yield(chunk)
          try? await Task.sleep(for: .milliseconds(5))
        }
        if holds { return }
        if let failure {
          continuation.finish(throwing: failure)
        } else {
          continuation.finish()
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }
}

extension Error where Self == ModelServiceError {
  fileprivate static var http503: ModelServiceError {
    .http(status: 503, providerMessage: nil, body: "")
  }
}
