import Foundation
import WebRTC


class Controller: ObservableObject {
    @MainActor @Published
    var remoteVideoTrack: RTCVideoTrack? = nil

    @WebRTSPActor
    private var session: WebRTSPSession? = nil

    init() {
        initConnection()
    }

    func initConnection() {
        Task { @WebRTSPActor in
            guard self.session == nil else { return }

            let session = WebRTSPSession()
            guard let localPeer = session.localPeer else { return }
            self.session = session

            localPeer.onRemoteVideoTrackChanged { [weak self] remoteVideoTrack in
                guard let self = self else { return }

                Task { @MainActor in
                    self.remoteVideoTrack = remoteVideoTrack
                }
            }

            var success = false
            do {
                try await session.connect()
                success = true
            } catch {
                print("Connect failed with: \(error.localizedDescription)")
            }

            if(!success) {
                session.disconnect()
                self.session = nil
            }
        }
    }
}
