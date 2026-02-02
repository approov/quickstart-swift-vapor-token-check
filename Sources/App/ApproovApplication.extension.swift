import Crypto
import Foundation
import JWTKit
import NIOConcurrencyHelpers
import Vapor

public typealias ApproovApplication = Application

// Application Bootstrap

public func configure(_ app: Application) throws {
    app.logger.logLevel = .notice
    let port = (Environment.get("PORT") ?? Environment.get("HTTP_PORT"))
        .flatMap(Int.init) ?? 8080
    app.http.server.configuration.port = port

    try app.configureApproov()
    try app.registerApproovRoutes()
}

extension ApproovApplication {
    func configureApproov() throws {
        let secret = try ApproovSecretLoader.load()
        let state = ApproovState()
        let signers = JWTSigners()
        signers.use(.hs256(key: secret))
        storage[ApproovStorageKey.self] = ApproovStorage(secret: secret, state: state, signers: signers)

        middleware.use(ApproovTokenMiddleware())
    }

    func registerApproovRoutes() throws {
        get { req in
            req.application.infoPayload(details: "Approov demo API is running on port \(req.application.http.server.configuration.port).")
        }

        get("approov-state") { req in
            req.application.statePayload()
        }

        post("approov", "enable") { req in
            req.application.approovState.enableApproov()
            return req.application.statePayload()
        }

        post("approov", "disable") { req in
            req.application.approovState.disableApproov()
            return req.application.statePayload()
        }

        post("token-binding", "enable") { req in
            req.application.approovState.setTokenBindingEnabled(true)
            return req.application.statePayload()
        }

        post("token-binding", "disable") { req in
            req.application.approovState.setTokenBindingEnabled(false)
            return req.application.statePayload()
        }

        get("unprotected") { req in
            req.application.infoPayload(details: "Unprotected endpoint '/unprotected'; no Approov checks performed.")
        }

        get("token-check") { req in
            req.application.infoPayload(details: "Protected endpoint '/token-check'; Approov token verified.")
        }

        get("token-binding") { req in
            let authPresent = req.headers.first(name: ApproovHeaders.authorization)?.trimmed.isEmpty == false
            return req.application.infoPayload(
                details: "Protected endpoint '/token-binding'; Approov token binding enforced.",
                authorizationHeaderPresent: authPresent
            )
        }

        get("token-double-binding") { req in
            let authPresent = req.headers.first(name: ApproovHeaders.authorization)?.trimmed.isEmpty == false
            let digestPresent = req.headers.first(name: ApproovHeaders.contentDigest)?.trimmed.isEmpty == false
            return req.application.infoPayload(
                details: "Protected endpoint '/token-double-binding'; dual token binding enforced.",
                authorizationHeaderPresent: authPresent,
                contentDigestHeaderPresent: digestPresent
            )
        }
    }

    struct ApproovJWTPayload: JWTPayload {
        enum CodingKeys: String, CodingKey {
            case expiration = "exp"
            case tokenBinding = "pay"
        }

        let expiration: ExpirationClaim
        let tokenBinding: String?

        func verify(using signer: JWTSigner) throws {
            try expiration.verifyNotExpired()
        }
    }

    func verifyApproovToken(_ rawToken: String) throws -> ApproovJWTPayload {
        try approovStorage.signers.verify(rawToken.trimmed, as: ApproovJWTPayload.self)
    }

    func isTokenBindingValid(_ bindingValue: String, payload: ApproovJWTPayload) -> Bool {
        guard let expected = payload.tokenBinding?.trimmed, !expected.isEmpty else {
            return false
        }
        let digest = SHA256.hash(data: Data(bindingValue.utf8))
        let computed = Data(digest).base64EncodedString()
        if computed == expected {
            return true
        }
        return Base64URL.encode(Data(digest)) == expected
    }

    func bindingValue(from request: Request, requiredHeaders: [HTTPHeaders.Name]) -> String? {
        var parts: [String] = []
        for header in requiredHeaders {
            guard let value = request.headers.first(name: header)?.trimmed, !value.isEmpty else {
                return nil
            }
            parts.append(value)
        }
        return parts.joined()
    }

    func statePayload() -> ApproovStatePayload {
        let snapshot = approovState.snapshot()
        return ApproovStatePayload(
            approovEnabled: snapshot.approovEnabled,
            tokenBindingEnabled: snapshot.tokenBindingEnabled
        )
    }

    func infoPayload(
        details: String,
        authorizationHeaderPresent: Bool? = nil,
        contentDigestHeaderPresent: Bool? = nil
    ) -> ApproovInfoPayload {
        let snapshot = approovState.snapshot()
        return ApproovInfoPayload(
            approovEnabled: snapshot.approovEnabled,
            tokenBindingEnabled: snapshot.tokenBindingEnabled,
            details: details,
            authorizationHeaderPresent: authorizationHeaderPresent,
            contentDigestHeaderPresent: contentDigestHeaderPresent
        )
    }

    var approovState: ApproovState {
        approovStorage.state
    }

    private var approovStorage: ApproovStorage {
        guard let storage = storage[ApproovStorageKey.self] else {
            fatalError("Approov storage not configured. Call configureApproov() before use.")
        }
        return storage
    }
}

// Approov Middleware

struct ApproovTokenMiddleware: Middleware {
    func respond(to request: Request, chainingTo next: Responder) -> EventLoopFuture<Response> {
        guard let requirement = ProtectedRoutes.requirement(for: request.url.path) else {
            return next.respond(to: request)
        }

        let app = request.application
        if !app.approovState.isApproovEnabled {
            return next.respond(to: request)
        }

        guard let rawToken = request.headers.first(name: ApproovHeaders.approovToken)?.trimmed,
              !rawToken.isEmpty else {
            return unauthorizedResponse(on: request)
        }

        do {
            let payload = try app.verifyApproovToken(rawToken)

            if !requirement.bindingHeaders.isEmpty, app.approovState.isTokenBindingEnabled {
                guard let bindingValue = app.bindingValue(from: request, requiredHeaders: requirement.bindingHeaders),
                      app.isTokenBindingValid(bindingValue, payload: payload) else {
                    return unauthorizedResponse(on: request)
                }
            }

            return next.respond(to: request)
        } catch {
            app.logger.debug("Approov token verification failed: \(error)")
            return unauthorizedResponse(on: request)
        }
    }

    private func unauthorizedResponse(on request: Request) -> EventLoopFuture<Response> {
        request.eventLoop.makeSucceededFuture(Response(status: .unauthorized))
    }
}

// Protected Routes

struct ProtectedRouteRequirement: Hashable {
    let path: String
    let bindingHeaders: [HTTPHeaders.Name]
}

enum ProtectedRoutes {
    static let routes: [ProtectedRouteRequirement] = [
        ProtectedRouteRequirement(path: "/token-check", bindingHeaders: []),
        ProtectedRouteRequirement(path: "/token-binding", bindingHeaders: [ApproovHeaders.authorization]),
        ProtectedRouteRequirement(
            path: "/token-double-binding",
            bindingHeaders: [ApproovHeaders.authorization, ApproovHeaders.contentDigest]
        )
    ]

    static func requirement(for path: String) -> ProtectedRouteRequirement? {
        routes.first { $0.path == path }
    }
}

// Approov State

struct ApproovStateSnapshot {
    let approovEnabled: Bool
    let tokenBindingEnabled: Bool
}

final class ApproovState {
    private let lock = NIOLock()
    private var approovEnabled: Bool
    private var tokenBindingEnabled: Bool

    init(approovEnabled: Bool = true, tokenBindingEnabled: Bool = true) {
        self.approovEnabled = approovEnabled
        self.tokenBindingEnabled = tokenBindingEnabled
    }

    var isApproovEnabled: Bool {
        lock.withLock { approovEnabled }
    }

    var isTokenBindingEnabled: Bool {
        lock.withLock { tokenBindingEnabled }
    }

    func enableApproov() {
        lock.withLock {
            approovEnabled = true
            tokenBindingEnabled = true
        }
    }

    func disableApproov() {
        lock.withLock {
            approovEnabled = false
            tokenBindingEnabled = false
        }
    }

    func setTokenBindingEnabled(_ enabled: Bool) {
        lock.withLock {
            tokenBindingEnabled = enabled
        }
    }

    func snapshot() -> ApproovStateSnapshot {
        lock.withLock {
            ApproovStateSnapshot(
                approovEnabled: approovEnabled,
                tokenBindingEnabled: tokenBindingEnabled
            )
        }
    }
}

// Response Payloads

struct ApproovStatePayload: Content {
    let approovEnabled: Bool
    let tokenBindingEnabled: Bool
}

struct ApproovInfoPayload: Content {
    let approovEnabled: Bool
    let tokenBindingEnabled: Bool
    let details: String
    let authorizationHeaderPresent: Bool?
    let contentDigestHeaderPresent: Bool?
}

// Approov Storage

private struct ApproovStorageKey: StorageKey {
    typealias Value = ApproovStorage
}

final class ApproovStorage {
    let secret: Data
    let state: ApproovState
    let signers: JWTSigners

    init(secret: Data, state: ApproovState, signers: JWTSigners) {
        self.secret = secret
        self.state = state
        self.signers = signers
    }
}

enum Base64URL {
    static func encode(_ data: Data) -> String {
        let base64 = data.base64EncodedString()
        return base64
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }
}

// Secret Loading

enum ApproovSecretLoader {
    static func load() throws -> Data {
        guard let rawSecret = Environment.get("APPROOV_BASE64URL_SECRET")?.trimmed,
              !rawSecret.isEmpty else {
            throw Abort(.internalServerError, reason: "Missing value for APPROOV_BASE64URL_SECRET")
        }
        guard let decoded = Base64URL.decode(rawSecret) else {
            throw Abort(.internalServerError, reason: "APPROOV_BASE64URL_SECRET is not valid base64url")
        }
        return decoded
    }
}

enum ApproovHeaders {
    static let approovToken = HTTPHeaders.Name("Approov-Token")
    static let authorization = HTTPHeaders.Name.authorization
    static let contentDigest = HTTPHeaders.Name("Content-Digest")
}

// String Helpers

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}