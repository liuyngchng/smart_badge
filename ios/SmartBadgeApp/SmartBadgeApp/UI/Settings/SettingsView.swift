import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    let onBack: () -> Void

    var body: some View {
        Form {
            Section(header: Text("FunASR 语音识别")) {
                TextField("WebSocket 地址", text: $viewModel.asrURL)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
            }

            Section(header: Text("LLM AI 总结")) {
                TextField("API 地址", text: $viewModel.llmURL)
                    .keyboardType(.URL)
                    .autocapitalization(.none)

                SecureField("API Key", text: $viewModel.llmKey)

                TextField("模型名称", text: $viewModel.llmModel)
                    .autocapitalization(.none)
            }

            Section(header: Text("自定义 Prompt（可选）")) {
                ZStack(alignment: .topLeading) {
                    if viewModel.llmPrompt.isEmpty {
                        Text("留空使用默认 Prompt，可自定义总结格式...")
                            .foregroundColor(.secondary.opacity(0.5))
                            .font(.caption)
                            .padding(.top, 8)
                            .padding(.leading, 4)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $viewModel.llmPrompt)
                        .frame(minHeight: 120)
                        .font(.caption)
                }
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
                Button("返回", action: onBack)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("保存") {
                    viewModel.save()
                }
                .disabled(!viewModel.hasChanges)
            }
        }
    }
}
