import Foundation
import Synchronization

public final class ServerSentEventParser: Sendable {
    private enum Byte {
        static let carriageReturn: UInt8 = 0x0D
        static let lineFeed: UInt8 = 0x0A
        static let space: UInt8 = 0x20
        static let zero: UInt8 = 0x30
        static let nine: UInt8 = 0x39
    }

    private struct State {
        var pendingLineBytes: [UInt8] = []
        var sawCarriageReturn = false
        var dataLines: [String] = []
        var event: String?
        var lastEventID: String?
        var retry: Int?
    }

    private let state = Mutex(State())

    public init() {}

    public func parse(_ data: Data) throws -> [ServerSentEvent] {
        try state.withLock { state in
            var events: [ServerSentEvent] = []

            for byte in data {
                try Self.process(byte, state: &state, events: &events)
            }

            return events
        }
    }

    public func finish() throws -> [ServerSentEvent] {
        try state.withLock { state in
            var events: [ServerSentEvent] = []

            if state.sawCarriageReturn {
                state.sawCarriageReturn = false
                try Self.emitLine(state: &state, events: &events)
            }

            if !state.pendingLineBytes.isEmpty {
                try Self.emitLine(state: &state, events: &events)
            }

            if let event = Self.dispatchEvent(state: &state) {
                events.append(event)
            }

            return events
        }
    }

    private static func process(
        _ byte: UInt8,
        state: inout State,
        events: inout [ServerSentEvent]
    ) throws {
        if state.sawCarriageReturn {
            state.sawCarriageReturn = false
            try emitLine(state: &state, events: &events)

            if byte == Byte.lineFeed {
                return
            }
        }

        switch byte {
        case Byte.carriageReturn:
            state.sawCarriageReturn = true
        case Byte.lineFeed:
            try emitLine(state: &state, events: &events)
        default:
            state.pendingLineBytes.append(byte)
        }
    }

    private static func emitLine(
        state: inout State,
        events: inout [ServerSentEvent]
    ) throws {
        let lineBytes = state.pendingLineBytes
        state.pendingLineBytes.removeAll(keepingCapacity: true)

        guard let line = String(bytes: lineBytes, encoding: .utf8) else {
            throw ServerSentEventsError.invalidUTF8
        }

        if let event = process(line: line, state: &state) {
            events.append(event)
        }
    }

    private static func process(
        line: String,
        state: inout State
    ) -> ServerSentEvent? {
        guard !line.isEmpty else {
            return dispatchEvent(state: &state)
        }

        guard !line.hasPrefix(":") else {
            return nil
        }

        let field: String
        var value: Substring

        if let separatorIndex = line.firstIndex(of: ":") {
            field = String(line[..<separatorIndex])
            value = line[line.index(after: separatorIndex)...]

            if value.utf8.first == Byte.space {
                value = value.dropFirst()
            }
        } else {
            field = line
            value = ""
        }

        let fieldValue = String(value)

        switch field {
        case "data":
            state.dataLines.append(fieldValue)
        case "event":
            state.event = fieldValue
        case "id":
            if !fieldValue.unicodeScalars.contains(where: { $0.value == 0 }) {
                state.lastEventID = fieldValue
            }
        case "retry":
            if let retry = retryValue(from: fieldValue) {
                state.retry = retry
            }
        default:
            break
        }

        return nil
    }

    private static func dispatchEvent(state: inout State) -> ServerSentEvent? {
        defer {
            state.dataLines.removeAll(keepingCapacity: true)
            state.event = nil
            state.retry = nil
        }

        guard !state.dataLines.isEmpty else {
            return nil
        }

        return ServerSentEvent(
            id: state.lastEventID,
            event: state.event,
            data: state.dataLines.joined(separator: "\n"),
            retry: state.retry
        )
    }

    private static func retryValue(from value: String) -> Int? {
        guard !value.isEmpty else {
            return nil
        }

        guard value.utf8.allSatisfy({ (Byte.zero ... Byte.nine).contains($0) }) else {
            return nil
        }

        return Int(value)
    }
}
