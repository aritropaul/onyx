import Foundation

@Observable
final class AuthManager {
    private let profileManager: ProfileManager
    private let baseURL: String

    var isLoading = false
    var errorMessage: String?

    init(profileManager: ProfileManager, baseURL: String = "http://localhost:3000") {
        self.profileManager = profileManager
        self.baseURL = baseURL
    }

    // MARK: - API

    func register(email: String, password: String, displayName: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let body: [String: String] = [
            "email": email,
            "password": password,
            "display_name": displayName
        ]

        guard let result: AuthResponse = await post(path: "/auth/register", body: body) else {
            return false
        }

        profileManager.authToken = result.token
        profileManager.profile.email = email
        profileManager.profile.displayName = displayName
        if let userId = result.userId {
            profileManager.profile.id = userId
        }
        profileManager.save()
        return true
    }

    func login(email: String, password: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let body: [String: String] = [
            "email": email,
            "password": password
        ]

        guard let result: AuthResponse = await post(path: "/auth/login", body: body) else {
            return false
        }

        profileManager.authToken = result.token
        profileManager.profile.email = email
        if let name = result.displayName {
            profileManager.profile.displayName = name
        }
        if let userId = result.userId {
            profileManager.profile.id = userId
        }
        profileManager.save()
        return true
    }

    func validateToken() async -> Bool {
        guard let token = profileManager.authToken else { return false }

        var request = URLRequest(url: URL(string: "\(baseURL)/auth/me")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse else {
            return false
        }

        if httpResponse.statusCode == 401 {
            profileManager.authToken = nil
            return false
        }

        guard httpResponse.statusCode == 200,
              let user = try? JSONDecoder().decode(MeResponse.self, from: data) else {
            return false
        }

        profileManager.profile.email = user.email
        profileManager.profile.displayName = user.displayName
        profileManager.save()
        return true
    }

    // MARK: - Private

    private func post<T: Decodable>(path: String, body: [String: String]) async -> T? {
        guard let url = URL(string: "\(baseURL)\(path)"),
              let jsonData = try? JSONEncoder().encode(body) else {
            errorMessage = "Invalid request"
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse else {
            errorMessage = "Network error"
            return nil
        }

        guard httpResponse.statusCode == 200 else {
            if let err = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                errorMessage = err.error
            } else {
                errorMessage = "Request failed (\(httpResponse.statusCode))"
            }
            return nil
        }

        guard let result = try? JSONDecoder().decode(T.self, from: data) else {
            errorMessage = "Invalid response"
            return nil
        }

        return result
    }
}

// MARK: - Response Types

private struct AuthResponse: Decodable {
    let token: String
    let userId: String?
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case token
        case userId = "user_id"
        case displayName = "display_name"
    }
}

private struct MeResponse: Decodable {
    let id: String
    let email: String
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case displayName = "display_name"
    }
}

private struct ErrorResponse: Decodable {
    let error: String
}
