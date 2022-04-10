import XCTest
@testable import iOsPlayground


class WebRTSPClientTest: XCTestCase {
    private let clockServer = URL(string: "ws://rpi:5554")!

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testConnectDisconnect() async throws {
        let client = await WebRTSPClient()
        try await client.connect(url: self.clockServer)
        await client.disconnect()
    }

    func testOptionsRequest() async throws {
        let client = await WebRTSPClient()
        try await client.connect(url: self.clockServer)

        let options = try await client.requestOptions()
        print("Available methods: \(String(describing: options))")

        await client.disconnect()
    }

    func testDescribe() async throws {
        let client = await WebRTSPClient()
        try await client.connect(url: self.clockServer)

        let options = try await client.requestOptions()
        print("Available methods: \(String(describing: options))")

        let sessionDescription = try await client.requestDescribe()
        print("Remote session description: \(String(describing: sessionDescription))")

        try await client.requestTeardown()

        await client.disconnect()
    }

    private func handleSetupRequest(_ request: Request, localPeer: WebRTCPeer) async {
        guard request.method == .SETUP else { return }
        guard request.contentType == "application/x-ice-candidate" else {
            XCTFail("Unexpected \"Content-type\" value")
            return
        }

        do {
            let iceCandidates = try WebRTSPParser.ParseIceCandidates(request.body)
            for (mLineIndex, candidate) in iceCandidates {
                try await localPeer.addIceCandidate(mLineIndex: mLineIndex, candidate: candidate)
            }
        } catch {
            XCTFail("Ice candidates parsing failed")
        }
    }

    func testPeerConnection() async throws {
        let client = await WebRTSPClient()

        try await client.connect(url: self.clockServer)

        let _ = try await client.requestOptions()

        if let localPeer = await GoogleWebRTCPeer(iceServers: GoogleWebRTCPeer.IceServers()) {
            await client.onRequest { request in
                switch(request.method) {
                case .SETUP:
                    await self.handleSetupRequest(request, localPeer: localPeer)
                    break
                default:
                    break
                }
            }

            await localPeer.onIceCandidate { mLineIndex, candidate in
                do {
                    try await client.requestSetup(mLineIndex: mLineIndex, candidate: candidate)
                } catch {
                    XCTFail("Request setup failed with: \(error.localizedDescription)")
                }
            }

            let remoteSessionDescription = try await client.requestDescribe()
            try await localPeer.setRemoteSessionDescription(remoteSessionDescription)

            let localSessionDescription = try await localPeer.getLocalSessionDescription()
            try await client.requestPlay(with: localSessionDescription)
        }

        try await Task.sleep(nanoseconds: 5 * NSEC_PER_SEC)

        try await client.requestTeardown()

        await client.disconnect()
    }
}
