import Foundation

enum UpdateSourceError: LocalizedError, Sendable {
    case invalidResponse
    case httpStatus(Int)
    case malformedData(String)
    case transport(String)

    init(_ error: Error) {
        if let sourceError = error as? UpdateSourceError {
            self = sourceError
        } else if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                self = .transport("No network connection.")
            case .timedOut:
                self = .transport("The request timed out.")
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                self = .transport("The update server could not be reached.")
            default:
                self = .transport(urlError.localizedDescription)
            }
        } else {
            self = .transport(error.localizedDescription)
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "The update server returned an invalid response."
        case let .httpStatus(status): "The update server returned HTTP \(status)."
        case let .malformedData(details): "The update data could not be read: \(details)"
        case let .transport(message): message
        }
    }
}
