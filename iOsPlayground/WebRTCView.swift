import SwiftUI
import WebRTC


struct WebRTCView: UIViewRepresentable {
    @ObservedObject var controller: Controller

    func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView(frame: .zero)
        view.videoContentMode = .scaleAspectFit
        return view
    }

    func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {
        guard let remoteVideoTrack = self.controller.remoteVideoTrack else { return }

        remoteVideoTrack.add(uiView) // FIXME?
    }
}
