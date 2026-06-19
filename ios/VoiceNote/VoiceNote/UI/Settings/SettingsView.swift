import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    let onBack: () -> Void

    @State private var showBackAlert = false
    @State private var showValidationAlert = false

    var body: some View {
        Form {
            Section(header: Text("FunASR 语音识别")) {
                TextField("WebSocket 地址", text: $viewModel.asrURL)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
            }

            Section(header: Text("LLM API(OpenAI)")) {
                TextField("API 地址", text: $viewModel.llmURL)
                    .keyboardType(.URL)
                    .autocapitalization(.none)

                SecureField("API Key", text: $viewModel.llmKey)

                TextField("模型名称", text: $viewModel.llmModel)
                    .autocapitalization(.none)
            }

            // MARK: - 连接测试
            Section(header: Text("连接测试")) {
                HStack {
                    Text("FunASR WebSocket")
                        .font(.subheadline)
                    Spacer()
                    Text(viewModel.wsTestResult.message)
                        .font(.caption)
                        .foregroundColor(testResultColor(viewModel.wsTestResult))
                    Image(systemName: testResultIcon(viewModel.wsTestResult))
                        .foregroundColor(testResultColor(viewModel.wsTestResult))
                }

                HStack {
                    Text("LLM API")
                        .font(.subheadline)
                    Spacer()
                    Text(viewModel.llmTestResult.message)
                        .font(.caption)
                        .foregroundColor(testResultColor(viewModel.llmTestResult))
                    Image(systemName: testResultIcon(viewModel.llmTestResult))
                        .foregroundColor(testResultColor(viewModel.llmTestResult))
                }

                Button(action: { viewModel.test() }) {
                    HStack {
                        Text("开始测试")
                            .foregroundColor(viewModel.isTesting ? .secondary : .accentColor)
                        Spacer()
                        if viewModel.isTesting {
                            ProgressView()
                        }
                    }
                }
                .disabled(viewModel.isTesting)
            }

            // 版本号
            Section {
                HStack {
                    Spacer()
                    Text("版本：\(viewModel.appVersion)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }

            // 保存状态提示
            if viewModel.saveConfirmed {
                Section {
                    HStack {
                        Spacer()
                        Label("已保存", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("返回") {
                    if viewModel.hasChanges {
                        showBackAlert = true
                    } else {
                        onBack()
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("保存") {
                    if !viewModel.save() {
                        showValidationAlert = true
                    }
                }
                .disabled(!viewModel.hasChanges)
            }
        }
        .alert(isPresented: $showBackAlert) {
            Alert(
                title: Text("未保存的修改"),
                message: Text("设置已修改但尚未保存，确定要离开吗？"),
                primaryButton: .destructive(Text("放弃修改")) { onBack() },
                secondaryButton: .cancel(Text("继续编辑"))
            )
        }
        .alert(isPresented: $showValidationAlert) {
            Alert(
                title: Text("保存失败"),
                message: Text(viewModel.validationError ?? "输入有误"),
                dismissButton: .cancel(Text("好"))
            )
        }
    }

    // MARK: - 测试结果辅助

    private func testResultColor(_ result: ConnectionTestResult) -> Color {
        switch result {
        case .idle:     return .secondary
        case .testing:  return .orange
        case .success:  return .green
        case .failure:  return .red
        }
    }

    private func testResultIcon(_ result: ConnectionTestResult) -> String {
        switch result {
        case .idle:     return "minus.circle"
        case .testing:  return "arrow.triangle.2.circlepath"
        case .success:  return "checkmark.circle.fill"
        case .failure:  return "xmark.circle.fill"
        }
    }
}
