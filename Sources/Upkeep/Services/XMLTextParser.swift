import Foundation

class XMLTextParser: NSObject, XMLParserDelegate {
    final func parser(_ parser: XMLParser, foundCharacters string: String) {
        appendXMLText(string, parser: parser)
    }

    final func parser(_ parser: XMLParser, foundCDATA data: Data) {
        appendXMLText(String(decoding: data, as: UTF8.self), parser: parser)
    }

    func appendXMLText(_ string: String, parser: XMLParser) {
        preconditionFailure("XMLTextParser subclasses must handle parsed text")
    }
}
