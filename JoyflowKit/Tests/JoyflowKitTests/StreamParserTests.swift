import Foundation
import Testing

@testable import JoyflowKit

struct StreamParserTests {
    @Test func concatenatesContentDeltas() {
        var parser = StreamParser()
        var buffer = """
            data: {"choices":[{"delta":{"content":"Hel"}}]}

            data: {"choices":[{"delta":{"content":"lo"}}]}

            data: {"choices":[{"delta":{"content":"!"}}]}

            data: [DONE]

            """
        let events = parser.parse(buffer: &buffer)
        let text = events.compactMap { if case .text(let value) = $0 { return value } else { return nil } }.joined()
        #expect(text == "Hello!")
        #expect(events.contains(.finished))
    }

    @Test func parsesToolCallFragments() {
        var parser = StreamParser()
        let first = parser.parseLine(
            #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"c1","function":{"name":"run_shell","arguments":"{\"c"}}]}}]}"#
        )
        let second = parser.parseLine(
            #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"md\":\"ls\"}"}}]}}]}"#
        )
        #expect(first.contains { if case .toolCall(let d) = $0 { return d.name == "run_shell" && d.id == "c1" } else { return false } })
        #expect(second.contains { if case .toolCall(let d) = $0 { return d.argumentsFragment.contains("md") } else { return false } })
    }

    @Test func doneLineFinishes() {
        var parser = StreamParser()
        #expect(parser.parseLine("data: [DONE]") == [.finished])
    }

    @Test func httpErrorExtractsMessage() {
        let event = StreamParser().parseHTTPError(status: 404, body: #"{"error":{"message":"unknown model"}}"#)
        #expect(event == .error("HTTP 404: unknown model"))
    }

    @Test func streamsReasoningDeltas() {
        var parser = StreamParser()
        let events = parser.parseLine(
            #"data: {"choices":[{"delta":{"reasoning":"Checking the project."}}]}"#
        )
        #expect(events == [.reasoning("Checking the project.")])
        let alt = parser.parseLine(
            #"data: {"choices":[{"delta":{"reasoning_content":" Still here."}}]}"#
        )
        #expect(alt == [.reasoning(" Still here.")])
    }

    @Test func splitsThinkTagsIntoReasoning() {
        var parser = StreamParser()
        let first = parser.parseLine(#"data: {"choices":[{"delta":{"content":"Hi <think>plan"}}]}"#)
        let second = parser.parseLine(#"data: {"choices":[{"delta":{"content":" step</think>Done"}}]}"#)
        #expect(first == [.text("Hi "), .reasoning("plan")])
        #expect(second == [.reasoning(" step"), .text("Done")])
    }

    @Test func toolCallsFinishReasonCompletes() {
        var parser = StreamParser()
        let events = parser.parseLine(
            #"data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}"#
        )
        #expect(events == [.finished])
    }

    @Test func reasoningDetailsDoNotDuplicateVisibleText() {
        var parser = StreamParser()
        let events = parser.parseLine(
            #"data: {"choices":[{"delta":{"reasoning":"The","reasoning_details":[{"type":"reasoning.summary","summary":"The","format":"xai-responses-v1","index":0}]}}]}"#
        )
        let visible = events.compactMap { if case .reasoning(let text) = $0 { return text } else { return nil } }
        #expect(visible == ["The"])
        #expect(
            events.contains {
                if case .reasoningDetail(let detail) = $0 {
                    return detail.summary == "The" && detail.format == "xai-responses-v1"
                }
                return false
            }
        )
    }

    @Test func reasoningDetailsAloneBecomeVisibleThought() {
        var parser = StreamParser()
        let events = parser.parseLine(
            #"data: {"choices":[{"delta":{"reasoning_details":[{"type":"reasoning.summary","summary":"Hello","format":"xai-responses-v1","index":0}]}}]}"#
        )
        #expect(events.contains(.reasoning("Hello")))
    }

    @Test func lengthFinishReasonCompletes() {
        var parser = StreamParser()
        #expect(
            parser.parseLine(#"data: {"choices":[{"delta":{},"finish_reason":"length"}]}"#)
                == [.finished]
        )
    }

    @Test func flushParsesTrailingLineWithoutNewline() {
        var parser = StreamParser()
        var buffer = #"data: {"choices":[{"delta":{"content":"Hi"}}]}"#
        #expect(parser.parse(buffer: &buffer).isEmpty)
        let events = parser.finish(buffer: &buffer)
        #expect(events == [.text("Hi")])
        #expect(buffer.isEmpty)
    }
}
