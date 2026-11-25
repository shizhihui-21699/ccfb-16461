import Foundation

public struct URLSessionOTPVerificationClient: OTPVerificationServicing {
    private let endpoint: URL
    private let session: URLSession
    private let additionalHeaders: [String: String]

    public init(
        endpoint: URL,
        session: URLSession = .shared,
        additionalHeaders: [String: String] = [:]
    ) {
        self.endpoint = endpoint
        self.session = session
        self.additionalHeaders = additionalHeaders
    }

    public func verify(
        _ submission: OTPVerificationSubmission
    ) async throws -> OTPVerificationResponse {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        additionalHeaders.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(submission)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw OTPVerificationError.invalidResponse
        }

        do {
            return try JSONDecoder().decode(OTPVerificationResponse.self, from: data)
        } catch {
            throw OTPVerificationError.decodingFailed
        }
    }
}

public enum OTPVerificationError: Error, Equatable {
    case invalidResponse
    case decodingFailed
}
