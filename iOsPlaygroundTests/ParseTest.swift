import XCTest
@testable import iOsPlayground

class ParseTest: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testOptionsRequestParse() throws {
        let message =
            "OPTIONS * WEBRTSP/0.2\r\n" +
            "CSeq: 1\r\n"

        let request = try WebRTSPParser.ParseRequest(message: message)
        XCTAssertNotNil(request)
        XCTAssertEqual(request.method, Method.OPTIONS)
        XCTAssertEqual(request.uri, "*")
        XCTAssertEqual(request.protocolName, Protocol.WEBRTSP_0_2)
        XCTAssertEqual(request.cSeq, 1)
        XCTAssert(request.headerFields.isEmpty)
    }

    func testOptionsRequestParse2() throws {
        let message =
            "OPTIONS * WEBRTSP/0.2\r\n" +
            "CSeq:\t1\r\n"

        let request = try WebRTSPParser.ParseRequest(message: message)
        XCTAssertNotNil(request)
        XCTAssertEqual(request.method, Method.OPTIONS)
        XCTAssertEqual(request.uri, "*")
        XCTAssertEqual(request.protocolName, Protocol.WEBRTSP_0_2)
        XCTAssertEqual(request.cSeq, 1)
        XCTAssert(request.headerFields.isEmpty)
    }

    func testSetupRequestParse() throws {
        let message =
            "SETUP rtsp://example.com/meida.ogg/streamid=0 WEBRTSP/0.2\r\n" +
            "CSeq: 3\r\n" +
            "Transport: RTP/AVP;unicast;client_port=8000-8001\r\n"

        let request = try WebRTSPParser.ParseRequest(message: message)

        XCTAssertEqual(request.method, Method.SETUP)
        XCTAssertEqual(request.uri, "rtsp://example.com/meida.ogg/streamid=0")
        XCTAssertEqual(request.protocolName, Protocol.WEBRTSP_0_2)
        XCTAssertEqual(request.cSeq, 3)
        XCTAssertEqual(request.headerFields.count, 1)

        XCTAssertEqual(request.headerFields.first!.key, "transport")
        XCTAssertEqual(request.headerFields.first!.value, "RTP/AVP;unicast;client_port=8000-8001")
    }

    func testGetParameterRequestParse() throws {
        let message =
            "GET_PARAMETER rtsp://example.com/media.mp4 WEBRTSP/0.2\r\n" +
            "CSeq: 9\r\n" +
            "Content-Type: text/parameters\r\n" +
            "Session: 12345678\r\n" +
            "\r\n" +
            "packets_received\r\n" +
            "jitter\r\n"

        let request = try WebRTSPParser.ParseRequest(message: message)
        XCTAssertEqual(Method.GET_PARAMETER, request.method)
        XCTAssertEqual(request.protocolName, Protocol.WEBRTSP_0_2)
        XCTAssertEqual(9, request.cSeq)
        XCTAssertEqual("12345678", request.mediaSession)
        XCTAssertEqual(1, request.headerFields.count)
        XCTAssertTrue(!request.body.isEmpty)
    }
    func testGetParameterResponseParse() throws {
        let message =
            "WEBRTSP/0.2 200 OK\r\n" +
            "CSeq: 9\r\n" +
            "Content-Length: 46\r\n" +
            "Content-Type: text/parameters\r\n" +
            "\r\n" +
            "packets_received: 10\r\n" +
            "jitter: 0.3838\r\n"

        let response = try WebRTSPParser.ParseResponse(message: message)
        XCTAssertEqual(response.protocolName, Protocol.WEBRTSP_0_2)
        XCTAssertEqual(response.statusCode, KnownStatus.Ok.rawValue)
        XCTAssertEqual(response.reasonPhrase, "OK")
        XCTAssertEqual(response.cSeq, 9)
        XCTAssertEqual(response.headerFields.count, 2)
        XCTAssertTrue(!response.body.isEmpty)
    }
}
