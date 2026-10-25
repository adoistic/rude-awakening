import Foundation

public enum OpenRouterError: LocalizedError, Sendable {
    case noKey
    case badKey
    case noCredits
    case rateLimited
    case http(Int, String)
    case emptyResponse
    case unparseable(String)
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .noKey: return "No OpenRouter key yet. Add one in Settings → Brain."
        case .badKey: return "OpenRouter says that key is wrong. Check Settings → Brain."
        case .noCredits: return "Your OpenRouter account is out of credits. I can't think for free."
        case .rateLimited: return "OpenRouter is rate-limiting me. Take a breath and try again."
        case .http(let code, let message): return "OpenRouter had a moment (HTTP \(code)): \(message)"
        case .emptyResponse: return "The model said nothing at all. Rude, even by my standards."
        case .unparseable: return "The model mumbled something I couldn't read. Try rephrasing?"
        case .network(let message): return "Couldn't reach OpenRouter: \(message)"
        }
    }

    /// True when the internet or the service is the problem, so the offline parser should step in.
    public var isConnectivity: Bool {
        switch self {
        case .network, .rateLimited: return true
        case .http(let code, _): return code >= 500
        default: return false
        }
    }
}

public struct OpenRouterClient: Sendable {
    public static let chatURL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    public static let keyURL = URL(string: "https://openrouter.ai/api/v1/key")!
    public static let keysPage = URL(string: "https://openrouter.ai/keys")!

    /// Cheap, quick and good at following a schema. Anything on OpenRouter works.
    public static let defaultModel = "anthropic/claude-haiku-5.5"
    public static let suggestedModels: [(id: String, name: String)] = [
        ("anthropic/claude-haiku-5.5", "Claude Haiku 5.5 (default: fast, pennies)"),
        ("anthropic/claude-sonnet-5.5", "Claude Sonnet 5.5 (smarter, pricier)"),
        ("google/gemini-3.8-flash", "Gemini 3.8 Flash"),
        ("openai/gpt-6-luna", "GPT-6 Luna"),
        ("deepseek/deepseek-v4.1-flash", "DeepSeek V4.1 Flash (cheapest)"),
    ]

    public var apiKey: String
    public var model: String

    public init(apiKey: String, model: String = OpenRouterClient.defaultModel) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Self.defaultModel : model
    }

    /// Sends one sentence and returns the model's plan.
    public func plan(for text: String, systemPrompt: String) async throws -> AlarmPlan {
        do {
            return try await send(text, systemPrompt: systemPrompt, structured: true)
        } catch OpenRouterError.http(let code, let message) where code == 400 && Self.mentionsSchema(message) {
            // Some models refuse structured outputs. The prompt still asks for JSON, so try plain.
            return try await send(text, systemPrompt: systemPrompt, structured: false)
        }
    }

    private func send(_ text: String, systemPrompt: String, structured: Bool) async throws -> AlarmPlan {
        guard !apiKey.isEmpty else { throw OpenRouterError.noKey }

        // No max_tokens on purpose: reasoning models spend a cap on hidden thinking and return nothing.
        let base: [String: Any] = [
            "model": model,
            "temperature": 0.3,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text],
            ],
        ]
        var body = try JSONSerialization.data(withJSONObject: base)
        if structured {
            // Splice the hand-ordered schema in as raw JSON (JSONSerialization would reorder its keys).
            let format = ",\"response_format\":{\"type\":\"json_schema\",\"json_schema\":{\"name\":\"alarm_plan\",\"strict\":true,\"schema\":\(Prompt.schemaJSON())}}}"
            body.removeLast() // the closing brace
            body.append(Data(format.utf8))
        }

        var request = URLRequest(url: Self.chatURL, timeoutInterval: 45)
        request.httpMethod = "POST"
        request.httpBody = body
        applyHeaders(&request)

        let data = try await perform(request)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OpenRouterError.unparseable(String(decoding: data, as: UTF8.self))
        }
        if let error = root["error"] as? [String: Any] {
            let code = (error["code"] as? Int) ?? 0
            throw Self.error(for: code, message: (error["message"] as? String) ?? "unknown error")
        }
        guard let choices = root["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else {
            throw OpenRouterError.emptyResponse
        }
        let content: String
        if let s = message["content"] as? String {
            content = s
        } else if let parts = message["content"] as? [[String: Any]] {
            content = parts.compactMap { $0["text"] as? String }.joined()
        } else {
            content = ""
        }
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw OpenRouterError.emptyResponse }
        return try AlarmPlan.decode(fromModelText: content)
    }

    public struct KeyStatus: Sendable {
        public var label: String?
        public var usage: Double?
        public var limitRemaining: Double?
    }

    /// Checks a key without spending anything.
    public static func check(key: String) async throws -> KeyStatus {
        var request = URLRequest(url: keyURL, timeoutInterval: 20)
        OpenRouterClient(apiKey: key).applyHeaders(&request)
        let data = try await OpenRouterClient(apiKey: key).perform(request)
        let root = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let info = root["data"] as? [String: Any] ?? [:]
        return KeyStatus(
            label: info["label"] as? String,
            usage: info["usage"] as? Double,
            limitRemaining: info["limit_remaining"] as? Double
        )
    }

    private func applyHeaders(_ request: inout URLRequest) {
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // OpenRouter's app attribution headers.
        request.setValue("https://github.com/adoistic/rude-awakening", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Rude Awakening", forHTTPHeaderField: "X-Title")
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw OpenRouterError.network(error.localizedDescription)
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            let root = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            let message = ((root["error"] as? [String: Any])?["message"] as? String)
                ?? String(decoding: data.prefix(300), as: UTF8.self)
            throw Self.error(for: code, message: message)
        }
        return data
    }

    static func error(for code: Int, message: String) -> OpenRouterError {
        switch code {
        case 401, 403: return .badKey
        case 402: return .noCredits
        case 429: return .rateLimited
        default: return .http(code, message)
        }
    }

    static func mentionsSchema(_ message: String) -> Bool {
        let m = message.lowercased()
        return m.contains("response_format") || m.contains("json_schema") || m.contains("structured")
    }
}
