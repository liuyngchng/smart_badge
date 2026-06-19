import Combine
import Foundation

@MainActor
final class DetailViewModel: ObservableObject {
    @Published var visit: Visit?
    @Published var isLoading = true

    @Published var audioPlayer = AudioPlayer()

    private let container: AppContainer
    private var cancellables = Set<AnyCancellable>()
    private var refreshTimer: AnyCancellable?
    private var currentVisitId: UUID?

    init(container: AppContainer) {
        self.container = container
        audioPlayer.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    func loadVisit(id: UUID) {
        currentVisitId = id
        refresh()
    }

    private func refresh() {
        guard let id = currentVisitId else { return }
        Task {
            let result = try? await container.visitRepository.getVisit(id: id)
            await MainActor.run {
                visit = result
                isLoading = false
                loadAudioIfNeeded()
                scheduleNextRefreshIfNeeded()
            }
        }
    }

    /// 如果转写或总结还在处理中，定时刷新
    private func scheduleNextRefreshIfNeeded() {
        refreshTimer?.cancel()
        guard let visit else { return }

        let needsRefresh = visit.transcriptStatus == .processing
            || visit.summaryStatus == .processing
            || visit.transcriptStatus == .pending

        if needsRefresh {
            refreshTimer = Timer.publish(every: 2, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in
                    self?.refresh()
                }
        }
    }

    /// 加载音频文件到播放器
    private func loadAudioIfNeeded() {
        guard let path = visit?.audioFilePath, !path.isEmpty else { return }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else { return }
        audioPlayer.load(url: url)
    }

    /// 格式化时长 (mm:ss)
    func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "00:00" }
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%02d:%02d", m, s)
    }
}
