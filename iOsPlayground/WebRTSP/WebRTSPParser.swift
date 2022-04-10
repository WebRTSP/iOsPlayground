import Foundation


private struct MethodLine {
    let method: Method
    let uri: String
    let protocolName: Protocol
}

private struct StatusLine {
    let protocolName: Protocol
    let statusCode: StatusCode
    let reasonPhrase: String
}

extension WebRTSPParser.Error: LocalizedError {
    public var errorDescription: String? {
        switch(self) {
        default:
            return "\(String(describing: self))"
        }
    }
}

final class WebRTSPParser {
    private let scanner: Scanner

    init(buffer: String) {
        self.scanner = Scanner(string: buffer)
        self.scanner.charactersToBeSkipped = nil
    }

    private var eos: Bool {
        return self.scanner.isAtEnd
    }

    private var tail: String {
        return String(self.scanner.string[self.scanner.currentIndex...])
    }

    private var currentChar: Character? {
        guard !self.scanner.isAtEnd else { return nil }
        return self.scanner.string[self.scanner.currentIndex]
    }

    private static let spaceCharacterSet = CharacterSet(charactersIn: " ")
    private static let wspCharacterSet = CharacterSet(charactersIn: " \t")
    private static let ctlCharacterSet =
        CharacterSet(charactersIn: Unicode.Scalar(UInt8(0))...Unicode.Scalar(UInt8(31)))
            .union(CharacterSet([Unicode.Scalar(UInt8(127))]))
    private static let tSpecialsCharacterSet = CharacterSet(charactersIn: "()<>@,;:\\\"/[]?={} \t")

    private var isCurrentCtl: Bool {
        guard let asciiChar = self.currentChar?.asciiValue else { return false }
        return Self.ctlCharacterSet.contains(Unicode.Scalar(asciiChar))
    }

    /*
    private func startsWith(prefix: String): Bool {
        return buffer.startsWith(prefix, pos)
    }
    private func substringFrom(beginPos: Int): String {
        return buffer.substring(beginPos, pos)
    }
    private func substring(beginPos: Int, endPos: Int): String {
        return buffer.substring(beginPos, endPos)
    }
    */

    private func advance(count: UInt = 1) -> Bool {
        let savedIndex = self.scanner.currentIndex
        for _ in 1...count {
            if(self.scanner.scanCharacter() == nil) {
                self.scanner.currentIndex = savedIndex
                return false
            }
        }

        return true
    }

    private func skipWSP() -> Bool {
        self.scanner.scanCharacters(from: Self.wspCharacterSet) != nil
    }
    private func skipEOL() -> Bool {
        if(skip("\n")) {
            return true
        }

        if(skip("\r\n") ) {
            return true
        }

        return false
    }
    private func skipFolding() -> Bool {
        let savedIndex = self.scanner.currentIndex

        if(!skipEOL()) {
            self.scanner.currentIndex = savedIndex
            return false
        }
        if(!skipWSP()) {
            self.scanner.currentIndex = savedIndex
            return false
        }

        return true
    }
    private func skipLWS() -> Bool {
        let savedIndex = self.scanner.currentIndex

        _ = skipEOL()
        if(!self.skipWSP()) {
            self.scanner.currentIndex = savedIndex
            return false
        }

        return true
    }
    private func skip(_ char: Character) -> Bool {
        guard !self.scanner.isAtEnd else { return false }

        let savedIndex = self.scanner.currentIndex
        if let scannedChar = self.scanner.scanCharacter(), scannedChar == char {
            return true
        } else {
            self.scanner.currentIndex = savedIndex
            return false
        }
    }
    private func skipNot(_ char: Character) -> Bool {
        let scanTillCharacterSet = CharacterSet(charactersIn: String(char))
        return self.scanner.scanUpToCharacters(from: scanTillCharacterSet) != nil
    }
    private func scanDigit() -> Character? {
        let savedIndex = self.scanner.currentIndex
        if let scannedChar = self.scanner.scanCharacter(), scannedChar.isASCII && scannedChar.isNumber {
            return scannedChar
        } else {
            self.scanner.currentIndex = savedIndex
            return nil
        }
    }
    private func getToken() -> Token? {
        let scanTillCharacterSet = Self.ctlCharacterSet.union(Self.tSpecialsCharacterSet)
        return self.scanner.scanUpToCharacters(from: scanTillCharacterSet)
    }
    private func getProtocolToken() -> Token? {
        let protocolPrefix = "WEBRTSP"

        guard self.scanner.scanString(protocolPrefix) != nil else { return nil }
        guard self.scanner.scanString("/") != nil else { return nil }
        guard let majorDigit = scanDigit() else { return nil }
        guard skip(".") else { return nil }
        guard let minorDigit = scanDigit() else { return nil }

        return "\(protocolPrefix)/\(majorDigit).\(minorDigit)"
    }
    private func getProtocol() -> Protocol? {
        guard let token = getProtocolToken() else { return nil }
        return Self.ParseProtocol(token: token)
    }
    private func getURIToken() -> Token? {
        // FIXME! fix according to rfc
        let scanTillCharacterSet = Self.ctlCharacterSet.union(Self.spaceCharacterSet)
        return self.scanner.scanUpToCharacters(from: scanTillCharacterSet)
    }
    private func getURI() throws -> String {
        guard let token = getURIToken() else { throw Error.ParseFailed }
        return token
    }
    private func getStatusCodeToken() -> Token? {
        let savedIndex = self.scanner.currentIndex

        var statusCode = Token()
        for _ in 1...3 {
            guard let digit = scanDigit() else {
                self.scanner.currentIndex = savedIndex
                return nil
            }
            statusCode.append(digit)
        }

        return statusCode
    }
    private func getStatusCode() throws -> StatusCode {
        guard let token = getStatusCodeToken() else { throw Error.ParseFailed }
        return try Self.ParseStatusCode(token: token)
    }
    private func getReasonPhraseToken() -> Token? {
        let scanTillCharacterSet = Self.ctlCharacterSet
        return self.scanner.scanUpToCharacters(from: scanTillCharacterSet)
    }
    private func getReasonPhrase() throws -> String {
        guard let token = getReasonPhraseToken() else { throw Error.ParseFailed }
        return token
    }
    private func getMethodLine() throws -> MethodLine {
        guard let methodToken = getToken() else { throw Error.ParseFailed }
        guard let method = Self.ParseMethod(token: methodToken) else { throw Error.ParseFailed }
        guard skipWSP() else { throw Error.ParseFailed }
        let uri = try getURI()
        guard skipWSP() else { throw Error.ParseFailed }
        guard let protocolName = getProtocol() else { throw Error.ParseFailed }
        guard skipEOL() else { throw Error.ParseFailed }

        return MethodLine(method: method, uri: uri, protocolName: protocolName)
    }
    private func getHeaderField() -> HeaderField? {
        guard let nameToken = getToken() else { return nil }
        guard skip(":") else { return nil }
        _ = skipLWS()

        let valueStartIndex = self.scanner.currentIndex
        while(!self.eos) {
            let valueEndIndex = self.scanner.currentIndex
            if(skipFolding()) {
                continue
            } else if(skipEOL()) {
                let lowerName = nameToken.lowercased()
                let value = self.scanner.string[valueStartIndex..<valueEndIndex]
                return (lowerName, String(value))
            } else if(!isCurrentCtl) {
                _ = advance()
            } else {
                return nil
            }
        }

        return nil
    }
/*
    private func getParameter(): Parameter? {
        let namePos = pos

        if(!skipNot(':')) return nil

        let name = substringFrom(namePos)
        if(name.isBlank()) return nil

        if(!skip(':')) return nil

        skipWSP()

        let valuePos = pos

        while(!eos) {
            let tmpPos = pos
            if(skipEOL()) {
                let value = substring(valuePos, tmpPos);
                return Parameter(name, value)
            } else if(!isCurrentCtl)
                advance()
            else
                return nil
        }

        return nil
    }
*/
    private func getStatusLine() throws -> StatusLine {
        guard let protocolName = getProtocol() else { throw Error.ParseFailed }
        guard skipWSP() else { throw Error.ParseFailed }
        let statusCode = try getStatusCode()
        guard skipWSP() else { throw Error.ParseFailed }
        let reasonPhrase = try getReasonPhrase()
        guard skipEOL() else {  throw Error.ParseFailed }

        return StatusLine(protocolName: protocolName, statusCode: statusCode, reasonPhrase: reasonPhrase)
    }
}

extension WebRTSPParser {
    enum Error: Swift.Error {
        case ParseFailed
    }

    /*
    func ParseParameters(body: String): Map<String, String>? {
        let parameters = mutableMapOf<String, String>();

        let parser = Parser(body);
        while(!parser.eos) {
            let pair = parser.getParameter() ?: return nil
            if(pair.first.isEmpty()) return nil

            parameters.set(pair.first, pair.second);
        }

        return parameters;
    }
    */

    static func ParseOptions(_ optionsString: String) throws -> Set<Method> {
        var parsedOptions = Set<Method>()

        let parser = WebRTSPParser(buffer: optionsString)
        while(!parser.eos) {
            _ = parser.skipWSP()

            guard let methodToken = parser.getToken() else { throw Error.ParseFailed }
            guard let method = Self.ParseMethod(token: methodToken) else { throw Error.ParseFailed }

            parsedOptions.update(with: method)

            _ = parser.skipWSP()

            guard !parser.eos else { break }

            guard parser.skip(",") else { throw Error.ParseFailed }
        }

        return parsedOptions
    }

    static func ParseIceCandidates(_ iceCandidates: String) throws -> [(UInt, String)] {
        let iceCandidatesList = iceCandidates.split(whereSeparator: \.isNewline)

        return try iceCandidatesList.compactMap { candidateRow in
            if(candidateRow.isEmpty) {
                return nil
            } else {
                let fields = candidateRow.split(separator: "/", maxSplits: 2)
                guard fields.count == 2 else { throw Error.ParseFailed }
                guard let mLineIndex = UInt(fields[0]) else { throw Error.ParseFailed }
                let candidate = String(fields[1])
                return (mLineIndex, candidate)
            }
        }
    }

    static func ParseProtocol( token: Token) -> Protocol? {
        guard !token.isEmpty else { return nil }

        for protocolName in Protocol.allCases {
            if(token == protocolName.rawValue) {
                return protocolName
            }
        }

        return nil
    }

    static func ParseMethod(token: Token) -> Method? {
        guard !token.isEmpty else { return nil }

        for method in Method.allCases {
            if(token == method.rawValue) {
                return method
            }
        }

        return nil
    }

    static func ParseStatusCode(token: String) throws -> StatusCode {
        guard token.count == 3 else { throw Error.ParseFailed }

        var statusCode: UInt = 0

        for c in token {
            guard c.isASCII && c.isNumber, let digit = c.wholeNumberValue else { throw Error.ParseFailed }

            statusCode = statusCode * 10 + UInt(digit)
        }

        return statusCode
    }

    static func ParseCSeq(token: String) throws -> CSeq {
        var cSeq = 0

        for c in token {
            guard c.isASCII && c.isNumber, let digit = c.wholeNumberValue else { throw Error.ParseFailed }

            var shifted: CSeq
            var overflow = false

            (shifted, overflow) = cSeq.multipliedReportingOverflow(by: 10)
            guard !overflow else { throw Error.ParseFailed }

            (cSeq, overflow) = shifted.addingReportingOverflow(digit)
            guard !overflow else { throw Error.ParseFailed }
        }

        guard cSeq != 0 else { throw Error.ParseFailed }

        return cSeq
    }

    static func IsRequest(message: String) throws -> Bool {
        let parser = WebRTSPParser(buffer: message)
        guard let methodToken = parser.getToken() else { throw Error.ParseFailed }
        return ParseMethod(token: methodToken) != nil
    }

    static func ParseRequest(message: String) throws -> InRequest {
        let parser = WebRTSPParser(buffer: message)

        let methodLine = try parser.getMethodLine()

        var headerFields = [String: String]()
        while(!parser.eos) {
            guard let headerField = parser.getHeaderField() else { throw Error.ParseFailed }
            headerFields[headerField.0] = headerField.1
            if(parser.eos) {
                break // no body
            }
            if(parser.skipEOL()) {
                break // empty line before body
            }
        }

        var body = String()
        if(!parser.eos) {
            body = parser.tail
        }

        guard let strCSeq = headerFields["cseq"] else { throw Error.ParseFailed }
        let cSeq = try ParseCSeq(token: strCSeq)
        headerFields.removeValue(forKey: "cseq")

        let mediaSession = headerFields["session"]
        if(mediaSession != nil) {
            headerFields.removeValue(forKey: "session")
        }

        return InRequest(
            method: methodLine.method, uri: methodLine.uri, protocolName: methodLine.protocolName,
            cSeq: cSeq, mediaSession: mediaSession, headerFields: headerFields,
            body: body)
    }
    static func ParseResponse(message: String) throws -> Response {
        let parser = WebRTSPParser(buffer: message)

        let statusLine = try parser.getStatusLine()

        var headerFields = HeaderFields()
        while(!parser.eos) {
            guard let headerField = parser.getHeaderField() else { throw Error.ParseFailed }
            headerFields[headerField.0] = headerField.1

             if(parser.eos) {
                break // no body
            }
            if(parser.skipEOL()) {
                break // empty line before body
            }
        }

        var body = String()
        if(!parser.eos) {
            body = parser.tail
        }

        guard let strCSeq = headerFields["cseq"] else { throw Error.ParseFailed }
        let cSeq = try ParseCSeq(token: strCSeq)
        headerFields.removeValue(forKey: "cseq")

        let mediaSession: String? = headerFields["session"]
        if(mediaSession != nil) {
            headerFields.removeValue(forKey: "session")
        }

        return Response(
            protocolName: statusLine.protocolName, statusCode: statusLine.statusCode, reasonPhrase: statusLine.reasonPhrase,
            cSeq: cSeq, mediaSession: mediaSession, headerFields: headerFields,
            body: body)
    }
}

extension Request {
    static func isRequest(_ message: String) throws -> Bool {
        return try WebRTSPParser.IsRequest(message: message)
    }

    static func parse(_ message: String) throws -> Request {
        return try WebRTSPParser.ParseRequest(message: message)
    }
}

extension Response {
    static func parse(_ message: String) throws -> Response {
        return try WebRTSPParser.ParseResponse(message: message)
    }
}
