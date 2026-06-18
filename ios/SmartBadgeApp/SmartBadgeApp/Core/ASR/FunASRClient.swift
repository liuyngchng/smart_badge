import Foundation

/// FunASR WebSocket 客户端
/// 对齐 Android: FunASRClient.kt
final class FunASRClient {
    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession!
    private var serverUrl: String?
    private var intentionalDisconnect = false
    private var reconnectAttempt = 0

    private let maxReconnectAttempts = 3
    private let reconnectDelays: [TimeInterval] = [2, 4, 8]

    // MARK: - 实时流式连接

    func connect(url: String) -> AsyncStream<ASREvent> {
        serverUrl = url
        intentionalDisconnect = false
        reconnectAttempt = 0
        session = URLSession(configuration: {
            let c = URLSessionConfiguration.default
            c.timeoutIntervalForResource = 0    // 无超时
            return c
        }())

        return AsyncStream { continuation in
            openWebSocket(url: url, continuation: continuation)
        }
    }

    private func openWebSocket(url: String, continuation: AsyncStream<ASREvent>.Continuation) {
        guard let wsUrl = URL(string: url) else {
            continuation.yield(.error("无效的 WebSocket URL"))
            continuation.finish()
            return
        }
        webSocket = session.webSocketTask(with: wsUrl)
        webSocket?.resume()

        // 短暂延迟后发送已连接事件
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
            continuation.yield(.connected)
        }

        receiveLoop(continuation: continuation)
    }

    private func receiveLoop(continuation: AsyncStream<ASREvent>.Continuation) {
        webSocket?.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.parseMessage(text, continuation: continuation)
                case .data:
                    break // 忽略二进制消息
                @unknown default:
                    break
                }
                self.receiveLoop(continuation: continuation)

            case .failure(let error):
                continuation.yield(.error(error.localizedDescription))
                if !self.intentionalDisconnect {
                    self.scheduleReconnect(continuation: continuation)
                } else {
                    continuation.yield(.disconnected)
                    continuation.finish()
                }
            }
        }
    }

    private func parseMessage(_ text: String, continuation: AsyncStream<ASREvent>.Continuation) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        let resultText = json["text"] as? String ?? ""
        let isFinal = json["is_final"] as? Bool ?? false

        guard !resultText.isEmpty else { return }

        if isFinal {
            continuation.yield(.final(resultText))
        } else {
            continuation.yield(.partial(resultText))
        }
    }

    // MARK: - 控制消息

    func sendHandshake(chunkSize: [Int] = [5, 10, 5]) {
        sendJSON([
            "mode": "2pass",
            "chunk_size": chunkSize,
            "wav_name": "streaming",
            "is_speaking": true
        ])
    }

    func sendAudio(_ data: Data) {
        webSocket?.send(.data(data)) { _ in }
    }

    func sendEnd() {
        sendJSON(["is_speaking": false])
    }

    func disconnect() {
        intentionalDisconnect = true
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
    }

    // MARK: - 私有方法

    private func sendJSON(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let text = String(data: data, encoding: .utf8)
        else { return }
        webSocket?.send(.string(text)) { _ in }
    }

    private func scheduleReconnect(continuation: AsyncStream<ASREvent>.Continuation) {
        guard reconnectAttempt < maxReconnectAttempts, let url = serverUrl else { return }
        let delay = reconnectDelays[reconnectAttempt]
        reconnectAttempt += 1

        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.openWebSocket(url: url, continuation: continuation)
        }
    }

    // MARK: - 离线文件处理（带重试）

    func processFile(audioFilePath: String, serverUrl: String, maxRetries: Int = 5) async -> Result<String, Error> {
        let retryDelays: [TimeInterval] = [20, 40, 80, 160, 320]

        for attempt in 0..<maxRetries {
            if attempt > 0 {
                let delay = retryDelays[min(attempt - 1, retryDelays.count - 1)]
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }

            let result = await doProcessFile(audioFilePath: audioFilePath, serverUrl: serverUrl)
            if case .success = result {
                return result
            }
        }

        return .failure(ASRError.allRetriesExhausted)
    }

    private func doProcessFile(audioFilePath: String, serverUrl: String) async -> Result<String, Error> {
        guard let fileHandle = FileHandle(forReadingAtPath: audioFilePath) else {
            return .failure(ASRError.fileNotFound)
        }
        defer { try? fileHandle.close() }

        // 跳过 WAV 头 44 字节
        let wavHeader = try? fileHandle.read(upToCount: 44)
        guard wavHeader?.count == 44 else {
            return .failure(ASRError.invalidWavFile)
        }

        guard let wsUrl = URL(string: serverUrl) else {
            return .failure(ASRError.invalidURL)
        }

        return await withCheckedContinuation { continuation in
            let wsSession = URLSession(configuration: .default)
            let task = wsSession.webSocketTask(with: wsUrl)
            var transcript = ""
            var hasResumed = false

            func finish(_ result: Result<String, Error>) {
                guard !hasResumed else { return }
                hasResumed = true
                task.cancel()
                continuation.resume(returning: result)
            }

            task.resume()

            // 发送握手
            let handshake: [String: Any] = [
                "mode": "offline",
                "wav_name": URL(fileURLWithPath: audioFilePath).lastPathComponent,
                "is_speaking": true
            ]
            if let data = try? JSONSerialization.data(withJSONObject: handshake),
               let text = String(data: data, encoding: .utf8) {
                task.send(.string(text)) { _ in }
            }

            // 分块发送 PCM 数据
            let chunkSize = 64_000
            var offset = 44
            while let chunk = try? fileHandle.read(upToCount: chunkSize), !chunk.isEmpty {
                task.send(.data(chunk)) { _ in }
                offset += chunk.count
                Thread.sleep(forTimeInterval: 0.005)
            }

            // 发送结束
            let endMsg: [String: Any] = ["is_speaking": false]
            if let data = try? JSONSerialization.data(withJSONObject: endMsg),
               let text = String(data: data, encoding: .utf8) {
                task.send(.string(text)) { _ in }
            }

            // 接收结果
            func receive() {
                task.receive { result in
                    switch result {
                    case .success(let message):
                        if case .string(let text) = message {
                            if let data = text.data(using: .utf8),
                               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let t = json["text"] as? String {
                                transcript += t
                            }
                        }
                        receive()
                    case .failure:
                        if transcript.isEmpty {
                            finish(.failure(ASRError.noTranscript))
                        } else {
                            finish(.success(transcript))
                        }
                    }
                }
            }
            receive()
        }
    }
}

// MARK: - 事件与错误

enum ASREvent {
    case connected
    case disconnected
    case partial(String)
    case final(String)
    case error(String)
}

enum ASRError: LocalizedError {
    case fileNotFound
    case invalidURL
    case invalidWavFile
    case noTranscript
    case allRetriesExhausted

    var errorDescription: String? {
        switch self {
        case .fileNotFound: return "音频文件不存在"
        case .invalidURL: return "无效的服务器地址"
        case .invalidWavFile: return "无效的 WAV 文件"
        case .noTranscript: return "未收到转写结果"
        case .allRetriesExhausted: return "所有重试均已失败"
        }
    }
}
