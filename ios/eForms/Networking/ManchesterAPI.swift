import Foundation

enum APIError: LocalizedError {
    case notAuthenticated
    case unexpectedResponse
    case server(Int)
    case message(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Your Manchester eForms session has expired."
        case .unexpectedResponse: return "Manchester eForms returned an unexpected response."
        case .server(let code): return "Manchester eForms returned HTTP \(code)."
        case .message(let text): return text
        }
    }
}

actor ManchesterAPI {
    static let shared = ManchesterAPI()
    private let redirectDelegate: NoRedirectDelegate
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 45
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let redirectDelegate = NoRedirectDelegate()
        self.redirectDelegate = redirectDelegate
        session = URLSession(configuration: configuration, delegate: redirectDelegate, delegateQueue: nil)
    }

    func assignedForms() async throws -> JSONArray {
        var forms = try await arrayRequest("/ui/api/forms")
        for formIndex in forms.indices {
            let formID = encode(forms[formIndex].string("id"))
            forms[formIndex]["fields"] = try await arrayRequest("/ui/api/forms/\(formID)/fields")
            var sets = forms[formIndex].objects("populationSets")
            for setIndex in sets.indices {
                let setID = encode(sets[setIndex].string("id"))
                var populations = try await arrayRequest("/ui/api/forms/\(formID)/popSets/\(setID)/populations")
                for populationIndex in populations.indices {
                    let populationID = encode(populations[populationIndex].string("id"))
                    populations[populationIndex]["tokenMap"] = try await objectRequest(
                        "/ui/api/forms/\(formID)/popSets/\(setID)/populations/\(populationID)/tokens"
                    )
                }
                sets[setIndex]["populations"] = populations
            }
            forms[formIndex]["populationSets"] = sets
        }
        return forms
    }

    func headers(_ status: String) async throws -> JSONArray {
        try await arrayRequest("/ui/api/submissions/\(encode(status))")
    }

    func submission(_ uuid: String) async throws -> JSONObject {
        try await objectRequest("/ui/api/submissions/\(encode(uuid))")
    }

    func save(_ payload: JSONObject) async throws -> String {
        let response = try await objectRequest("/ui/api/submissions/save", method: "POST", body: payload)
        let uuid = response.string("uuid")
        guard !uuid.isEmpty else { throw APIError.message("The server did not return a submission ID.") }
        return uuid
    }

    func promote(_ uuid: String) async throws {
        let response = try await objectRequest("/ui/api/submissions/\(encode(uuid))/promote", method: "POST", body: [:])
        guard response.bool("success") else { throw APIError.message("The server did not accept the form.") }
    }

    func deleteDraft(_ uuid: String) async throws {
        let response = try await objectRequest("/ui/api/submissions/\(encode(uuid))/delete", method: "POST", body: [:])
        guard response.bool("success") else { throw APIError.message("Manchester eForms did not delete the draft.") }
    }

    private func arrayRequest(_ path: String) async throws -> JSONArray {
        guard let value = try await request(path: path) as? JSONArray else { throw APIError.unexpectedResponse }
        return value
    }

    private func objectRequest(_ path: String, method: String = "GET", body: JSONObject? = nil) async throws -> JSONObject {
        guard let value = try await request(path: path, method: method, body: body) as? JSONObject else {
            throw APIError.unexpectedResponse
        }
        if let message = value["error"] as? String { throw APIError.message(message) }
        return value
    }

    private func request(path: String, method: String = "GET", body: JSONObject? = nil) async throws -> Any {
        guard let url = URL(string: path, relativeTo: SessionStore.origin) else { throw APIError.unexpectedResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(await SessionStore.shared.cookieHeader(), forHTTPHeaderField: "Cookie")
        request.setValue(SessionStore.origin.absoluteString, forHTTPHeaderField: "Origin")
        request.setValue(SessionStore.home.absoluteString, forHTTPHeaderField: "Referer")
        request.setValue("eForms-iOS/1.0", forHTTPHeaderField: "User-Agent")
        let csrf = await SessionStore.shared.csrfToken()
        if !csrf.isEmpty { request.setValue(csrf, forHTTPHeaderField: "X-XSRF-TOKEN") }
        if let body {
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, rawResponse) = try await session.data(for: request)
        guard let response = rawResponse as? HTTPURLResponse else { throw APIError.unexpectedResponse }
        await SessionStore.shared.acceptCookies(from: response)
        if response.statusCode == 401 || [301, 302, 303, 307, 308].contains(response.statusCode) {
            throw APIError.notAuthenticated
        }
        guard (200..<300).contains(response.statusCode) else { throw APIError.server(response.statusCode) }
        if response.statusCode == 204 || data.isEmpty { return JSONObject() }
        guard response.value(forHTTPHeaderField: "Content-Type")?.lowercased().contains("json") == true else {
            throw APIError.notAuthenticated
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    private func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }
}

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
