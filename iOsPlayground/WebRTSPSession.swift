import Foundation
import WebRTC


private let WebRTSPServer = URL(string: "ws://rpi:5554")!

@WebRTSPActor
class WebRTSPSession {
    private var client: WebRTSPClient
    private(set) var localPeer: GoogleWebRTCPeer? = nil

    init() {
        self.client = WebRTSPClient()
        self.localPeer = GoogleWebRTCPeer(iceServers: [])
    }

    private func onSetupRequest(_ request: Request) async {
        guard let localPeer = self.localPeer else { return }

        guard request.method == .SETUP else { return }

        guard request.contentType == "application/x-ice-candidate" else {
            print("Invalid contentType in .SETUP request: \"\(request.contentType ?? String())\"")
            return
        }

        do {
            let iceCandidates = try WebRTSPParser.ParseIceCandidates(request.body)
            for (mLineIndex, candidate) in iceCandidates {
                try await localPeer.addIceCandidate(mLineIndex: mLineIndex, candidate: candidate)
            }
        } catch {
            print(".SETUP request handling failed: \(error.localizedDescription)")
        }
    }

    private func onRequest(_ request: Request) async {
        guard self.localPeer != nil else { return }

        switch(request.method) {
        case .SETUP:
            await onSetupRequest(request)
            break
        default:
            print("Unsupported request: \(request.method)")
            break
        }
    }

    private func onIceCandidate(_ mLineIndex: UInt, _ candidate: String) async {
        do {
            try await client.requestSetup(mLineIndex: mLineIndex, candidate: candidate)
        } catch {
            print("Request .SETUP failed with: \(error.localizedDescription)")
        }
    }
}


extension WebRTSPSession {
    func connect() async throws {
        guard let localPeer = self.localPeer else { return }

        var success = false
        defer {
            if(!success) {
                disconnect()
            }
        }

        self.client.onRequest { [weak self] request in
            guard let self = self else { return }

            await self.onRequest(request)
        }

        localPeer.onIceCandidate { [weak self] mLineIndex, candidate in
            guard let self = self else { return }

            await self.onIceCandidate(mLineIndex, candidate)
        }

        try await self.client.connect(url: WebRTSPServer)

        let remoteSessionDescription = try await self.client.requestDescribe()
        try await localPeer.setRemoteSessionDescription(remoteSessionDescription)

        let localSessionDescription = try await localPeer.getLocalSessionDescription()
        try await self.client.requestPlay(with: localSessionDescription)

        success = true
    }

    func disconnect() {
        Task {
            self.localPeer?.close()
            await self.client.disconnect()
        }
    }
}
