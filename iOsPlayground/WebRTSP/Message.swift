typealias CSeq = Int
typealias MediaSession = String
typealias Parameter = (String, String)
typealias HeaderFields = [String: String]
typealias HeaderField = (String, String)
typealias ContentType = String

class MessageCommon {
    let protocolName: Protocol

    let mediaSession: MediaSession?
    private(set) var headerFields: HeaderFields
    let body: String

    var contentType: ContentType? {
        return headerFields["content-type"]
    }

    init(
        protocolName: Protocol,
        mediaSession: MediaSession? = nil,
        headerFields: HeaderFields,
        body: String
    ) {
        self.protocolName = protocolName
        self.mediaSession = mediaSession
        self.headerFields = headerFields
        self.body = body
    }

    func getHeaderField(_ name: String) -> String? {
        return self.headerFields[name.lowercased()]
    }
    func setHeaderField(_ name: String, value: String) {
        self.headerFields[name] = value
    }
    func setContentType(_ contentType: String) {
        setHeaderField("Content-Type", value: contentType)
    }
}

class Request: MessageCommon {
    let method: Method
    let uri: String

    init(
        method: Method,
        uri: String,
        protocolName: Protocol,
        mediaSession: MediaSession? = nil,
        headerFields: HeaderFields = [:],
        body: String = String()
    ) {
        self.method = method
        self.uri = uri
        super.init(
            protocolName: protocolName,
            mediaSession: mediaSession,
            headerFields: headerFields,
            body: body)
    }
}

class InRequest: Request {
    let cSeq: CSeq

    init(
        method: Method,
        uri: String,
        protocolName: Protocol,
        cSeq: CSeq,
        mediaSession: MediaSession? = nil,
        headerFields: HeaderFields = [:],
        body: String
    ) {
        self.cSeq = cSeq
        super.init(
            method: method,
            uri: uri,
            protocolName: protocolName,
            mediaSession: mediaSession,
            headerFields: headerFields,
            body: body)
    }
}

class Response: MessageCommon {
    let statusCode: StatusCode
    let reasonPhrase: String
    let cSeq: CSeq

    init(
        protocolName: Protocol,
        statusCode: StatusCode,
        reasonPhrase: String,
        cSeq: CSeq,
        mediaSession: MediaSession? = nil,
        headerFields: HeaderFields,
        body: String
    ) {
        self.statusCode = statusCode
        self.reasonPhrase = reasonPhrase
        self.cSeq = cSeq
        super.init(
            protocolName: protocolName,
            mediaSession: mediaSession,
            headerFields: headerFields,
            body: body)
    }
}

func ContentTypeField(contentType: ContentType) -> HeaderField {
    return ("content-type", contentType)
}
