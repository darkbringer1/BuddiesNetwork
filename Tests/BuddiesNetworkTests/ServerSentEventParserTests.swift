import XCTest
@testable import BuddiesNetwork

final class ServerSentEventParserTests: XCTestCase {
    func testParserBuildsEventsFromFieldsAndDataLines() throws {
        let parser = ServerSentEventParser()
        let payload = """
        : keep-alive
        id: 42
        event: greeting
        retry: 1500
        data: hello
        data: world

        data: next
        """
        + "\n\n"

        let events = try parser.parse(Data(payload.utf8))

        XCTAssertEqual(
            events,
            [
                ServerSentEvent(
                    id: "42",
                    event: "greeting",
                    data: "hello\nworld",
                    retry: 1500
                ),
                ServerSentEvent(
                    id: "42",
                    data: "next"
                )
            ]
        )
    }

    func testParserHandlesChunksSplitInsideUTF8Scalar() throws {
        let parser = ServerSentEventParser()
        let bytes = Array("data: café\n\n".utf8)
        let splitIndex = try XCTUnwrap(bytes.firstIndex(of: 0xC3)).advanced(by: 1)

        let firstEvents = try parser.parse(Data(bytes[..<splitIndex]))
        let secondEvents = try parser.parse(Data(bytes[splitIndex...]))

        XCTAssertEqual(firstEvents, [])
        XCTAssertEqual(secondEvents, [ServerSentEvent(data: "café")])
    }

    func testFinishFlushesPendingEvent() throws {
        let parser = ServerSentEventParser()

        XCTAssertEqual(
            try parser.parse(Data("data: unfinished".utf8)),
            []
        )
        XCTAssertEqual(
            try parser.finish(),
            [ServerSentEvent(data: "unfinished")]
        )
    }

    func testParserRejectsInvalidUTF8Line() {
        let parser = ServerSentEventParser()
        let invalidPayload = Data([0x64, 0x61, 0x74, 0x61, 0x3A, 0x20, 0xFF, 0x0A])

        XCTAssertThrowsError(try parser.parse(invalidPayload)) { error in
            XCTAssertEqual(error as? ServerSentEventsError, .invalidUTF8)
        }
    }
}
