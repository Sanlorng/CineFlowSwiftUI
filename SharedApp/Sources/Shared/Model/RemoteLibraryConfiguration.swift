//
//  RemoteLibraryConfiguration.swift
//  CineFlowPackage
//
//  Created by sanlorng char on 2025/10/14.
//

import Foundation
import SwiftData
import Dependencies

@Model
final class RemoteLibraryConfiguration: Equatable, Identifiable {
    @Attribute(.unique) var id: UUID
    var name: String
    var url: String
    var apiKey: String?
    var isDefault: Bool
    var createdAt: Date

    init(id: UUID = UUID(), name: String, url: String, apiKey: String? = nil, isDefault: Bool = false, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.url = url
        self.apiKey = apiKey
        self.isDefault = isDefault
        self.createdAt = createdAt
    }

    static func == (lhs: RemoteLibraryConfiguration, rhs: RemoteLibraryConfiguration) -> Bool {
        return lhs.id == rhs.id
    }
}

struct RemoteLibraryConfigurationOperation {
    struct Record: Equatable, Identifiable, Sendable {
        var id: UUID
        var name: String
        var url: String
        var apiKey: String?
        var isDefault: Bool
        var createdAt: Date
        
        init(id: UUID, name: String, url: String, apiKey: String?, isDefault: Bool, createdAt: Date) {
            self.id = id
            self.name = name
            self.url = url
            self.apiKey = apiKey
            self.isDefault = isDefault
            self.createdAt = createdAt
        }
        
        init(model: RemoteLibraryConfiguration) {
            self.init(
                id: model.id,
                name: model.name,
                url: model.url,
                apiKey: model.apiKey,
                isDefault: model.isDefault,
                createdAt: model.createdAt
            )
        }
        
        func apply(to model: RemoteLibraryConfiguration) {
            model.name = name
            model.url = url
            model.apiKey = apiKey
            model.isDefault = isDefault
            model.createdAt = createdAt
        }
    }
    
    var addItem: @MainActor (Record) throws -> Record
    var updateItem: @MainActor (Record) throws -> Record
    var deleteItem: @MainActor (UUID) throws -> Void
    var fetchAll: @MainActor () throws -> [Record]
    var fetchDefault: @MainActor () throws -> Record?
}

extension RemoteLibraryConfigurationOperation {
    static func live(container: ModelContainer) -> Self {
        Self(
            addItem: { record in
                let context = ModelContext(container)
                let model = RemoteLibraryConfiguration(
                    id: record.id,
                    name: record.name,
                    url: record.url,
                    apiKey: record.apiKey,
                    isDefault: record.isDefault,
                    createdAt: record.createdAt
                )
                context.insert(model)
                try context.save()
                return Record(model: model)
            },
            updateItem: { record in
                let context = ModelContext(container)
                let descriptor = FetchDescriptor<RemoteLibraryConfiguration>()
                let items = try context.fetch(descriptor)
                if let existing = items.first(where: { $0.id == record.id }) {
                    record.apply(to: existing)
                    try context.save()
                }
                return record
            },
            deleteItem: { id in
                let context = ModelContext(container)
                let descriptor = FetchDescriptor<RemoteLibraryConfiguration>()
                let items = try context.fetch(descriptor)
                if let existing = items.first(where: { $0.id == id }) {
                    context.delete(existing)
                    try context.save()
                }
            },
            fetchAll: {
                let context = ModelContext(container)
                let descriptor = FetchDescriptor<RemoteLibraryConfiguration>(sortBy: [SortDescriptor(\.createdAt)])
                let items = try context.fetch(descriptor)
                return items.map(Record.init(model:))
            },
            fetchDefault: {
                let context = ModelContext(container)
                let descriptor = FetchDescriptor<RemoteLibraryConfiguration>(sortBy: [SortDescriptor(\.createdAt)])
                let items = try context.fetch(descriptor)
                return items.first(where: { $0.isDefault }).map(Record.init(model:))
            }
        )
    }
}

extension RemoteLibraryConfigurationOperation: DependencyKey {
    static var liveValue: Self {
        fatalError("RemoteLibraryConfigurationOperation dependency must be provided at runtime.")
    }
}

extension RemoteLibraryConfigurationOperation: @unchecked Sendable {}

extension DependencyValues {
    var remoteLibraryConfigurationOperation: RemoteLibraryConfigurationOperation {
        get { self[RemoteLibraryConfigurationOperation.self] }
        set { self[RemoteLibraryConfigurationOperation.self] = newValue }
    }
}
