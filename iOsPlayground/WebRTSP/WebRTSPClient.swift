import Foundation
import os


extension WebRTSPClient.Error: LocalizedError {
    public var errorDescription: String? {
        switch(self) {
        default:
            return "\(String(describing: self))"
        }
    }
}

@WebRTSPActor
class WebRTSPClient {
    enum Error: Swift.Error {
        case NotConnected
        case AlreadyConnected
        case UnsupportedMessageType
        case ResponseForUnknownRequest
        case RequestNotHandled
        case OptionsHeaderFieldIsMissing
        case SessionHeaderFieldIsMissing
        case AlreadyHasSession
        case MissingSession
        case RequestFailed(with: StatusCode, reason: String)
    }

    private class Delegate: NSObject, URLSessionWebSocketDelegate {
        weak var owner: WebRTSPClient? = nil

        func urlSession(
            _ session: URLSession,
            webSocketTask: URLSessionWebSocketTask,
            didOpenWithProtocol protocol: String?
        ) {
            Task { @WebRTSPActor in
                guard let owner = self.owner else { return }
                guard owner.webSocketTask == webSocketTask else { return }

                owner.onConnected()
            }
        }

        func urlSession(
            _ session: URLSession,
            webSocketTask: URLSessionWebSocketTask,
            didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
            reason: Data?
        ) {
            Task { @WebRTSPActor in
                guard let owner = self.owner else { return }
                guard owner.webSocketTask == webSocketTask else { return }

                owner.onDisconnected(didCloseWith: closeCode, reason: reason)
            }
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            didCompleteWithError error: Swift.Error?
        ) {
            Task { @WebRTSPActor in
                guard let owner = self.owner else { return }
                guard owner.webSocketTask == task else { return }

                owner.onDisconnected(error: error)
            }
        }
    }

    private typealias WebSocketMessage = URLSessionWebSocketTask.Message

    private struct OutRequest {
        typealias Continuation = CheckedContinuation<Response, Swift.Error>

        let request: Request
        let continuation: Continuation
    }


    private let log = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "WebRTSPClient")
    private let delegate = Delegate()
    private let urlSession: URLSession
    private var webSocketTask: URLSessionWebSocketTask? = nil
    private var connectContinuation: CheckedContinuation<Void, Swift.Error>? = nil
    private var disconnectContinuation: CheckedContinuation<Void, Never>? = nil

    private var requestHandler: (_ request: Request) async throws -> Void = { _ in throw Error.RequestNotHandled }

    private var receiveLoopTask: Task<Void, Never>? = nil

    private var lastCSeq: CSeq = 0
    private var sentRequests: [CSeq: OutRequest] = [:]

    private(set) var availableMethods = Set<Method>()
    private(set) var mediaSession: String? = nil


    init() {
        self.urlSession = URLSession(configuration: .default, delegate: self.delegate, delegateQueue: nil)

        self.delegate.owner = self
    }

    func nextCSeq() -> CSeq {
        repeat {
            self.lastCSeq = self.lastCSeq &+ 1
        } while(sentRequests[self.lastCSeq] != nil)

        return self.lastCSeq
    }

    private func runReceiveLoop() {
        assert(self.receiveLoopTask == nil)
        guard self.receiveLoopTask == nil else { return }

        assert(self.webSocketTask != nil)
        guard let webSocketTask = self.webSocketTask else {
            return
        }

        self.receiveLoopTask = Task { [webSocketTask] in
            do {
                while(webSocketTask == self.webSocketTask) {
                    try Task.checkCancellation()
                    try await onMessage(try await webSocketTask.receive())
                }
            } catch {
                switch(error) {
                case is CancellationError:
                    self.log.debug("Receive loop cancelled.")
                    break
                case is Error:
                    self.log.error("Message handling failed with: \(error.localizedDescription)\nCancelling connection...")
                    webSocketTask.cancel()
                default:
                    self.log.error("Receive failed with: \(error.localizedDescription)")
                }
            }

            self.receiveLoopTask = nil
        }
    }

    private func onConnected() {
        self.connectContinuation?.resume()
        self.connectContinuation = nil

        self.log.info("Connected")

        runReceiveLoop()
    }

    private func onDisconnected(
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        onDisconnected()
    }

    private func onDisconnected(error: Swift.Error?) {
        self.connectContinuation?.resume(throwing: error ?? Error.NotConnected)
        self.connectContinuation = nil

        onDisconnected()
    }

    private func onDisconnected() {
        assert(self.connectContinuation == nil)

        self.webSocketTask = nil

        self.receiveLoopTask?.cancel()
        self.receiveLoopTask = nil

        self.sentRequests.forEach { (cSeq, request) in
            request.continuation.resume(throwing: Error.NotConnected)
        }
        self.sentRequests.removeAll()

        if let disconnectContinuation = self.disconnectContinuation {
            disconnectContinuation.resume()
        }

        self.log.info("Disconnected")
    }

    private func onMessage(_ webSocketMessage: WebSocketMessage) async throws {
        guard case let .string(message) = webSocketMessage else {
            throw Error.UnsupportedMessageType
        }

        self.log.trace("<- \n\(message)")

        try await onMessage(message)
    }

    private func onMessage(_ message: String) async throws {
        if(try Request.isRequest(message)) {
            try await onRequest(try Request.parse(message))
        } else {
            try onResponse(try Response.parse(message))
        }
    }

    private func onRequest(_ request: Request) async throws {
        try await self.requestHandler(request)
    }

    private func onResponse(_ response: Response) throws {
        guard let request = self.sentRequests[response.cSeq] else {
            throw Error.ResponseForUnknownRequest
        }

        defer {
            self.sentRequests.removeValue(forKey: response.cSeq)
        }

        if(response.statusCode == KnownStatus.Ok.rawValue) {
            request.continuation.resume(returning: response)
        } else {
            request.continuation.resume(
                throwing: Error.RequestFailed(
                    with: response.statusCode,
                    reason: response.reasonPhrase))
        }
    }

    private func sendRequest(_ request: Request, continuation: OutRequest.Continuation) {
        Task {
            let cSeq = nextCSeq()
            self.sentRequests[cSeq] = OutRequest(request: request, continuation: continuation)
            let requestMessage = request.serialize(cSeq: cSeq)

            do {
                self.log.trace("->\n\(requestMessage)")
                try await self.webSocketTask?.send(.string(requestMessage))
            } catch {
                self.sentRequests.removeValue(forKey: cSeq)
                continuation.resume(throwing: error)
            }
        }
    }
    private func sendRequest(_ request: Request) async throws -> Response {
        guard self.webSocketTask != nil else { throw Error.NotConnected }
        guard self.connectContinuation == nil else { throw Error.NotConnected }

        let response = try await withCheckedThrowingContinuation { (continuation: OutRequest.Continuation) -> Void in
            sendRequest(request, continuation: continuation)
        }
        return response
    }
}

extension WebRTSPClient {
    func connect(url: URL) async throws {
        guard self.webSocketTask == nil else { throw Error.AlreadyConnected }

        self.log.info("Connecting to \"\(url.absoluteString)\"...")

        var request = URLRequest(url: url)
        request.setValue("webrtsp", forHTTPHeaderField: "Sec-WebSocket-Protocol")
        let webSocketTask = self.urlSession.webSocketTask(with: request)
        self.webSocketTask = webSocketTask
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Swift.Error>) -> Void in
            self.connectContinuation = continuation
            webSocketTask.resume()
        }
    }
    func disconnect() async {
        guard let webSocketTask = self.webSocketTask else { return }
        guard self.disconnectContinuation == nil else { return }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) -> Void in
            self.disconnectContinuation = continuation

            webSocketTask.cancel(with: .normalClosure, reason: nil)
        }
    }

    func onRequest(_ requestHandler: @escaping (_ request: Request) async throws -> Void) {
        self.requestHandler = requestHandler
    }

    func requestOptions() async throws -> Set<Method> {
        guard self.webSocketTask != nil else { throw Error.NotConnected }

        let request = Request(method: .OPTIONS, uri: "*", protocolName: .Current, body: String())
        let response = try await sendRequest(request)

        guard let optionsString = response.getHeaderField("Public") else { throw Error.OptionsHeaderFieldIsMissing }

        let options = try WebRTSPParser.ParseOptions(optionsString)

        self.availableMethods = options

        return options
    }

    func requestDescribe(uri: String = "*") async throws -> String {
        guard self.webSocketTask != nil else { throw Error.NotConnected }
        guard self.mediaSession == nil else { throw Error.AlreadyHasSession }

        let request = Request(method: .DESCRIBE, uri: uri, protocolName: .Current)
        let response = try await sendRequest(request)

        guard let mediaSession = response.mediaSession else { throw Error.SessionHeaderFieldIsMissing }

        self.mediaSession = mediaSession

        return response.body
    }


    func requestSetup(mLineIndex: UInt, candidate: String) async throws {
        guard self.webSocketTask != nil else { throw Error.NotConnected }
        guard let mediaSession = self.mediaSession else { throw Error.MissingSession }

        let body = "\(mLineIndex)/\(candidate)\r\n"

        let request =
            Request(
                method: .SETUP,
                uri: "*",
                protocolName: .Current,
                mediaSession: mediaSession,
                body: body)
        request.setContentType("application/x-ice-candidate")

        let _ = try await sendRequest(request)
    }

    func requestPlay(with sessionDescription: String) async throws {
        guard self.webSocketTask != nil else { throw Error.NotConnected }
        guard let mediaSession = self.mediaSession else { throw Error.MissingSession }

        let request =
            Request(
                method: .PLAY,
                uri: "*",
                protocolName: .Current,
                mediaSession: mediaSession,
                body: sessionDescription)
        request.setContentType("application/sdp")

        let _ = try await sendRequest(request)
    }

    func requestTeardown() async throws {
        guard self.webSocketTask != nil else { throw Error.NotConnected }
        guard let mediaSession = self.mediaSession else { throw Error.MissingSession }

        defer {
            self.mediaSession = nil
        }

        let request =
            Request(
                method: .TEARDOWN,
                uri: "*",
                protocolName: .Current,
                mediaSession: mediaSession)
        let _ = try await sendRequest(request)
    }
}
