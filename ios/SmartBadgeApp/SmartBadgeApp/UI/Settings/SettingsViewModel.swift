import Combine
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    // MARK: - 编辑中的值
    @Published var asrURL: String
    @Published var llmURL: String
    @Published var llmKey: String
    @Published var llmModel: String
    @Published var llmPrompt: String

    @Published var saveConfirmed = false

    /// 已保存的原始值（用于判断是否有修改）
    private var saved: Snapshot

    private struct Snapshot: Equatable {
        var asrURL, llmURL, llmKey, llmModel, llmPrompt: String
    }

    /// 构建版本号（年月日时分秒）
    var appVersion: String {
        if let url = Bundle.main.url(forResource: "Info", withExtension: "plist"),
           let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let modDate = attrs[.modificationDate] as? Date {
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyyMMddHHmmss"
            return fmt.string(from: modDate)
        }
        return "unknown"
    }

    /// 是否有未保存的修改
    var hasChanges: Bool {
        Snapshot(asrURL: asrURL, llmURL: llmURL, llmKey: llmKey,
                 llmModel: llmModel, llmPrompt: llmPrompt) != saved
    }

    init() {
        let defaults = UserDefaults.standard
        let a = defaults.string(forKey: "asr_url")    ?? "ws://192.168.27.29:10095"
        let b = defaults.string(forKey: "llm_url")    ?? "https://api.deepseek.com"
        let c = defaults.string(forKey: "llm_key")    ?? "sk-0220a5e0d8ff4d39828859be52563df1"
        let d = defaults.string(forKey: "llm_model")  ?? "deepseek-v4-pro"
        let e = defaults.string(forKey: "llm_prompt") ?? ""

        asrURL = a
        llmURL = b
        llmKey = c
        llmModel = d
        llmPrompt = e
        saved = Snapshot(asrURL: a, llmURL: b, llmKey: c, llmModel: d, llmPrompt: e)
    }

    /// 显式保存
    func save() {
        let defaults = UserDefaults.standard
        defaults.set(asrURL,   forKey: "asr_url")
        defaults.set(llmURL,   forKey: "llm_url")
        defaults.set(llmKey,   forKey: "llm_key")
        defaults.set(llmModel, forKey: "llm_model")
        defaults.set(llmPrompt, forKey: "llm_prompt")

        saved = Snapshot(asrURL: asrURL, llmURL: llmURL, llmKey: llmKey,
                         llmModel: llmModel, llmPrompt: llmPrompt)

        // 短暂显示已保存
        saveConfirmed = true
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            saveConfirmed = false
        }
    }
}
