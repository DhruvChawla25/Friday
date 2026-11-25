// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import Foundation

/// Thin connector to the separate **Friday Online** app.
///
/// Friday Online is its own app and its own server, and the only part of
/// Friday's world that may use the network. Friday never links its code.
/// This file is all Friday has: it looks up Friday Online's XPC Mach
/// service, sends one MCP `tools/call` for `get_usage_limits`, and strictly
/// decodes the reply. It uses no networking API (XPC is local kernel IPC).
///
/// The wire contract (names, enums, JSON shape) mirrors Friday Online's
/// `FridayOnlineProtocol` at commit e7c404a0a86d15c6923285ccf819af900a17aa9a.
enum FridayOnline {
    static let machServiceName = "com.dhruvchawla.friday.online"
    /// Friday only talks to a server signed with this identifier.
    static let serverIdentifier = "com.dhruvchawla.friday.online"
    static let toolName = "get_usage_limits"
    static let protocolVersion = "2025-06-18"
    static let maxReplyBytes = 16 * 1024

    enum Provider: String, Codable, Sendable {
        case claude, antigravity, qoder
        case qwenCode = "qwen-code"
        case wisprFlow = "wispr-flow"
        case openCode = "opencode"
    }

    enum Status: String, Codable, Sendable {
        case ok, unsupported, unreachable
        case credentialsMissing = "credentials-missing"
        case credentialsExpired = "credentials-expired"
        case upstreamError = "upstream-error"
    }

    enum WindowKind: String, Codable, Sendable {
        case fiveHour = "5h"
        case weekly
        case weeklyOpus = "weekly-opus"
        case weeklySonnet = "weekly-sonnet"
    }

    struct Window: Codable, Equatable, Sendable {
        var window: WindowKind
        /// 0…100.
        var usedPercent: Double
        var resetsAt: Date?
    }

    struct Report: Codable, Equatable, Sendable {
        var provider: Provider
        var status: Status
        var windows: [Window] = []
        var fetchedAt: Date?
    }
}

/// The XPC interface Friday Online exports: one JSON-RPC message in, one out.
@objc protocol FridayOnlineXPCProtocol {
    func handle(_ message: Data, reply: @escaping @Sendable (Data?) -> Void)
}

/// What the Friday Online app said about one tool's limits.
enum OnlineLimits: Equatable, Sendable {
    /// The Friday Online app is not installed or not running.
    case notRunning
    /// It answered with something Friday could not use.
    case invalidReply
    case report(FridayOnline.Report)
}

/// Anything that can answer `get_usage_limits`. Tests use a fake.
protocol FridayOnlineConnecting: Sendable {
    func usageLimits(for provider: FridayOnline.Provider) async -> OnlineLimits
}

/// The real connector, over XPC.
final class FridayOnlineConnector: FridayOnlineConnecting, @unchecked Sendable {
    // @unchecked: the mutable state below is only touched under `lock`.
    private let connection: NSXPCConnection
    private let lock = NSLock()
    private var nextID = 0
    private var initialized = false

    init() {
        connection = NSXPCConnection(machServiceName: FridayOnline.machServiceName)
        connection.setCodeSigningRequirement("identifier \"\(FridayOnline.serverIdentifier)\"")
        connection.remoteObjectInterface = NSXPCInterface(with: FridayOnlineXPCProtocol.self)
        connection.resume()
    }

    deinit { connection.invalidate() }

    func usageLimits(for provider: FridayOnline.Provider) async -> OnlineLimits {
        if !lock.withLock({ initialized }) {
            let id = takeID()
            let hello: [String: Any] = [
                "jsonrpc": "2.0", "id": id, "method": "initialize",
                "params": [
                    "protocolVersion": FridayOnline.protocolVersion, "capabilities": [String: Any](),
                    "clientInfo": ["name": "friday", "version": "1"],
                ],
            ]
            guard let reply = await send(hello) else { return .notRunning }
            guard Self.rpcResult(reply, id: id) != nil else { return .invalidReply }
            lock.withLock { initialized = true }
        }
        let id = takeID()
        let call: [String: Any] = [
            "jsonrpc": "2.0", "id": id, "method": "tools/call",
            "params": ["name": FridayOnline.toolName, "arguments": ["provider": provider.rawValue]],
        ]
        guard let reply = await send(call) else { return .notRunning }
        guard let report = Self.report(fromReply: reply, id: id), report.provider == provider else {
            return .invalidReply
        }
        return .report(report)
    }

    private func takeID() -> Int {
        lock.withLock {
            nextID += 1
            return nextID
        }
    }

    private func send(_ message: [String: Any]) async -> Data? {
        guard let body = try? JSONSerialization.data(withJSONObject: message) else { return nil }
        let connection = connection
        let reply: Data? = await withCheckedContinuation { continuation in
            let once = ResumeOnce(continuation)
            let proxy = connection.remoteObjectProxyWithErrorHandler { _ in once.resume(nil) }
            guard let service = proxy as? FridayOnlineXPCProtocol else { return once.resume(nil) }
            service.handle(body) { once.resume($0) }
        }
        guard let reply, reply.count <= FridayOnline.maxReplyBytes else { return nil }
        return reply
    }

    // MARK: Decoding (static so tests can feed bytes directly)

    private struct Envelope<Result: Decodable>: Decodable {
        struct RPCError: Decodable { var code: Int }
        var jsonrpc: String
        var id: Int?
        var result: Result?
        var error: RPCError?
    }

    private struct Initialized: Decodable { var protocolVersion: String }

    private struct CallResult: Decodable {
        var structuredContent: FridayOnline.Report
        var isError: Bool
    }

    private static func rpcResult(_ data: Data, id: Int) -> Initialized? {
        guard let envelope = try? decoder.decode(Envelope<Initialized>.self, from: data),
            envelope.jsonrpc == "2.0", envelope.id == id, envelope.error == nil
        else { return nil }
        return envelope.result
    }

    /// The report in a `tools/call` reply, or nil if it is anything else.
    static func report(fromReply data: Data, id: Int) -> FridayOnline.Report? {
        guard let envelope = try? decoder.decode(Envelope<CallResult>.self, from: data),
            envelope.jsonrpc == "2.0", envelope.id == id, envelope.error == nil,
            let result = envelope.result, !result.isError
        else { return nil }
        return result.structuredContent
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// Resumes a continuation exactly once, whichever XPC callback fires first.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data?, Never>?

    init(_ continuation: CheckedContinuation<Data?, Never>) { self.continuation = continuation }

    func resume(_ value: Data?) {
        let pending = lock.withLock {
            defer { continuation = nil }
            return continuation
        }
        pending?.resume(returning: value)
    }
}
