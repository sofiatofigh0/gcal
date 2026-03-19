import Foundation
import AuthenticationServices

final class GoogleCalendarService: ObservableObject {
    static let shared = GoogleCalendarService()

    @Published var isSignedIn = false
    @Published var userEmail: String?

    private var accessToken: String?
    private var refreshToken: String?

    private let clientId: String
    private let redirectURI: String
    private let calendarBaseURL = "https://www.googleapis.com/calendar/v3"

    private let tokenKey = "google_access_token"
    private let refreshTokenKey = "google_refresh_token"
    private let emailKey = "google_user_email"

    private init() {
        clientId = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLIENT_ID") as? String ?? ""
        redirectURI = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_REDIRECT_URI") as? String ?? ""

        accessToken = KeychainHelper.load(key: tokenKey)
        refreshToken = KeychainHelper.load(key: refreshTokenKey)
        userEmail = UserDefaults.standard.string(forKey: emailKey)
        isSignedIn = accessToken != nil
    }

    // MARK: - OAuth2 Authentication

    func getAuthorizationURL() -> URL? {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "https://www.googleapis.com/auth/calendar https://www.googleapis.com/auth/userinfo.email"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        return components?.url
    }

    func handleAuthorizationCode(_ code: String) async throws {
        let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "code": code,
            "client_id": clientId,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code",
        ]
        request.httpBody = body.map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)

        await MainActor.run {
            self.accessToken = tokenResponse.accessToken
            self.refreshToken = tokenResponse.refreshToken
            self.isSignedIn = true
        }

        KeychainHelper.save(key: tokenKey, value: tokenResponse.accessToken)
        if let refresh = tokenResponse.refreshToken {
            KeychainHelper.save(key: refreshTokenKey, value: refresh)
        }

        try await fetchUserEmail()
    }

    private func fetchUserEmail() async throws {
        guard let token = accessToken else { return }
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let email = json["email"] as? String {
            await MainActor.run {
                self.userEmail = email
            }
            UserDefaults.standard.set(email, forKey: emailKey)
        }
    }

    private func refreshAccessToken() async throws {
        guard let refresh = refreshToken else {
            throw GoogleCalendarError.notAuthenticated
        }

        let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "refresh_token": refresh,
            "client_id": clientId,
            "grant_type": "refresh_token",
        ]
        request.httpBody = body.map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)

        await MainActor.run {
            self.accessToken = tokenResponse.accessToken
        }
        KeychainHelper.save(key: tokenKey, value: tokenResponse.accessToken)
    }

    // MARK: - Calendar Operations

    func createEvent(task: VoiceTask) async throws -> String {
        guard let token = accessToken else {
            throw GoogleCalendarError.notAuthenticated
        }

        let url = URL(string: "\(calendarBaseURL)/calendars/primary/events")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let eventBody = buildEventBody(from: task)
        request.httpBody = try JSONSerialization.data(withJSONObject: eventBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
            try await refreshAccessToken()
            return try await createEvent(task: task)
        }

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw GoogleCalendarError.requestFailed
        }

        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let eventId = json["id"] as? String {
            return eventId
        }

        throw GoogleCalendarError.invalidResponse
    }

    func deleteEvent(eventId: String) async throws {
        guard let token = accessToken else {
            throw GoogleCalendarError.notAuthenticated
        }

        let url = URL(string: "\(calendarBaseURL)/calendars/primary/events/\(eventId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
            try await refreshAccessToken()
            try await deleteEvent(eventId: eventId)
            return
        }
    }

    private func buildEventBody(from task: VoiceTask) -> [String: Any] {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]

        let dateOnlyFormatter = DateFormatter()
        dateOnlyFormatter.dateFormat = "yyyy-MM-dd"

        var event: [String: Any] = [
            "summary": task.title,
        ]

        if let notes = task.notes {
            event["description"] = notes
        }

        if task.isAllDay {
            event["start"] = ["date": dateOnlyFormatter.string(from: task.date)]
            let endDate = task.endDate ?? Calendar.current.date(byAdding: .day, value: 1, to: task.date)!
            event["end"] = ["date": dateOnlyFormatter.string(from: endDate)]
        } else {
            let timeZone = TimeZone.current.identifier
            event["start"] = [
                "dateTime": dateFormatter.string(from: task.date),
                "timeZone": timeZone,
            ]
            let endDate = task.endDate ?? task.date.addingTimeInterval(3600)
            event["end"] = [
                "dateTime": dateFormatter.string(from: endDate),
                "timeZone": timeZone,
            ]
        }

        if task.hasAlarm {
            let reminderMinutes = Int(abs(task.alarmOffset) / 60)
            event["reminders"] = [
                "useDefault": false,
                "overrides": [
                    ["method": "popup", "minutes": reminderMinutes],
                ],
            ]
        }

        return event
    }

    func signOut() {
        accessToken = nil
        refreshToken = nil
        userEmail = nil
        isSignedIn = false
        KeychainHelper.delete(key: tokenKey)
        KeychainHelper.delete(key: refreshTokenKey)
        UserDefaults.standard.removeObject(forKey: emailKey)
    }

    // MARK: - Types

    enum GoogleCalendarError: LocalizedError {
        case notAuthenticated
        case requestFailed
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .notAuthenticated: return "Not signed in to Google. Please sign in first."
            case .requestFailed: return "Failed to create calendar event."
            case .invalidResponse: return "Received an invalid response from Google."
            }
        }
    }

    private struct TokenResponse: Codable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Int?
        let tokenType: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
            case tokenType = "token_type"
        }
    }
}
