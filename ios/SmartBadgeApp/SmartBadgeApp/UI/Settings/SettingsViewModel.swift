import Combine
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var asrURL: String {
        didSet { save() }
    }
    @Published var llmURL: String {
        didSet { save() }
    }
    @Published var llmKey: String {
        didSet { save() }
    }
    @Published var llmModel: String {
        didSet { save() }
    }
    @Published var llmPrompt: String {
        didSet { save() }
    }

    init() {
        let defaults = UserDefaults.standard
        asrURL = defaults.string(forKey: "asr_url") ?? ""
        llmURL = defaults.string(forKey: "llm_url") ?? ""
        llmKey = defaults.string(forKey: "llm_key") ?? ""
        llmModel = defaults.string(forKey: "llm_model") ?? "gpt-4o-mini"
        llmPrompt = defaults.string(forKey: "llm_prompt") ?? ""
    }

    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(asrURL, forKey: "asr_url")
        defaults.set(llmURL, forKey: "llm_url")
        defaults.set(llmKey, forKey: "llm_key")
        defaults.set(llmModel, forKey: "llm_model")
        defaults.set(llmPrompt, forKey: "llm_prompt")
    }
}
