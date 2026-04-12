import Dispatch
import Foundation
import Testing
@testable import OpenIslandCore

struct QwenHooksTests {
    @Test
    func qwenPayloadDecodesJSONObjectToolInputAndExtractsCommandPreview() throws {
        let data = Data(
            """
            {
              "cwd": "/tmp/worktree",
              "hook_event_name": "pre_tool_use",
              "session_id": "qwen-session-1",
              "tool_name": "Bash",
              "tool_input": {
                "command": "grep -i default_api:question README.md"
              }
            }
            """.utf8
        )

        let payload = try JSONDecoder().decode(QwenHookPayload.self, from: data)

        #expect(payload.toolInput == .object(["command": .string("grep -i default_api:question README.md")]))
        #expect(payload.effectiveToolInputPreview == "grep -i default_api:question README.md")
    }

    @Test
    func qwenPreToolUseUsesExtractedCommandPreviewInActivitySummary() async throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }

        let observer = LocalBridgeClient(socketURL: socketURL)
        let stream = try observer.connect()
        defer { observer.disconnect() }
        try await observer.send(.registerClient(role: .observer))

        let payload = QwenHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: "pre_tool_use",
            sessionID: "qwen-tool-preview",
            toolName: "Bash",
            toolInput: .object(["command": .string("grep -i default_api:question README.md")])
        )

        _ = try BridgeCommandClient(socketURL: socketURL).send(.processQwenHook(payload))

        var iterator = stream.makeAsyncIterator()
        let activityEvent = try await nextMatchingEvent(from: &iterator, maxEvents: 8) { event in
            if case .activityUpdated = event {
                return true
            }
            return false
        }

        if case let .activityUpdated(update) = activityEvent {
            #expect(update.summary == "Running Bash: grep -i default_api:question README.md")
        } else {
            Issue.record("Expected a Qwen activity update event")
        }
    }

    @Test
    func qwenPermissionRequestReturnsAllowDirectiveAfterApproval() async throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }

        let observer = LocalBridgeClient(socketURL: socketURL)
        let stream = try observer.connect()
        defer { observer.disconnect() }
        try await observer.send(.registerClient(role: .observer))

        let payload = QwenHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: "permission_request",
            sessionID: "qwen-permission-1",
            toolName: "Bash",
            toolInput: .object(["command": .string("ls -la")]),
            permissionTitle: "Allow Bash",
            permissionDescription: "Qwen needs approval to continue."
        )

        async let responseTask = sendOnGCDThread(.processQwenHook(payload), socketURL: socketURL)

        var iterator = stream.makeAsyncIterator()
        let permissionEvent = try await nextMatchingEvent(from: &iterator, maxEvents: 8) { event in
            if case .permissionRequested = event {
                return true
            }
            return false
        }

        if case let .permissionRequested(requested) = permissionEvent {
            #expect(requested.request.title == "Allow Bash")
            #expect(requested.request.affectedPath == "ls -la")
            #expect(requested.request.toolName == "Bash")
        } else {
            Issue.record("Expected a Qwen permission request event")
        }

        try await observer.send(.resolvePermission(sessionID: "qwen-permission-1", resolution: .allowOnce()))

        let response = try await responseTask
        #expect(response == .qwenHookDirective(.allow))
    }

    @Test
    func qwenQuestionAskedReturnsAnswerDirectiveAfterResponse() async throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }

        let observer = LocalBridgeClient(socketURL: socketURL)
        let stream = try observer.connect()
        defer { observer.disconnect() }
        try await observer.send(.registerClient(role: .observer))

        let payload = QwenHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: "question_asked",
            sessionID: "qwen-question-1",
            questionText: "Which environment?"
        )

        async let responseTask = sendOnGCDThread(.processQwenHook(payload), socketURL: socketURL)

        var iterator = stream.makeAsyncIterator()
        let questionEvent = try await nextMatchingEvent(from: &iterator, maxEvents: 8) { event in
            if case .questionAsked = event {
                return true
            }
            return false
        }

        if case let .questionAsked(question) = questionEvent {
            #expect(question.prompt.title == "Which environment?")
        } else {
            Issue.record("Expected a Qwen question event")
        }

        try await observer.send(
            .answerQuestion(
                sessionID: "qwen-question-1",
                response: QuestionPromptResponse(answer: "Production")
            )
        )

        let response = try await responseTask
        #expect(response == .qwenHookDirective(.answer(text: "Production")))
    }

    @Test
    func qwenHookOutputEncoderEncodesAnswerDirective() throws {
        let output = try QwenHookOutputEncoder.standardOutput(
            for: .qwenHookDirective(.answer(text: "Production"))
        )

        let payload = try #require(output)
        let object = try jsonObject(from: payload)

        #expect(object["type"] as? String == "answer")
        #expect(object["text"] as? String == "Production")
    }
}

private enum QwenHooksTestError: Error {
    case streamEnded
    case noMatchingEvent
}

private func nextEvent(
    from iterator: inout AsyncThrowingStream<AgentEvent, Error>.AsyncIterator
) async throws -> AgentEvent {
    guard let event = try await iterator.next() else {
        throw QwenHooksTestError.streamEnded
    }

    return event
}

private func nextMatchingEvent(
    from iterator: inout AsyncThrowingStream<AgentEvent, Error>.AsyncIterator,
    maxEvents: Int,
    predicate: (AgentEvent) -> Bool
) async throws -> AgentEvent {
    for _ in 0..<maxEvents {
        let event = try await nextEvent(from: &iterator)
        if predicate(event) {
            return event
        }
    }

    throw QwenHooksTestError.noMatchingEvent
}

private func jsonObject(from data: Data) throws -> [String: Any] {
    let object = try JSONSerialization.jsonObject(with: data)
    return object as? [String: Any] ?? [:]
}

private func sendOnGCDThread(
    _ command: BridgeCommand,
    socketURL: URL
) async throws -> BridgeResponse? {
    try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global().async {
            do {
                let response = try BridgeCommandClient(socketURL: socketURL).send(command)
                continuation.resume(returning: response)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
