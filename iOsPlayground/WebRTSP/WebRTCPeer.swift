@WebRTSPActor
protocol WebRTCPeer {
    typealias IceCandidateHandler = (_ mLineIndex: UInt, _ candidate: String) async -> Void
    typealias EosHandler = () -> Void

    func onIceCandidate(_ iceCandidateHandler: @escaping IceCandidateHandler)
    func onEos(_ eosHandler: @escaping EosHandler)

    func setRemoteSessionDescription(_ sessionDescription: String) async throws
    func getLocalSessionDescription() async throws -> String
    func addIceCandidate(mLineIndex: UInt, candidate: String) async throws
    func close()
}

