import Foundation
import os

/// 离线模型下载管理器
/// 从 ModelScope（国内可访问）下载 SenseVoice ONNX 模型（INT8 / FP32）
@MainActor
final class ModelDownloadManager: ObservableObject {
    @Published var downloadProgress: Double = 0
    @Published var downloadState: DownloadState = .idle

    enum DownloadState: Equatable {
        case idle
        case downloading(progress: Double)
        case completed(Date)
        case failed(String)
    }

    // MARK: - 下载任务持有

    private var currentTask: URLSessionDownloadTask?
    private var currentResumeData: Data?
    private var downloadSession: URLSession?

    deinit {
        downloadSession?.invalidateAndCancel()
    }

    // MARK: - 路径

    /// ModelScope 仓库（国内可访问）
    private static let modelScopeRepo = "pengzhendong/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17"
    private static let baseURL = "https://www.modelscope.cn/models/\(modelScopeRepo)/resolve/master"

    /// 模型本地存储根目录
    nonisolated static var modelsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("models/sherpa-onnx-sense-voice", isDirectory: true)
    }

    /// tokens.txt 本地路径（所有模型共享）
    nonisolated static func tokensFilePath() -> URL {
        modelsDirectory.appendingPathComponent("tokens.txt")
    }

    /// 模型文件本地路径
    nonisolated static func modelFilePath(_ quality: ModelQuality) -> URL {
        modelsDirectory.appendingPathComponent(quality.modelFilename)
    }

    // MARK: - 检查模型状态

    /// 检查指定质量的模型是否已下载（模型文件 + tokens.txt 都存在）
    nonisolated static func isModelDownloaded(_ quality: ModelQuality) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: modelFilePath(quality).path)
            && fm.fileExists(atPath: tokensFilePath().path)
    }

    /// 获取当前已下载的最高质量模型（用于 RecordingManager fallback）
    nonisolated static func bestDownloadedQuality() -> ModelQuality? {
        // 优先 FP32，其次 INT8
        if isModelDownloaded(.fp32) { return .fp32 }
        if isModelDownloaded(.int8) { return .int8 }
        return nil
    }

    /// 从 UserDefaults 读取用户偏好的模型质量
    nonisolated static func savedQuality() -> ModelQuality {
        let raw = UserDefaults.standard.string(forKey: "offline_model_quality") ?? "int8"
        return ModelQuality(rawValue: raw) ?? .int8
    }

    /// 获取已下载模型的文件大小
    nonisolated static func downloadedModelSize(_ quality: ModelQuality) -> UInt64 {
        let path = modelFilePath(quality).path
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? UInt64
        else { return 0 }
        return size
    }

    // MARK: - 磁盘空间检查

    /// 检查是否有足够磁盘空间（模型 + 10% 余量）
    nonisolated static func hasSufficientDiskSpace(for quality: ModelQuality) -> Bool {
        let required = Int64(quality.estimatedSizeMB) * 1024 * 1024
        let margin = Int64(Double(required) * 0.1)
        let totalRequired = required + margin

        do {
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let values = try documentsURL.resourceValues(forKeys: [.volumeAvailableCapacityKey])
            guard let available = values.volumeAvailableCapacity, available > 0 else {
                // 无法读取容量时，乐观放行
                return true
            }
            return Int64(available) > totalRequired
        } catch {
            return true // 无法读取时放行
        }
    }

    // MARK: - 下载

    /// 下载模型（模型文件 + tokens.txt），支持断点续传
    func downloadModel(quality: ModelQuality) async throws {
        // 检查磁盘空间
        guard Self.hasSufficientDiskSpace(for: quality) else {
            downloadState = .failed("磁盘空间不足，需要至少 \(quality.estimatedSizeMB) MB")
            throw DownloadError.insufficientDiskSpace
        }

        // 确保目录存在
        try? FileManager.default.createDirectory(at: Self.modelsDirectory,
                                                  withIntermediateDirectories: true)

        // 先下载 tokens.txt（如果已存在则跳过）
        if !FileManager.default.fileExists(atPath: Self.tokensFilePath().path) {
            downloadState = .downloading(progress: 0)
            do {
                try await downloadFile(filename: "tokens.txt", to: Self.tokensFilePath())
            } catch {
                downloadState = .failed("下载 tokens.txt 失败: \(error.localizedDescription)")
                throw error
            }
        }

        // 下载模型文件
        let targetURL = Self.modelFilePath(quality)
        let modelFilename = quality.modelFilename

        downloadState = .downloading(progress: 0)
        do {
            try await downloadModelFile(filename: modelFilename, to: targetURL, quality: quality)
            downloadState = .completed(Date())
            Log.asr("模型下载完成: \(quality.rawValue) (\(Self.downloadedModelSize(quality) / 1_048_576)MB)")
        } catch {
            if error is CancellationError {
                downloadState = .idle
                throw error
            }
            downloadState = .failed(error.localizedDescription)
            throw error
        }
    }

    /// 下载单个文件（小文件 / 无进度需求）
    private func downloadFile(filename: String, to targetURL: URL) async throws {
        guard let url = URL(string: "\(Self.baseURL)/\(filename)") else {
            throw DownloadError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode)
        else {
            throw DownloadError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        try data.write(to: targetURL)
    }

    /// 下载模型文件（大文件，带进度）
    private func downloadModelFile(filename: String, to targetURL: URL, quality: ModelQuality) async throws {
        guard let url = URL(string: "\(Self.baseURL)/\(filename)") else {
            throw DownloadError.invalidURL
        }

        return try await withCheckedThrowingContinuation { continuation in
            let delegate = DownloadDelegate(quality: quality) { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.downloadProgress = progress
                    self?.downloadState = .downloading(progress: progress)
                }
            }

            let session = URLSession(configuration: .default,
                                      delegate: delegate,
                                      delegateQueue: nil)
            self.downloadSession = session

            delegate.onCompletion = { [weak self] result in
                Task { @MainActor [weak self] in
                    self?.downloadSession?.invalidateAndCancel()
                    self?.downloadSession = nil
                    switch result {
                    case .success(let tempURL):
                        // 临时文件仅在 completion handler 内有效，需要立即复制
                        defer { try? FileManager.default.removeItem(at: tempURL) }
                        do {
                            // 如果目标文件已存在，先删除
                            try? FileManager.default.removeItem(at: targetURL)
                            try FileManager.default.copyItem(at: tempURL, to: targetURL)
                            continuation.resume()
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            }

            let task: URLSessionDownloadTask
            if let resumeData = currentResumeData {
                task = session.downloadTask(withResumeData: resumeData)
                currentResumeData = nil
            } else {
                task = session.downloadTask(with: url)
            }
            self.currentTask = task
            task.resume()
        }
    }

    /// 取消当前下载
    func cancelDownload() {
        currentTask?.cancel { [weak self] resumeData in
            Task { @MainActor [weak self] in
                self?.currentResumeData = resumeData
            }
        }
        currentTask = nil
        downloadState = .idle
    }

    // MARK: - 删除

    /// 删除指定质量的模型文件
    func deleteModel(quality: ModelQuality) {
        let modelPath = Self.modelFilePath(quality)
        try? FileManager.default.removeItem(at: modelPath)
        Log.asr("模型已删除: \(quality.rawValue)")
        downloadState = .idle
        downloadProgress = 0

        // 如果另一种质量的模型也不存在，连 tokens.txt 一起清掉
        let otherQuality: ModelQuality = (quality == .int8) ? .fp32 : .int8
        if !Self.isModelDownloaded(otherQuality) {
            try? FileManager.default.removeItem(at: Self.tokensFilePath())
            try? FileManager.default.removeItem(at: Self.modelsDirectory)
            Log.asr("所有模型已清空")
        }
    }
}

// MARK: - 错误

enum DownloadError: LocalizedError {
    case invalidURL
    case httpError(Int)
    case insufficientDiskSpace

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "无效的下载地址"
        case .httpError(let code): return "服务器错误 (HTTP \(code))"
        case .insufficientDiskSpace: return "磁盘空间不足"
        }
    }
}

// MARK: - URLSessionDownloadDelegate

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let quality: ModelQuality
    let onProgress: (Double) -> Void
    var onCompletion: ((Result<URL, Error>) -> Void)?

    init(quality: ModelQuality, onProgress: @escaping (Double) -> Void) {
        self.quality = quality
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        DispatchQueue.main.async { [weak self] in
            self?.onProgress(progress)
        }
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        onCompletion?(.success(location))
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        if let error {
            let nsError = error as NSError
            // 如果是用户取消，不视为错误（由 cancelDownload 处理）
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                return
            }
            onCompletion?(.failure(error))
        }
    }
}
