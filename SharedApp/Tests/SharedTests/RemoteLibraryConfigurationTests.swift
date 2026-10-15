import Foundation
import SwiftData
import Testing
@testable import Shared

@MainActor
struct RemoteLibraryConfigurationTests {
    @Test
    func addingAndSwitchingDefaultsPreservesOneDefault() throws {
        let container = try ModelContainer(
            for: RemoteLibraryConfiguration.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let operation = RemoteLibraryConfigurationOperation.live(container: container)
        let first = try operation.addItem(record(name: "First", isDefault: true))
        let second = try operation.addItem(record(name: "Second", isDefault: true))
        #expect(try operation.fetchAll().filter(\.isDefault).map(\.id) == [second.id])

        let updated = try operation.setDefault(first.id)
        #expect(updated.filter(\.isDefault).map(\.id) == [first.id])
        #expect(try operation.fetchDefault()?.id == first.id)

        _ = try operation.updateItem(second)
        #expect(try operation.fetchAll().filter(\.isDefault).map(\.id) == [second.id])
    }

    @Test
    func missingDefaultDoesNotClearTheSavedDefault() throws {
        let container = try ModelContainer(
            for: RemoteLibraryConfiguration.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let operation = RemoteLibraryConfigurationOperation.live(container: container)
        let original = try operation.addItem(record(name: "Original", isDefault: true))
        #expect(throws: RemoteLibraryConfigurationOperation.OperationError.missingRecord) {
            _ = try operation.setDefault(UUID())
        }
        #expect(try operation.fetchDefault()?.id == original.id)
        #expect(try operation.fetchAll().count == 1)
    }

    private func record(name: String, isDefault: Bool) -> RemoteLibraryConfigurationOperation.Record {
        .init(id: UUID(), name: name, url: "https://media.example.com", apiKey: nil,
              isDefault: isDefault, createdAt: .now)
    }
}
