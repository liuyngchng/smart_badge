import AVFoundation
import Combine
import Foundation

/// 录音状态管理器 — 统筹录音/ASR/总结全流程
/// 对齐 Android: RecordingService.kt
@MainActor
final class RecordingManager: ObservableObject {
    private let container: AppContainer

    // MARK: - 可观察状态

    @Published var isRecording = false
    @Published var transcript: String = ""
    @Published var durationSeconds: TimeInterval = 0
    @Published var phase: RecordingPhase = .idle

    enum RecordingPhase {
        case idle
        case recording
        case stopping
        case generatingSummary
    }

    // MARK: - 内部状态

    private var currentVisitId: UUID?
    private var currentAsrURL: String = ""
    private var currentLlmURL: String = ""
    private var currentLlmKey: String = ""
    private var currentLlmModel: String = "deepseek-v4-pro"
    private var currentLlmPrompt: String?

    private var transcriptBuffer = ""

    private var audioStreamTask: Task<Void, Never>?
    private var asrTask: Task<Void, Never>?
    private var durationTask: Task<Void, Never>?

    private var currentPcmURL: URL?
    private var lastPartialText: String = ""
    private var audioDataWritable: ((Data) -> Void)?
    private var batteryWarningShown = false

    init(container: AppContainer) {
        self.container = container
    }

    // MARK: - 开始录音

    func startRecording(
        visitId: UUID,
        asrURL: String,
        llmURL: String,
        llmKey: String,
        llmModel: String = "deepseek-v4-pro",
        llmPrompt: String? = nil
    ) {
        currentVisitId = visitId
        currentAsrURL = asrURL
        currentLlmURL = llmURL
        currentLlmKey = llmKey
        currentLlmModel = llmModel
        currentLlmPrompt = llmPrompt

        transcriptBuffer = ""
        transcript = ""
        durationSeconds = 0
        batteryWarningShown = false
        isRecording = true
        phase = .recording

        // 时长计时器
        durationTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                durationSeconds += 1

                if durationSeconds >= 3600, !batteryWarningShown {
                    batteryWarningShown = true
                    // 电量提醒 — 实际可通过 UIDevice 获取电量
                }
            }
        }

        // 启动 ASR + 录音 pipeline
        performRecording()
    }

    private func performRecording() {
        let asrURL = currentAsrURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let asrClient = container.asrClient
        let audioCapture = container.audioCapture

        guard !asrURL.isEmpty else {
            Log.recording("ASR URL 为空，跳过连接")
            transcript = "请先在设置中配置 FunASR 服务地址"
            isRecording = false
            phase = .idle
            return
        }

        Log.recording("Connecting to ASR: \(asrURL)")
        let asrStream = asrClient.connect(url: asrURL)

        // 主流程：等待连接 → 握手 → 采集音频（顺序执行，对齐 Android）
        audioStreamTask = Task {
            // 等待 WebSocket 建立连接
            try? await Task.sleep(nanoseconds: 500_000_000)

            // 先发送握手，确保在音频数据之前到达服务端
            asrClient.sendHandshake()
            Log.recording("ASR handshake sent")

            // 然后启动音频采集
            do {
                let stream = try audioCapture.startCapturing()
                for try await audioData in stream {
                    audioDataWritable?(audioData)
                    asrClient.sendAudio(audioData)
                }
            } catch {
                Log.recording("Audio capture error: \(error)")
            }
        }

        // ASR 事件消费（独立 Task，与音频发送并行）
        asrTask = Task {
            for await event in asrStream {
                switch event {
                case .partial(let text):
                    // 去重：检测重叠的增量修正
                    if !lastPartialText.isEmpty {
                        if text.hasPrefix(lastPartialText) {
                            // 新文本是旧文本的扩展，只追加后缀
                            let suffix = String(text.dropFirst(lastPartialText.count))
                            if !suffix.isEmpty {
                                transcriptBuffer += suffix
                            }
                        } else if !lastPartialText.hasPrefix(text) {
                            // 不重叠的增量片段
                            transcriptBuffer += text
                        }
                        // 否则新文本是旧文本的子串（回退修正），忽略
                    } else {
                        transcriptBuffer += text
                    }
                    lastPartialText = text
                    transcript = transcriptBuffer

                case .final(let text):
                    // FunASR 2pass 离线结果返回完整修正文本，替换而非追加
                    transcriptBuffer = text
                    transcript = transcriptBuffer
                    lastPartialText = ""

                case .error(let msg):
                    Log.recording("ASR error: \(msg)")

                case .connected:
                    Log.recording("ASR connected")

                case .disconnected:
                    Log.recording("ASR disconnected")
                }
            }
        }
    }

    /// 提供给外部的原始音频回调（用于写本地文件）
    func onAudioData(_ block: @escaping (Data) -> Void) {
        audioDataWritable = block
    }

    // MARK: - 结束录音

    func stopRecording() {
        phase = .stopping
        durationTask?.cancel()
        container.audioCapture.stop()

        // 发送 ASR 结束信号（触发离线纠错）
        container.asrClient.sendEnd()

        // 立即标记录音结束 → UI 马上返回
        isRecording = false
        phase = .idle

        // 所有收尾工作放到后台执行，不阻塞 UI
        let visitId = currentVisitId
        let pcmURL = currentPcmURL
        let asrURL = currentAsrURL
        let llmURL = currentLlmURL
        let llmKey = currentLlmKey
        let llmModel = currentLlmModel
        let llmPrompt = currentLlmPrompt
        let asrClient = container.asrClient
        let audioStreamT = audioStreamTask
        let asrT = asrTask

        Task.detached(priority: .utility) { [weak self] in
            // 等待 ASR 离线结果（.final 事件在此期间到达）
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            asrClient.disconnect()
            audioStreamT?.cancel()
            asrT?.cancel()

            guard let self else { return }

            // 读取最终转写文本（在 3s 等待之后，确保收到 .final）
            let transcriptText = await MainActor.run { self.transcriptBuffer }

            // 定稿音频文件
            if let visitId, let pcmURL {
                let wavPath = await MainActor.run {
                    self.finalizeAudio(visitId: visitId, pcmURL: pcmURL)
                }
                if let path = wavPath {
                    try? await self.container.visitRepository.updateAudioFilePath(
                        visitId, path: path, endTime: Date()
                    )
                }
            }

            // 保存转写
            let savedText = transcriptText.isBlank
                ? "暂时无法获取转写内容"
                : transcriptText
            let fileURL = await MainActor.run {
                self.saveTranscriptToFile(visitId: visitId!, text: savedText)
            }
            if let visitId {
                try? await self.container.visitRepository.updateTranscript(
                    visitId, text: savedText, filePath: fileURL?.path ?? ""
                )
                try? await self.container.visitRepository.updateTranscriptStatus(
                    visitId,
                    status: savedText == "暂时无法获取转写内容" ? .unavailable : .completed
                )
            }

            // 如果实时转写为空，尝试离线 ASR 重试
            var finalText = savedText
            if savedText == "暂时无法获取转写内容", !asrURL.isEmpty, let visitId {
                try? await self.container.visitRepository.updateTranscriptStatus(visitId, status: .processing)
                if let visit = try? await self.container.visitRepository.getVisit(id: visitId),
                   let audioPath = visit.audioFilePath, !audioPath.isEmpty {
                    let result = await asrClient.processFile(audioFilePath: audioPath, serverUrl: asrURL)
                    if case .success(let text) = result {
                        finalText = text
                        let retryFileURL = await MainActor.run {
                            self.saveTranscriptToFile(visitId: visitId, text: text)
                        }
                        try? await self.container.visitRepository.updateTranscript(
                            visitId, text: text, filePath: retryFileURL?.path ?? ""
                        )
                        try? await self.container.visitRepository.updateTranscriptStatus(visitId, status: .completed)
                    } else {
                        try? await self.container.visitRepository.updateTranscriptStatus(visitId, status: .unavailable)
                    }
                }
            }

            // LLM 总结（5 次重试，不阻塞 UI）—— 只有转写完成才执行
            if finalText != "暂时无法获取转写内容", !llmURL.isEmpty, let visitId {
                try? await self.container.visitRepository.updateSummaryStatus(visitId, status: .processing)

                let delays: [TimeInterval] = [20, 40, 80, 160, 320]
                var summaryResult: Result<VisitSummary, Error> = .failure(LLMError.parseFailed("未开始"))
                for (i, delay) in delays.enumerated() {
                    if i > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
                    let r = await self.container.llmClient.generateSummary(
                        transcript: finalText, apiUrl: llmURL, apiKey: llmKey,
                        model: llmModel, customPrompt: llmPrompt
                    )
                    if case .success = r { summaryResult = r; break }
                }
                if case .success(let summary) = summaryResult {
                    try? await self.container.visitRepository.updateSummary(visitId, summary: summary)
                } else {
                    try? await self.container.visitRepository.updateSummaryStatus(visitId, status: .unavailable)
                }
            }
        }
        currentPcmURL = nil
    }


    // MARK: - 文件管理

    private let fileManager = FileManager.default

    private var audioDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("audio", isDirectory: true)
    }

    func startWritingAudio(visitId: UUID) -> URL {
        let dir = audioDirectory.appendingPathComponent(visitId.uuidString, isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

        let dateString = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let url = dir.appendingPathComponent("\(dateString).pcm")
        fileManager.createFile(atPath: url.path, contents: nil)

        // 设置写入回调
        let fileHandle = try? FileHandle(forWritingTo: url)
        onAudioData { data in
            try? fileHandle?.write(contentsOf: data)
        }

        currentPcmURL = url
        return url
    }

    func finalizeAudio(visitId: UUID, pcmURL: URL) -> String? {
        try? FileHandle(forWritingTo: pcmURL).close()

        let wavURL = pcmURL.deletingPathExtension().appendingPathExtension("wav")
        guard let pcmData = try? Data(contentsOf: pcmURL),
              pcmData.count > 0
        else { return nil }

        let dataSize = Int32(pcmData.count)
        let fileSize = dataSize + 36
        let sampleRate: Int32 = 16_000
        let byteRate: Int32 = sampleRate * 2 // 16-bit mono

        var wav = Data()
        wav.append("RIFF".data(using: .ascii)!)
        wav.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian, Array.init))
        wav.append("WAVE".data(using: .ascii)!)
        wav.append("fmt ".data(using: .ascii)!)
        wav.append(contentsOf: withUnsafeBytes(of: Int32(16).littleEndian, Array.init)) // chunk size
        wav.append(contentsOf: withUnsafeBytes(of: Int16(1).littleEndian, Array.init))  // PCM
        wav.append(contentsOf: withUnsafeBytes(of: Int16(1).littleEndian, Array.init))  // mono
        wav.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian, Array.init))
        wav.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian, Array.init))
        wav.append(contentsOf: withUnsafeBytes(of: Int16(2).littleEndian, Array.init))  // block align
        wav.append(contentsOf: withUnsafeBytes(of: Int16(16).littleEndian, Array.init)) // bits/sample
        wav.append("data".data(using: .ascii)!)
        wav.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian, Array.init))
        wav.append(pcmData)

        try? wav.write(to: wavURL)
        try? fileManager.removeItem(at: pcmURL) // 删除原始 PCM

        return wavURL.path
    }

    private func saveTranscriptToFile(visitId: UUID, text: String) -> URL? {
        guard !text.isEmpty else { return nil }
        let dir = audioDirectory.appendingPathComponent(visitId.uuidString, isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let dateString = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let url = dir.appendingPathComponent("\(dateString).txt")
        try? text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

// MARK: - 日志

enum Log {
    static func recording(_ msg: String) {
        #if DEBUG
        print("[RecordingManager] \(msg)")
        #endif
    }
}

// MARK: - 工具扩展

private extension String {
    var isBlank: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
