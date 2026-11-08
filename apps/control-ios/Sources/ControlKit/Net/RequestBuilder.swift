import Foundation

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case patch = "PATCH"
    case delete = "DELETE"
}

/// Petición al contrato: `path` relativo a `PLANIFY_BASE_URL` (sin slash inicial), filtros de
/// lectura SIEMPRE en `query` (GET nunca lleva body: el runtime de Edge lo descarta), y body
/// JSON opcional para POST/PATCH/DELETE (en DELETE también va body, como PHP).
public struct APIRequest: Equatable, Sendable {
    public let method: HTTPMethod
    public let path: String
    public let query: [URLQueryItem]
    public let body: Data?
    /// Rutas públicas (`GET config`, `POST user/create`, `POST user/auth`): sin `Authorization`.
    public let isPublic: Bool

    public init(method: HTTPMethod, path: String, query: [URLQueryItem] = [], body: Data? = nil, isPublic: Bool = false) {
        self.method = method
        self.path = path
        self.query = query
        self.body = body
        self.isPublic = isPublic
    }
}

public enum RequestBuilder {
    /// Construye el `URLRequest` final. GET/HEAD nunca llevan body aunque se pase (desviación 9).
    public static func urlRequest(baseURL: URL, apiRequest: APIRequest, accessToken: String?) throws -> URLRequest {
        let joined = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard var components = URLComponents(string: joined + "/" + apiRequest.path) else {
            throw APIError.decoding("URL inválida: \(apiRequest.path)")
        }
        if !apiRequest.query.isEmpty {
            components.queryItems = apiRequest.query
        }
        guard let url = components.url else {
            throw APIError.decoding("URL inválida: \(apiRequest.path)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = apiRequest.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if apiRequest.body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if !apiRequest.isPublic, let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        if apiRequest.method != .get {
            request.httpBody = apiRequest.body
        }
        return request
    }
}

enum JSONCoding {
    /// `sortedKeys` para bodies deterministas (tests de forma de petición).
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        JSONDecoder()
    }
}
