import Foundation

/// AI 端点配置：~/Library/Application Support/Guiyu/ai-config.json
/// 示例（Kimi）：{"baseURL":"https://api.moonshot.cn/v1","model":"kimi-k3","apiKey":"sk-xxx"}
/// 示例（小米 MiMo Token Plan）：{"baseURL":"https://token-plan-cn.xiaomimimo.com/v1","model":"mimo-v2.6-pro","apiKey":"tp-xxx"}
/// 密钥只存本机文件，不进日志、不上传。
struct AIEndpointConfig: Decodable {
    var baseURL: String
    var model: String
    var apiKey: String
    var timeoutSeconds: Double?
}

enum AIService {
    static let configURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Guiyu/ai-config.json")

    static func loadConfig() -> AIEndpointConfig? {
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(AIEndpointConfig.self, from: data) else { return nil }
        let trimmed = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBase = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmedBase.isEmpty, !config.model.isEmpty else { return nil }
        guard trimmedBase.lowercased().hasPrefix("https://") else { return nil }
        return AIEndpointConfig(baseURL: config.baseURL, model: config.model, apiKey: trimmed, timeoutSeconds: config.timeoutSeconds)
    }

    /// OpenAI 兼容 /chat/completions。MiMo（api-key 头）与 Kimi（Bearer 头）统一带两种认证头。
    static func complete(prompt: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let config = loadConfig() else {
            completion(.failure(localError("未找到 AI 配置。请在 ~/Library/Application Support/Guiyu/ai-config.json 填写 baseURL、model、apiKey。")))
            return
        }
        var base = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base = String(base.dropLast()) }
        guard let url = URL(string: base + "/chat/completions") else {
            completion(.failure(localError("AI 配置的 baseURL 无效。")))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = config.timeoutSeconds ?? 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer " + config.apiKey, forHTTPHeaderField: "Authorization")
        request.setValue(config.apiKey, forHTTPHeaderField: "api-key")
        let body: [String: Any] = [
            "model": config.model,
            "messages": [["role": "user", "content": prompt]],
            "temperature": 0.2,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error { completion(.failure(error)); return }
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                let preview = data.map { String($0.prefix(400)) } ?? ""
                completion(.failure(localError("AI 服务返回 HTTP \(http.statusCode)：\(preview)")))
                return
            }
            guard let data = data else {
                completion(.failure(localError("AI 服务无响应，请稍后重试。")))
                return
            }
            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    completion(.failure(localError("AI 服务返回格式无法识别。")))
                    return
                }
                if let apiError = json["error"] as? [String: Any] {
                    let message = apiError["message"] as? String ?? "未知错误"
                    completion(.failure(localError("AI 服务报错：" + message)))
                    return
                }
                guard let choices = json["choices"] as? [[String: Any]],
                      let message = choices.first?["message"] as? [String: Any],
                      let content = message["content"] as? String, !content.isEmpty else {
                    completion(.failure(localError("AI 服务未返回内容，请重试或更换模型。")))
                    return
                }
                completion(.success(content))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    private static func localError(_ text: String) -> NSError {
        NSError(domain: "Guiyu.AI", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }
}
