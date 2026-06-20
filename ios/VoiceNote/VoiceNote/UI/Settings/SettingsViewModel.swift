import Combine
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    // MARK: - 编辑中的值
    @Published var asrURL: String
    @Published var llmURL: String
    @Published var llmKey: String
    @Published var llmModel: String

    @Published var saveConfirmed = false
    @Published var validationError: String?

    // MARK: - 连接测试状态
    @Published var wsTestResult: ConnectionTestResult = .idle
    @Published var llmTestResult: ConnectionTestResult = .idle

    /// 已保存的原始值（用于判断是否有修改）
    private var saved: Snapshot

    private struct Snapshot: Equatable {
        var asrURL, llmURL, llmKey, llmModel: String
    }

    /// 版本号 — 用可执行文件的修改时间（即编译时间），格式 20260620.1351
    var appVersion: String {
        guard let execURL = Bundle.main.executableURL,
              let attrs = try? FileManager.default.attributesOfItem(atPath: execURL.path),
              let modDate = attrs[.modificationDate] as? Date
        else { return "unknown" }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyyMMdd.HHmm"
        return fmt.string(from: modDate)
    }

    /// 是否有未保存的修改
    var hasChanges: Bool {
        Snapshot(asrURL: asrURL, llmURL: llmURL, llmKey: llmKey,
                 llmModel: llmModel) != saved
    }

    init() {
        let defaults = UserDefaults.standard
        let a = defaults.string(forKey: "asr_url")    ?? "ws://192.168.1.110:10095"
        let b = defaults.string(forKey: "llm_url")    ?? "https://api.deepseek.com"
        let c = defaults.string(forKey: "llm_key")    ?? ""
        let d = defaults.string(forKey: "llm_model")  ?? "deepseek-v4-pro"

        asrURL = a
        llmURL = b
        llmKey = c
        llmModel = d
        saved = Snapshot(asrURL: a, llmURL: b, llmKey: c, llmModel: d)
    }

    private var saveGeneration = 0

    /// 显式保存；返回 true 表示保存成功（校验通过并已写入）
    @discardableResult
    func save() -> Bool {
        // 校验
        if let error = validate() {
            validationError = error
            return false
        }
        validationError = nil

        let defaults = UserDefaults.standard
        defaults.set(asrURL,   forKey: "asr_url")
        defaults.set(llmURL,   forKey: "llm_url")
        defaults.set(llmKey,   forKey: "llm_key")
        defaults.set(llmModel, forKey: "llm_model")

        saved = Snapshot(asrURL: asrURL, llmURL: llmURL, llmKey: llmKey,
                         llmModel: llmModel)

        // 短暂显示"已保存"，使用代数防止快速多次保存时的闪烁
        let generation = saveGeneration + 1
        saveGeneration = generation
        saveConfirmed = true
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if saveGeneration == generation {
                saveConfirmed = false
            }
        }
        return true
    }

    // MARK: - 输入校验

    /// 校验所有必填字段；返回 nil 表示通过，否则返回错误信息
    func validate() -> String? {
        let trimmed = [
            ("FunASR 地址", asrURL),
            ("LLM API 地址", llmURL),
            ("API Key", llmKey),
            ("模型名称", llmModel),
        ]
        for (name, value) in trimmed {
            if value.trimmingCharacters(in: .whitespaces).isEmpty {
                return "\(name) 不能为空"
            }
        }
        // URL 格式校验
        for (name, value) in [("FunASR 地址", asrURL), ("LLM API 地址", llmURL)] {
            guard let url = URL(string: value.trimmingCharacters(in: .whitespaces)),
                  let scheme = url.scheme,
                  !scheme.isEmpty,
                  url.host != nil
            else {
                return "\(name) 格式不正确"
            }
        }
        return nil
    }

    // MARK: - 连接测试

    func testWebSocket() {
        guard wsTestResult != .testing else { return }
        wsTestResult = .testing
        let url = asrURL
        Task {
            let result = await ConnectionTester.testWebSocket(urlString: url)
            wsTestResult = result
        }
    }

    func testLLM() {
        guard llmTestResult != .testing else { return }
        llmTestResult = .testing
        let url = llmURL
        let key = llmKey
        let model = llmModel
        Task {
            let result = await ConnectionTester.testLLMAPI(baseURL: url, apiKey: key, model: model)
            llmTestResult = result
        }
    }

    var isTesting: Bool {
        wsTestResult == .testing || llmTestResult == .testing
    }

    func test() {
        testWebSocket()
        testLLM()
    }
}
