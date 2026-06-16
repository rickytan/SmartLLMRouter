import Foundation

final class HTTPForwardingClient {
    enum Result {
        case success(data: Data, statusCode: Int, headers: [String: String])
        case failure(Error)
    }

    func forwardSync(
        url: URL,
        method: String = "POST",
        headers: [String: String],
        body: Data,
        timeout: TimeInterval
    ) -> Result {
        var resultData: Data?
        var resultStatusCode = 200
        var resultHeaders: [String: String] = [:]
        var forwardErr: Error?
        let group = DispatchGroup()
        group.enter()

        Task {
            do {
                var urlRequest = URLRequest(url: url)
                urlRequest.httpMethod = method
                if !body.isEmpty {
                    urlRequest.httpBody = body
                }
                urlRequest.timeoutInterval = timeout
                for (key, value) in headers {
                    urlRequest.setValue(value, forHTTPHeaderField: key)
                }

                let (responseData, urlResponse) = try await URLSession.shared.data(for: urlRequest)
                let httpResponse = urlResponse as? HTTPURLResponse

                let responseHeaders: [String: String] = (httpResponse?.allHeaderFields ?? [:])
                    .reduce(into: [:]) { dict, pair in
                        if let key = pair.key as? String, let value = pair.value as? String {
                            dict[key] = value
                        }
                    }

                resultData = responseData
                resultStatusCode = httpResponse?.statusCode ?? 200
                resultHeaders = responseHeaders
            } catch {
                forwardErr = error
            }
            group.leave()
        }

        _ = group.wait(timeout: .now() + timeout + 5)

        if let forwardErr {
            return .failure(forwardErr)
        }

        guard let data = resultData else {
            return .failure(NSError(
                domain: "HTTPForwardingClient",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No response data"]
            ))
        }

        return .success(data: data, statusCode: resultStatusCode, headers: resultHeaders)
    }
}
