//
//  RunwayVideoService.swift
//  MemoriesApp
//

import Foundation

/// Runway API 封装：text_to_image（多图+风格融合）、image_to_video（图→视频），含任务轮询
enum RunwayVideoService {
    private static let baseURL = "https://api.dev.runwayml.com/v1"
    private static let versionHeader = "2024-11-06"
    
    struct Config {
        var apiKey: String
    }
    
    enum Error: Swift.Error {
        case missingAPIKey
        case invalidResponse
        case taskFailed(status: String?, message: String?)
        case network(underlying: Swift.Error)
    }
    
    // MARK: - Text to Image（多图参考 + 文案 → 一张图，用于风格化/融合场景）
    
    /// 生成一张图：referenceImages（1–3 张，可选 tag）+ promptText
    /// - Returns: 生成图片的 URL（Runway 或 HTTPS）
    static func textToImage(
        config: Config,
        referenceImages: [(uri: String, tag: String?)],
        promptText: String,
        model: String = "gen4_image",
        ratio: String = "1280:720"
    ) async throws -> String {
        guard !config.apiKey.isEmpty else { throw Error.missingAPIKey }
        let refs: [[String: Any]] = referenceImages.map { ref in
            var obj: [String: Any] = ["uri": ref.uri]
            if let tag = ref.tag, !tag.isEmpty { obj["tag"] = tag }
            return obj
        }
        let body: [String: Any] = [
            "model": model,
            "promptText": promptText,
            "ratio": ratio,
            "referenceImages": refs
        ]
        let taskId = try await createTask(endpoint: "text_to_image", body: body, config: config)
        let output = try await pollTaskUntilDone(taskId: taskId, config: config)
        guard let first = output.first, first.hasPrefix("http") else { throw Error.invalidResponse }
        return first
    }
    
    // MARK: - Image to Video（一张图 + 文案 → 短视频）
    
    /// 图生视频：promptImage 为 data URI 或 HTTPS URL
    static func imageToVideo(
        config: Config,
        promptImage: String,
        promptText: String,
        model: String = "gen4.5",
        ratio: String = "1280:720",
        duration: Int = 5
    ) async throws -> String {
        guard !config.apiKey.isEmpty else { throw Error.missingAPIKey }
        let body: [String: Any] = [
            "model": model,
            "promptImage": promptImage,
            "promptText": promptText,
            "ratio": ratio,
            "duration": duration
        ]
        let taskId = try await createTask(endpoint: "image_to_video", body: body, config: config)
        let output = try await pollTaskUntilDone(taskId: taskId, config: config)
        guard let first = output.first, first.hasPrefix("http") else { throw Error.invalidResponse }
        return first
    }
    
    // MARK: - 创建任务与轮询
    
    private static func createTask(endpoint: String, body: [String: Any], config: Config) async throws -> String {
        let url = URL(string: "\(baseURL)/\(endpoint)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(versionHeader, forHTTPHeaderField: "X-Runway-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            if let err = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let message = extractMessage(from: err) ?? String(data: data, encoding: .utf8)
                throw Error.taskFailed(status: "HTTP_\((response as? HTTPURLResponse)?.statusCode ?? -1)", message: message)
            }
            throw Error.network(underlying: NSError(domain: "Runway", code: -1, userInfo: [NSLocalizedDescriptionKey: "HTTP error"]))
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let id = json?["id"] as? String else { throw Error.invalidResponse }
        return id
    }
    
    private static func pollTaskUntilDone(taskId: String, config: Config) async throws -> [String] {
        let url = URL(string: "\(baseURL)/tasks/\(taskId)")!
        for _ in 0..<120 {
            var request = URLRequest(url: url)
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue(versionHeader, forHTTPHeaderField: "X-Runway-Version")
            let (data, _) = try await URLSession.shared.data(for: request)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let status = json?["status"] as? String ?? ""
            switch status {
            case "SUCCEEDED":
                if let output = json?["output"] as? [String] { return output }
                if let out = json?["output"] as? String { return [out] }
                throw Error.invalidResponse
            case "FAILED", "CANCELED":
                let message = extractMessage(from: json)
                throw Error.taskFailed(status: status, message: message)
            default:
                break
            }
            try await Task.sleep(nanoseconds: 2_500_000_000)
        }
        throw Error.taskFailed(status: "TIMEOUT", message: "轮询超时")
    }

    private static func extractMessage(from json: [String: Any]?) -> String? {
        guard let json else { return nil }
        if let msg = json["message"] as? String, !msg.isEmpty { return msg }
        if let msg = json["error"] as? String, !msg.isEmpty { return msg }
        if let failure = json["failure"] as? [String: Any] {
            if let msg = failure["message"] as? String, !msg.isEmpty { return msg }
            if let reason = failure["reason"] as? String, !reason.isEmpty { return reason }
            if let code = failure["code"] as? String, !code.isEmpty { return code }
        }
        if let detail = json["detail"] as? String, !detail.isEmpty { return detail }
        if let raw = try? JSONSerialization.data(withJSONObject: json),
           let rawText = String(data: raw, encoding: .utf8),
           !rawText.isEmpty {
            return rawText
        }
        return nil
    }
}
