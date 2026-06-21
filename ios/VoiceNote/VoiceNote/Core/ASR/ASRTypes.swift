import Foundation

/// ASR 模式：在线（FunASR 服务端）或离线（SenseVoice 本地推理）
enum ASRMode: String, CaseIterable, Codable {
    case online = "online"
    case offline = "offline"

    var displayName: String {
        switch self {
        case .online: return "在线 (FunASR)"
        case .offline: return "离线 (SenseVoice)"
        }
    }
}

/// 离线模型质量
enum ModelQuality: String, CaseIterable, Codable {
    case int8 = "int8"
    case fp32 = "fp32"

    /// 预估模型体积（含安全余量），单位 MB
    var estimatedSizeMB: Int {
        switch self {
        case .int8: return 250
        case .fp32: return 920
        }
    }

    var displayName: String {
        switch self {
        case .int8: return "INT8 (~\(estimatedSizeMB)MB)"
        case .fp32: return "FP32 (~\(estimatedSizeMB)MB)"
        }
    }

    /// ONNX 模型文件名
    var modelFilename: String {
        switch self {
        case .int8: return "model.int8.onnx"
        case .fp32: return "model.onnx"
        }
    }
}
