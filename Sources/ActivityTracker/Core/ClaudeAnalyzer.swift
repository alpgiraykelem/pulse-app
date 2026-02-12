import Foundation

enum ClaudeAnalyzer {
    struct Message: Codable {
        let role: String
        let content: String
    }

    struct Request: Codable {
        let model: String
        let max_tokens: Int
        let system: String
        let messages: [Message]
    }

    struct ContentBlock: Codable {
        let text: String?
    }

    struct Response: Codable {
        let content: [ContentBlock]?
        let error: ResponseError?
    }

    struct ResponseError: Codable {
        let message: String
    }

    private static var reportsDir: URL {
        let dir = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("ActivityTracker/reports")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func analyze(timeline: [TimelineEntry], totalSeconds: Int, wallClockSeconds: Int, date: String, completion: @escaping (Result<(text: String, file: URL), Error>) -> Void) {
        guard let apiKey = ConfigManager.claudeApiKey, !apiKey.isEmpty else {
            completion(.failure(AnalyzeError.noApiKey))
            return
        }

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

        let lines = timeline.map { entry -> String in
            let time = timeFormatter.string(from: entry.timestamp)
            let dur = entry.durationSeconds
            let extra = [entry.extraInfo, entry.url].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
            let suffix = extra.isEmpty ? "" : " (\(extra))"
            return "\(time) \(entry.appName): \(entry.windowTitle) [\(dur)s]\(suffix)"
        }

        let timelineText = lines.joined(separator: "\n")

        let system = """
        You are a timesheet grouping tool. Group app usage entries by project/client and sum durations. \
        Identify projects by recurring keywords in window titles, URLs, file paths. \
        Same keyword across different apps = same project. \
        Entries with no match go under "Other". Sort by total time descending. Convert seconds to Xh Ym. \
        Output ONLY the markdown format shown. No commentary, no tips, no analysis, no headers like "Productivity Analysis".
        """

        let user = "Group by project:\n\n\(timelineText)"

        // Assistant prefill forces the model to start with the correct format
        let request = Request(
            model: "claude-haiku-4-5-20251001",
            max_tokens: 2000,
            system: system,
            messages: [
                Message(role: "user", content: user),
                Message(role: "assistant", content: "## Projects")
            ]
        )

        guard let body = try? JSONEncoder().encode(request) else {
            completion(.failure(AnalyzeError.encodingFailed))
            return
        }

        var urlRequest = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.httpBody = body
        urlRequest.timeoutInterval = 60

        URLSession.shared.dataTask(with: urlRequest) { data, _, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(.failure(AnalyzeError.noResponse))
                return
            }

            // Debug: log raw response
            if let raw = String(data: data, encoding: .utf8) {
                let logFile = reportsDir.appendingPathComponent("debug-api.log")
                try? raw.write(to: logFile, atomically: true, encoding: .utf8)
            }

            guard let result = try? JSONDecoder().decode(Response.self, from: data) else {
                completion(.failure(AnalyzeError.decodingFailed))
                return
            }

            if let err = result.error {
                completion(.failure(AnalyzeError.apiError(err.message)))
                return
            }

            // Prepend the prefill since API returns only the continuation
            let continuation = result.content?.compactMap(\.text).joined(separator: "\n") ?? ""
            let text = "## Projects" + continuation

            // Save to file
            let fileName = "analysis-\(date).md"
            let fileURL = reportsDir.appendingPathComponent(fileName)
            try? text.write(to: fileURL, atomically: true, encoding: .utf8)

            completion(.success((text: text, file: fileURL)))
        }.resume()
    }

    enum AnalyzeError: LocalizedError {
        case noApiKey
        case encodingFailed
        case noResponse
        case decodingFailed
        case apiError(String)

        var errorDescription: String? {
            switch self {
            case .noApiKey: return "No API key configured. Set it from the menu bar."
            case .encodingFailed: return "Failed to encode request."
            case .noResponse: return "No response from API."
            case .decodingFailed: return "Failed to decode API response."
            case .apiError(let msg): return "API error: \(msg)"
            }
        }
    }
}
