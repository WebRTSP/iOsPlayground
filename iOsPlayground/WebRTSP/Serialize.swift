import Foundation


extension Request {
    func serialize(cSeq: CSeq) -> String {
        var out = String()

        out += "\(self.method) \(self.uri) \(self.protocolName.rawValue)\r\n"
        out += "CSeq: \(cSeq)\r\n"

        if let mediaSession = self.mediaSession {
            out += "Session: \(mediaSession)\r\n"
        }

        self.headerFields.forEach { (key, value) in
            out += "\(key): \(value)\r\n"
        }

        if(!self.body.isEmpty) {
            out += "\r\n"
            out += self.body
        }

        return out
    }
}

extension Response {
    private func SerializeStatusCode(_ statusCode: StatusCode) -> String {
        switch(statusCode) {
            case ...99: return "100"
            case 1000...: return "999"
            default: return String(statusCode)
        }
    }

    func serialize() -> String {
        var out = String()

        out += "\(self.protocolName.rawValue) $\(SerializeStatusCode(self.statusCode)) \(self.reasonPhrase)\r\n"
        out += "CSeq: $\(self.cSeq)\r\n"

        if let mediaSession = self.mediaSession {
            out.append("Session: \(mediaSession)\r\n");
        }

        self.headerFields.forEach { (key, value) in
            out += "\(key): \(value)\r\n"
        }

        if(!self.body.isEmpty) {
            out += "\r\n"
            out += self.body
        }

        return out
    }
}
