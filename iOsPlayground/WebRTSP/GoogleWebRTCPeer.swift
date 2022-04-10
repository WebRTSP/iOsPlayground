import os
import WebRTC


extension RTCPeerConnectionState: CustomStringConvertible {
    public var description: String {
        switch(self) {
        case .new: return "new"
        case .connecting: return "connecting"
        case .connected: return "connected"
        case .disconnected: return "disconnected"
        case .failed: return "failed"
        case .closed: return "closed"
        @unknown default: return "unknown"
        }
    }
}
extension RTCSignalingState: CustomStringConvertible {
    public var description: String {
        switch(self) {
        case .stable: return "stable"
        case .haveLocalOffer: return "haveLocalOffer"
        case .haveLocalPrAnswer: return "haveLocalPrAnswer"
        case .haveRemoteOffer: return "haveRemoteOffer"
        case .haveRemotePrAnswer: return "haveRemotePrAnswer"
        case .closed: return "closed"
        @unknown default: return "unknown"
        }
    }
}
extension RTCIceConnectionState: CustomStringConvertible {
    public var description: String {
        switch(self) {
        case .new: return "new"
        case .checking: return "checking"
        case .connected: return "connected"
        case .completed: return "completed"
        case .failed: return "failed"
        case .disconnected: return "disconnected"
        case .closed: return "closed"
        case .count: return "count"
        @unknown default: return "unknown"
        }
    }
}
extension RTCIceGatheringState: CustomStringConvertible {
    public var description: String {
        switch(self) {
        case .new: return "new"
        case .gathering: return "gathering"
        case .complete: return "complete"
        @unknown default: return "unknown"
        }
    }
}

extension GoogleWebRTCPeer.Error: LocalizedError {
    public var errorDescription: String? {
        switch(self) {
        default:
            return "\(String(describing: self))"
        }
    }
}

@WebRTSPActor
class GoogleWebRTCPeer: WebRTCPeer {
    enum Error: Swift.Error {
    }

    private class Delegate: NSObject, RTCPeerConnectionDelegate {
        weak var owner: GoogleWebRTCPeer? = nil

        func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
            GoogleWebRTCPeer.log.debug("Peer state changed to \"\(newState)\"")
        }

        func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
            GoogleWebRTCPeer.log.debug("Signaling state changed to \"\(stateChanged)\"")
        }

        func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        }

        func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        }

        func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        }

        func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
            GoogleWebRTCPeer.log.debug("Ice connection state changed to \"\(newState)\"")
        }

        func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
            GoogleWebRTCPeer.log.debug("Ice gathering state changed to \"\(newState)\"")
        }

        func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
            Task { @WebRTSPActor in
                await self.owner?.onIceCandidate(candidate)
            }
        }

        func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        }

        func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        }

        func peerConnection(
            _ peerConnection: RTCPeerConnection,
            didAdd rtpReceiver: RTCRtpReceiver,
            streams mediaStreams: [RTCMediaStream]
        ) {
            guard let owner = self.owner else { return }
            guard let track = rtpReceiver.track else { return }
            guard track.kind == kRTCMediaStreamTrackKindVideo else { return }
            guard let track = track as? RTCVideoTrack else { return }

            Task { @WebRTSPActor in
                owner.remoteVideoTrack = track
            }
        }
        func peerConnection(
            _ peerConnection: RTCPeerConnection,
            didRemove rtpReceiver: RTCRtpReceiver
        ) {
            guard let owner = self.owner else { return }

            Task { @WebRTSPActor in
                if(rtpReceiver == owner.remoteVideoReceiver) {
                    owner.remoteVideoTrack = nil
                }
            }
        }
    }

    typealias IceServers = [RTCIceServer]

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "GoogleWebRTCPeer")

    private var iceCandidateHandler: IceCandidateHandler = { _, _ in }
    private var eosHandler: EosHandler = {}

    private var delegate = Delegate()
    private var peerConnection: RTCPeerConnection

    typealias RemoteVideoTrackChangedHandler = (_ track: RTCVideoTrack?) -> Void
    private var remoteVideoTrackChangedHandler: RemoteVideoTrackChangedHandler = { _  in }
    private var remoteVideoReceiver: RTCRtpReceiver? = nil {
        didSet {
            if(self.remoteVideoReceiver == nil) {
                self.remoteVideoTrack = nil
            }
        }
    }
    private(set) var remoteVideoTrack: RTCVideoTrack? = nil {
        didSet {
            if(self.remoteVideoTrack != oldValue) {
                self.remoteVideoTrackChangedHandler(self.remoteVideoTrack)
            }
        }
    }


    init?(iceServers: IceServers) {
        let peerConnectionFactory =
            RTCPeerConnectionFactory(
                encoderFactory: nil,
                decoderFactory: RTCDefaultVideoDecoderFactory())

        let configuration = RTCConfiguration()
        configuration.sdpSemantics = RTCSdpSemantics.unifiedPlan
        configuration.iceServers = iceServers

        let constraints =
            RTCMediaConstraints(
                mandatoryConstraints: [:],
                optionalConstraints: [:])

        guard let peerConnection =
            peerConnectionFactory.peerConnection(
                with: configuration,
                constraints: constraints,
                delegate: delegate) else { return nil }

        self.peerConnection = peerConnection

        self.delegate.owner = self

        let transceiverInit = RTCRtpTransceiverInit()
        transceiverInit.direction = RTCRtpTransceiverDirection.recvOnly
        peerConnection.addTransceiver(of: RTCRtpMediaType.audio, init: transceiverInit)
        peerConnection.addTransceiver(of: RTCRtpMediaType.video, init: transceiverInit)
    }

    private func onIceCandidate(_ iceCandidate: RTCIceCandidate) async {
        await self.iceCandidateHandler(UInt(iceCandidate.sdpMLineIndex), iceCandidate.sdp)
    }
}

extension GoogleWebRTCPeer {
    func onRemoteVideoTrackChanged(_ remoteVideoTrackChangedHandler: @escaping RemoteVideoTrackChangedHandler) {
        self.remoteVideoTrackChangedHandler = remoteVideoTrackChangedHandler
    }

    func onIceCandidate(_ iceCandidateHandler: @escaping IceCandidateHandler) {
        self.iceCandidateHandler = iceCandidateHandler
    }

    func onEos(_ eosHandler: @escaping EosHandler) {
        self.eosHandler = eosHandler
    }

    func setRemoteSessionDescription(_ sessionDescription: String) async throws {
        let description = RTCSessionDescription(type: RTCSdpType.offer, sdp: sessionDescription)
        try await peerConnection.setRemoteDescription(description)
    }

    func getLocalSessionDescription() async throws -> String {
        let constraints =
            RTCMediaConstraints(
                mandatoryConstraints: [:],
                optionalConstraints: [:])

        let localSessionDescription = try await peerConnection.answer(for: constraints)
        try await peerConnection.setLocalDescription(localSessionDescription)

        return localSessionDescription.sdp
    }

    func addIceCandidate(mLineIndex: UInt, candidate: String) async throws {
        let iceCandidate = RTCIceCandidate(sdp: candidate, sdpMLineIndex: Int32(mLineIndex), sdpMid: nil)
        try await self.peerConnection.add(iceCandidate)
    }

    func close() {
        self.peerConnection.close()
        self.remoteVideoTrack = nil
    }
}

