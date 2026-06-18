import Combine
import Foundation

@MainActor
final class DetailViewModel: ObservableObject {
    @Published var visit: Visit?
    @Published var isLoading = true

    private let container: AppContainer

    init(container: AppContainer) {
        self.container = container
    }

    func loadVisit(id: UUID) {
        Task {
            let result = try? await container.visitRepository.getVisit(id: id)
            await MainActor.run {
                visit = result
                isLoading = false
            }
        }
    }
}
