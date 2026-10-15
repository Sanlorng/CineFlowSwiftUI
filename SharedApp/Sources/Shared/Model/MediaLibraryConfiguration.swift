import Foundation

struct MediaLibraryConfiguration: Equatable, Identifiable {
    let id: UUID
    var name: String
    var url: String
    var apiToken: String?
    var isDefault: Bool
    var createdAt: Date

    var baseURL: URL? { URL(string: url) }

    init(
        id: UUID,
        name: String,
        url: String,
        apiToken: String?,
        isDefault: Bool,
        createdAt: Date
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.apiToken = apiToken
        self.isDefault = isDefault
        self.createdAt = createdAt
    }

    init(record: RemoteLibraryConfigurationOperation.Record) {
        self.init(
            id: record.id,
            name: record.name,
            url: record.url,
            apiToken: record.apiKey,
            isDefault: record.isDefault,
            createdAt: record.createdAt
        )
    }

}
