import SwiftUI

struct DetailView: View {
    @ObservedObject var viewModel: DetailViewModel
    let visitId: UUID
    let onBack: () -> Void

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("加载中...")
            } else if let visit = viewModel.visit {
                content(visit)
            } else {
                Text("记录不存在")
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("拜访详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("返回", action: onBack)
            }
        }
        .onAppear { viewModel.loadVisit(id: visitId) }
    }

    private func content(_ visit: Visit) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 基本信息
                GroupBox(label: Text("基本信息")) {
                    infoRow("客户", visit.clientName)
                    if !visit.clientCompany.isEmpty {
                        infoRow("公司", visit.clientCompany)
                    }
                    if !visit.purpose.isEmpty {
                        infoRow("目的", visit.purpose)
                    }
                    if !visit.participants.isEmpty {
                        infoRow("参与人员", visit.participants.joined(separator: "、"))
                    }
                    infoRow("开始时间", formattedDate(visit.startTime))
                    if let end = visit.endTime {
                        infoRow("结束时间", formattedDate(end))
                        infoRow("时长", AppTheme.formatDuration(end.timeIntervalSince(visit.startTime)))
                    }
                }

                // AI 总结
                if let summary = visit.summary {
                    GroupBox(label: Text("AI 总结")) {
                        if !summary.topics.isEmpty {
                            summarySection("议题", summary.topics, color: .blue)
                        }
                        if !summary.conclusions.isEmpty {
                            summarySection("结论", summary.conclusions, color: .green)
                        }
                        if !summary.todos.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("待办", systemImage: "checklist")
                                    .font(.subheadline)
                                    .foregroundColor(.orange)
                                ForEach(summary.todos) { todo in
                                    HStack {
                                        Text("• \(todo.task)")
                                        if !todo.owner.isEmpty {
                                            Text("(\(todo.owner))")
                                                .foregroundColor(.secondary)
                                                .font(.caption)
                                        }
                                    }
                                }
                            }
                        }
                        if !summary.nextSteps.isEmpty {
                            summarySection("后续", summary.nextSteps, color: .purple)
                        }
                    }
                } else if visit.summaryStatus == .processing {
                    HStack {
                        ProgressView()
                        Text("正在生成总结...")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                } else if visit.summaryStatus == .unavailable {
                    Text("总结生成失败")
                        .foregroundColor(.secondary)
                        .padding()
                }

                // 完整转写
                if let transcript = visit.transcriptText, !transcript.isEmpty {
                    GroupBox(label: Text("完整转写")) {
                        if #available(iOS 15.0, *) {
                            Text(transcript)
                                .font(.body)
                                .textSelection(.enabled)
                        } else {
                            SelectableTextView(text: transcript)
                                .frame(minHeight: 100)
                        }
                    }
                } else if visit.transcriptStatus == .processing {
                    HStack {
                        ProgressView()
                        Text("正在转写...")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }
            }
            .padding()
        }
    }

    // MARK: - iOS 14 日期格式化 (Date.formatted() 仅 iOS 15+)

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.subheadline)
            Spacer()
        }
    }

    private func summarySection(_ title: String, _ items: [String], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: "circle.fill")
                .font(.subheadline)
                .foregroundColor(color)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Text("• \(item)")
                    .font(.subheadline)
                    .padding(.leading, 20)
            }
        }
    }
}

// MARK: - iOS 14 可选文本视图 (UITextView 包装)

private struct SelectableTextView: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.dataDetectorTypes = []
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        textView.text = text
    }
}
