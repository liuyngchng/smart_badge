import SwiftUI

/// 离线 ASR 设置组件 — 模型质量选择 + 下载/删除
/// 嵌入在 SettingsView 中使用
struct OfflineASRSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Section(header: Text("离线模型")) {
            Picker("模型质量", selection: $viewModel.offlineModelQuality) {
                ForEach(ModelQuality.allCases, id: \.self) { quality in
                    Text(quality.displayName).tag(quality)
                }
            }
            .pickerStyle(.menu)

            modelStatusSection
        }
    }

    // MARK: - 模型状态

    @ViewBuilder
    private var modelStatusSection: some View {
        switch viewModel.modelDownloadState {
        case .idle:
            if viewModel.isModelDownloaded {
                modelReadyRow
            } else {
                modelNotDownloadedRow
            }

        case .downloading(let progress):
            downloadingRow(progress)

        case .extracting(let progress):
            extractingRow(progress)

        case .completed:
            modelReadyRow
            // 如果切换了质量，显示下载按钮
            if !viewModel.isModelDownloaded {
                downloadButton
            }

        case .failed(let error):
            downloadFailedRow(error)
        }
    }

    // MARK: - 各状态行

    private var modelReadyRow: some View {
        HStack {
            Label("模型已就绪", systemImage: "checkmark.circle.fill")
                .foregroundColor(.green)
            Spacer()
            Text("\(viewModel.offlineModelQuality.rawValue.uppercased())")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var modelNotDownloadedRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("模型未下载")
                    .font(.subheadline)
            }
            Text("需要 SenseVoice 模型才能离线使用语音识别")
                .font(.caption)
                .foregroundColor(.secondary)
            downloadButton
        }
    }

    private func downloadingRow(_ progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ProgressView()
                Text("下载中...")
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            ProgressView(value: progress)
            Button(action: { viewModel.cancelDownload() }) {
                Text("取消下载").foregroundColor(.red)
            }
            .font(.caption)
        }
    }

    private func extractingRow(_ progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ProgressView()
                Text("解压提取中...")
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            ProgressView(value: progress)
            Text("正在解压并提取模型文件")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private func downloadFailedRow(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                Text("下载失败")
                    .font(.subheadline)
                    .foregroundColor(.red)
            }
            Text(error)
                .font(.caption)
                .foregroundColor(.secondary)
            Button("重试") {
                Task { await viewModel.startDownload() }
            }
            .font(.caption)
        }
    }

    private var downloadButton: some View {
        Button {
            Task { await viewModel.startDownload() }
        } label: {
            Label("下载模型",
                  systemImage: "arrow.down.circle")
        }
        .font(.subheadline)
    }
}
