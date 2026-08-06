/*
 Copyright 2024 The Fuel Rats Mischief

 Redistribution and use in source and binary forms, with or without modification,
 are permitted provided that the following conditions are met:

 1. Redistributions of source code must retain the above copyright notice,
 this list of conditions and the following disclaimer.

 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following
 disclaimer in the documentation and/or other materials provided with the distribution.

 3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote
 products derived from this software without specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES,
 INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

import Foundation
import Logging
import NIO

/// Sends already-encoded GELF datagrams to a Graylog GELF UDP input over a single,
/// long-lived NIO datagram channel. Sends are fire-and-forget: a dropped datagram must
/// never block or crash the caller (this is a log sink, not a delivery guarantee).
final class GelfLogBroadcaster: @unchecked Sendable {
    private let channel: Channel
    private let remoteAddress: SocketAddress

    init(host: String, port: Int, group: EventLoopGroup) throws {
        self.remoteAddress = try SocketAddress.makeAddressResolvingHost(host, port: port)
        self.channel = try DatagramBootstrap(group: group)
            .bind(host: "0.0.0.0", port: 0)
            .wait()
    }

    /// Writes each datagram to the socket. `Channel.writeAndFlush` is thread-safe and hops
    /// to the event loop itself, so this is safe to call from any logging thread.
    func send(_ datagrams: [[UInt8]]) {
        for bytes in datagrams {
            var buffer = channel.allocator.buffer(capacity: bytes.count)
            buffer.writeBytes(bytes)
            let envelope = AddressedEnvelope(remoteAddress: remoteAddress, data: buffer)
            channel.writeAndFlush(envelope, promise: nil)
        }
    }
}

/// Builds GELF 1.1 payloads and splits them into UDP datagrams, chunking per the GELF
/// spec when a payload is too large for a single datagram.
struct GelfEncoder: Sendable {
    /// The `host` field of every message — the source the logs are attributed to in Graylog.
    let source: String
    /// Emitted as the `_facility` additional field.
    let facility: String

    /// Payloads up to this size are sent as a single datagram; larger ones are chunked.
    private static let maxUnchunkedBytes = 8192
    /// GELF chunked messages are limited to 128 chunks; beyond that the message is truncated.
    private static let maxChunks = 128

    func datagrams(
        level: Logger.Level, message: String, metadata: Logger.Metadata, loggerLabel: String,
        source callSource: String, file: String, function: String, line: UInt
    ) -> [[UInt8]] {
        var fields: [String: Any] = [
            "version": "1.1",
            "host": source,
            "short_message": message.isEmpty ? "(empty message)" : message,
            "timestamp": Date().timeIntervalSince1970,
            "level": Self.syslogLevel(level),
            "_facility": facility,
            "_logger": loggerLabel,
            "_source": callSource,
            "_file": file,
            "_function": function,
            "_line": Int(line)
        ]

        for (key, value) in metadata {
            // GELF additional fields must be a string or number and are prefixed with `_`.
            fields["_" + Self.sanitizeFieldName(key)] = Self.stringify(value)
        }

        guard let payload = try? JSONSerialization.data(withJSONObject: fields, options: []) else {
            return []
        }

        return Self.chunk(Array(payload))
    }

    /// Maps a swift-log level onto the syslog severity GELF expects (0 highest, 7 lowest).
    static func syslogLevel(_ level: Logger.Level) -> Int {
        switch level {
            case .trace, .debug: return 7
            case .info: return 6
            case .notice: return 5
            case .warning: return 4
            case .error: return 3
            case .critical: return 2
        }
    }

    /// Renders a metadata value as a string, since GELF additional fields cannot be arrays
    /// or nested objects.
    static func stringify(_ value: Logger.MetadataValue) -> String {
        switch value {
            case .string(let string): return string
            case .stringConvertible(let convertible): return convertible.description
            case .array, .dictionary: return "\(value)"
        }
    }

    /// GELF additional field names allow `[A-Za-z0-9_.-]`; anything else is replaced. `_id`
    /// is reserved by Graylog, so a bare `id` key is renamed to avoid producing it.
    static func sanitizeFieldName(_ key: String) -> String {
        var sanitized = String(
            key.map { character in
                if character.isLetter || character.isNumber || character == "." || character == "-"
                    || character == "_" {
                    return character
                }
                return "_"
            })
        if sanitized == "id" {
            sanitized = "id_"
        }
        return sanitized
    }

    /// Splits a payload into one or more UDP datagrams. Payloads that fit are returned as-is;
    /// larger payloads are wrapped in GELF chunked datagrams (magic `0x1e 0x0f`, 8-byte
    /// message id, sequence, total, then the slice).
    static func chunk(_ payload: [UInt8]) -> [[UInt8]] {
        if payload.count <= maxUnchunkedBytes {
            return [payload]
        }

        var body = payload
        let neededChunks = (body.count + maxUnchunkedBytes - 1) / maxUnchunkedBytes
        if neededChunks > maxChunks {
            // Too large to represent; keep the head so at least the message is searchable.
            body = Array(body.prefix(maxUnchunkedBytes * maxChunks))
        }

        let total = UInt8((body.count + maxUnchunkedBytes - 1) / maxUnchunkedBytes)
        let messageId = (0..<8).map { _ in UInt8.random(in: UInt8.min...UInt8.max) }

        var datagrams: [[UInt8]] = []
        var sequence: UInt8 = 0
        var index = body.startIndex
        while index < body.endIndex {
            let end = body.index(index, offsetBy: maxUnchunkedBytes, limitedBy: body.endIndex)
                ?? body.endIndex
            var datagram: [UInt8] = [0x1e, 0x0f]
            datagram.append(contentsOf: messageId)
            datagram.append(sequence)
            datagram.append(total)
            datagram.append(contentsOf: body[index..<end])
            datagrams.append(datagram)
            sequence += 1
            index = end
        }
        return datagrams
    }
}

/// A swift-log `LogHandler` that ships records to Graylog as GELF over UDP, alongside
/// whatever other handlers are installed (see `GelfLogging.bootstrap`).
struct GelfLogHandler: LogHandler {
    let label: String
    private let broadcaster: GelfLogBroadcaster
    private let encoder: GelfEncoder

    var metadata: Logger.Metadata = [:]
    var logLevel: Logger.Level = .info

    init(label: String, broadcaster: GelfLogBroadcaster, encoder: GelfEncoder) {
        self.label = label
        self.broadcaster = broadcaster
        self.encoder = encoder
    }

    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    func log(event: LogEvent) {
        var merged = self.metadata
        if let explicit = event.metadata {
            merged.merge(explicit) { _, new in new }
        }
        if let error = event.error {
            merged["error"] = .string("\(error)")
        }
        let datagrams = encoder.datagrams(
            level: event.level, message: event.message.description, metadata: merged,
            loggerLabel: label, source: event.source, file: event.file,
            function: event.function, line: event.line)
        broadcaster.send(datagrams)
    }
}

/// Installs the process-wide logging backend. Called once, before any `Logger` is created.
enum GelfLogging {
    /// Bootstraps swift-log. When `GRAYLOG_HOST` is set, logs go to both stdout and a
    /// Graylog GELF UDP input; otherwise stdout only. Failure to reach Graylog degrades to
    /// stdout rather than preventing start-up.
    static func bootstrap() {
        guard let host = env("GRAYLOG_HOST") else {
            LoggingSystem.bootstrap(StreamLogHandler.standardOutput)
            return
        }

        let port = Int(env("GRAYLOG_PORT") ?? "12201") ?? 12201
        let facility = env("GRAYLOG_FACILITY") ?? "mechasqueak"
        let source = env("GRAYLOG_SOURCE") ?? ProcessInfo.processInfo.hostName

        do {
            let broadcaster = try GelfLogBroadcaster(
                host: host, port: port, group: MultiThreadedEventLoopGroup.singleton)
            let encoder = GelfEncoder(source: source, facility: facility)
            LoggingSystem.bootstrap { label in
                MultiplexLogHandler([
                    StreamLogHandler.standardOutput(label: label),
                    GelfLogHandler(label: label, broadcaster: broadcaster, encoder: encoder)
                ])
            }
        } catch {
            FileHandle.standardError.write(
                Data("Failed to initialise Graylog logging, using stdout only: \(error)\n".utf8))
            LoggingSystem.bootstrap(StreamLogHandler.standardOutput)
        }
    }
}
