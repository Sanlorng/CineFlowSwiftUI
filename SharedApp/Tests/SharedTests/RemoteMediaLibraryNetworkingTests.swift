import Foundation
import OpenAPIRuntime
import Testing
@testable import Shared

struct RemoteMediaLibraryNetworkingTests {
    @Test
    func wrappedOfflineErrorProvidesLocalNetworkGuidance() async throws {
        let transportError = URLError(.notConnectedToInternet)
        let clientError = ClientError(
            operationID: "getWelcomeMessage",
            operationInput: (),
            causeDescription: "Transport threw an error.",
            underlyingError: transportError
        )

        do {
            _ = try await TestAPIClient().fetch { () async throws -> TestAPIOutput in
                throw clientError
            }
            Issue.record("Expected the transport error to be reported")
        } catch let error as APIError {
            #expect(error == .networkError(underlyingError: transportError as NSError))
            let message = RemoteMediaLibraryNetworking.validationErrorMessage(for: error)
            #expect(message.contains("本地网络"))
            #expect(message.contains("CineFlow"))
            #expect(!message.contains("getWelcomeMessage"))
        }
    }

    @Test
    func connectionTimeoutExplainsPermissionAndServerChecks() {
        let error = APIError.networkError(underlyingError: URLError(.timedOut) as NSError)
        let message = RemoteMediaLibraryNetworking.validationErrorMessage(for: error)
        #expect(message.contains("超时"))
        #expect(message.contains("本地网络"))
        #expect(message.contains("端口"))
    }

    @Test
    func serverConnectionFailureExplainsAddressChecks() {
        let error = APIError.networkError(underlyingError: URLError(.cannotConnectToHost) as NSError)
        let message = RemoteMediaLibraryNetworking.validationErrorMessage(for: error)
        #expect(message.contains("地址和端口"))
        #expect(!message.contains("本地网络"))
    }

    @Test
    func authenticationErrorsKeepTheirExistingDescription() {
        #expect(
            RemoteMediaLibraryNetworking.validationErrorMessage(for: APIError.unauthorized)
                == APIError.unauthorized.localizedDescription
        )
    }
}

private struct TestAPIClient: BaseAPIProtocol {}

private struct TestAPIOutput: SuccessExtractable {
    var successModel: Bool? { true }
}
