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
    /// Rutas `home/*` que NO llevan `X-Home-Id`: `home/create` (no opera sobre un hogar existente)
    /// y `home/default` (el contrato responde 404 si la cabecera difiere del `home_id` pedido).
    /// `GET home` (path `home`) tampoco la lleva porque no empieza por `home/`.
    static let homeHeaderExcludedPaths: Set<String> = ["home/create", "home/default"]

    /// Regla de envío de `X-Home-Id`: ruta autenticada bajo `home/` y fuera de las excluidas.
    static func sendsHomeHeader(for apiRequest: APIRequest) -> Bool {
        !apiRequest.isPublic
            && apiRequest.path.hasPrefix("home/")
            && !homeHeaderExcludedPaths.contains(apiRequest.path)
    }

    /// Construye el `URLRequest` final. GET/HEAD nunca llevan body aunque se pase (desviación 9).
    /// `X-Home-Id` solo se añade si `homeId` no está vacío y aplica la regla de `sendsHomeHeader`.
    public static func urlRequest(baseURL: URL, apiRequest: APIRequest, accessToken: String?, homeId: String? = nil) throws -> URLRequest {
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
        if let homeId, !homeId.isEmpty, sendsHomeHeader(for: apiRequest) {
            request.setValue(homeId, forHTTPHeaderField: "X-Home-Id")
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
