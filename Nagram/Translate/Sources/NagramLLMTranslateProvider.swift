import Foundation
import NagramSettings
import SwiftSignalKit
import TelegramCore

// MARK: NAGRAM — Configurable LLM translation provider.
func nagramLLMTranslate(text: String, fromLang: String?, toLang: String) -> Signal<(String, [MessageTextEntity])?, TranslationError> {
    let settings = NagramSettings.shared
    let format = settings.translationLLMAPIFormatValue
    let model = settings.translationLLMModelValue
    guard let url = settings.translationLLMTranslationURL() else {
        return .fail(.generic)
    }
    guard !model.isEmpty else {
        return .fail(.generic)
    }

    switch format {
    case .openai:
        return nagramOpenAILLMTranslate(url: url, model: model, apiKey: settings.translationLLMAPIKeyValue, text: text, fromLang: fromLang, toLang: toLang)
    case .anthropic:
        return nagramAnthropicLLMTranslate(url: url, model: model, apiKey: settings.translationLLMAPIKeyValue, text: text, fromLang: fromLang, toLang: toLang)
    }
}

private func nagramLLMSystemPrompt(fromLang: String?, toLang: String) -> String {
    let sourceLanguage = fromLang.flatMap { $0.isEmpty || $0 == "auto" ? nil : $0 } ?? "auto"
    return """
You are a translation engine. Translate the user's text to the target language. Output only the translated text, with no explanation, quotes, markdown, or extra notes. Preserve line breaks and meaning. Source language: \(sourceLanguage). Target language: \(toLang).
"""
}

private func nagramOpenAILLMTranslate(url: URL, model: String, apiKey: String, text: String, fromLang: String?, toLang: String) -> Signal<(String, [MessageTextEntity])?, TranslationError> {
    let body: [String: Any] = [
        "model": model,
        "messages": [
            ["role": "system", "content": nagramLLMSystemPrompt(fromLang: fromLang, toLang: toLang)],
            ["role": "user", "content": text]
        ]
    ]
    guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
        return .fail(.generic)
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.httpBody = bodyData
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if !apiKey.isEmpty {
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    }

    return nagramHTTPRequest(request, provider: .llm)
    |> mapToSignal { data -> Signal<(String, [MessageTextEntity])?, TranslationError> in
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let result = nagramLLMText(fromOpenAIContent: message["content"])
        else {
            return .fail(.generic)
        }
        return nagramLLMTranslatedText(result)
    }
}

private func nagramAnthropicLLMTranslate(url: URL, model: String, apiKey: String, text: String, fromLang: String?, toLang: String) -> Signal<(String, [MessageTextEntity])?, TranslationError> {
    let body: [String: Any] = [
        "model": model,
        "max_tokens": 4096,
        "system": nagramLLMSystemPrompt(fromLang: fromLang, toLang: toLang),
        "messages": [
            ["role": "user", "content": text]
        ]
    ]
    guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
        return .fail(.generic)
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.httpBody = bodyData
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
    if !apiKey.isEmpty {
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
    }

    return nagramHTTPRequest(request, provider: .llm)
    |> mapToSignal { data -> Signal<(String, [MessageTextEntity])?, TranslationError> in
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let parts = object["content"] as? [[String: Any]]
        else {
            return .fail(.generic)
        }
        let result = parts.compactMap { part -> String? in
            guard (part["type"] as? String) == "text" else {
                return nil
            }
            return part["text"] as? String
        }.joined()
        return nagramLLMTranslatedText(result)
    }
}

private func nagramLLMText(fromOpenAIContent content: Any?) -> String? {
    if let text = content as? String {
        return text
    }
    if let parts = content as? [[String: Any]] {
        return parts.compactMap { part in
            return part["text"] as? String
        }.joined()
    }
    return nil
}

private func nagramLLMTranslatedText(_ text: String) -> Signal<(String, [MessageTextEntity])?, TranslationError> {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return .fail(.generic)
    }
    return .single((trimmed, []))
}
