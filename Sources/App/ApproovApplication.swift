import Crypto
import Foundation
import JWTKit
import Logging
import NIOConcurrencyHelpers
import Vapor

public typealias ApproovApplication = Application

// Application Bootstrap

public func configure(_ app: Application) throws {
  app.logger.logLevel = .notice
  let port =
    (Environment.get("PORT") ?? Environment.get("HTTP_PORT"))
    .flatMap(Int.init) ?? 8080
  app.http.server.configuration.port = port

  try app.configureApproov()
  try app.registerApproovRoutes()
}

extension ApproovApplication {
  func configureApproov() throws {
    let secret = try ApproovSecretLoader.load(logger: logger)
    let state = ApproovState()
    let signers = JWTSigners()
    signers.use(.hs256(key: secret))
    storage[ApproovStorageKey.self] = ApproovStorage(secret: secret, state: state, signers: signers)

    middleware.use(ApproovTokenMiddleware())
  }

  func registerApproovRoutes() throws {
    get { req in
      req.application.infoPayload(
        details:
          "Approov demo API is running on port \(req.application.http.server.configuration.port).")
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
      req.application.infoPayload(
        details: "Unprotected endpoint '/unprotected'; no Approov checks performed.")
    }

    get("token-check") { req in
      req.application.infoPayload(
        details: "Protected endpoint '/token-check'; Approov token verified.")
    }

    get("token-binding") { req in
      let authPresent =
        req.headers.first(name: ApproovHeaders.authorization)?.trimmed.isEmpty == false
      return req.application.infoPayload(
        details: "Protected endpoint '/token-binding'; Approov token binding enforced.",
        authorizationHeaderPresent: authPresent
      )
    }

    get("token-double-binding") { req in
      let authPresent =
        req.headers.first(name: ApproovHeaders.authorization)?.trimmed.isEmpty == false
      let sessionIdPresent =
        req.headers.first(name: ApproovHeaders.sessionId)?.trimmed.isEmpty == false
      return req.application.infoPayload(
        details: "Protected endpoint '/token-double-binding'; dual token binding enforced.",
        authorizationHeaderPresent: authPresent,
        sessionIdHeaderPresent: sessionIdPresent
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
    return timingSafeEquals(computed, expected)
  }

  private func timingSafeEquals(_ lhs: String, _ rhs: String) -> Bool {
    let lhsBytes = Array(lhs.utf8)
    let rhsBytes = Array(rhs.utf8)
    guard lhsBytes.count == rhsBytes.count else {
      return false
    }

    var difference: UInt8 = 0
    for index in lhsBytes.indices {
      difference |= lhsBytes[index] ^ rhsBytes[index]
    }
    return difference == 0
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
    sessionIdHeaderPresent: Bool? = nil
  ) -> ApproovInfoPayload {
    let snapshot = approovState.snapshot()
    return ApproovInfoPayload(
      approovEnabled: snapshot.approovEnabled,
      tokenBindingEnabled: snapshot.tokenBindingEnabled,
      details: details,
      authorizationHeaderPresent: authorizationHeaderPresent,
      sessionIdHeaderPresent: sessionIdHeaderPresent
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
    let snapshot = app.approovState.snapshot()
    let requiredHeaders = requiredHeaders(for: requirement, state: snapshot)

    if !snapshot.approovEnabled {
      return next.respond(to: request).map { response in
        self.logCompletion(
          request: request,
          response: response,
          summary: "approov_disabled",
          requiredHeaders: requiredHeaders,
          state: snapshot,
          error: nil
        )
        return response
      }
    }

    guard let rawToken = request.headers.first(name: ApproovHeaders.approovToken)?.trimmed,
      !rawToken.isEmpty
    else {
      return unauthorizedResponse(
        on: request,
        summary: "approov_failed:missing_approov_token",
        requiredHeaders: requiredHeaders,
        state: snapshot,
        error: nil
      )
    }

    do {
      let payload = try app.verifyApproovToken(rawToken)

      if snapshot.tokenBindingEnabled, !requirement.bindingHeaders.isEmpty {
        guard
          let bindingValue = app.bindingValue(
            from: request, requiredHeaders: requirement.bindingHeaders)
        else {
          return unauthorizedResponse(
            on: request,
            summary: "approov_failed:missing_binding_header",
            requiredHeaders: requiredHeaders,
            state: snapshot,
            error: nil
          )
        }
        guard app.isTokenBindingValid(bindingValue, payload: payload) else {
          return unauthorizedResponse(
            on: request,
            summary: "approov_failed:binding_mismatch",
            requiredHeaders: requiredHeaders,
            state: snapshot,
            error: nil
          )
        }
      }

      return next.respond(to: request).map { response in
        let summary = response.status == .unauthorized ? "downstream_unauthorized" : "approov_ok"
        self.logCompletion(
          request: request,
          response: response,
          summary: summary,
          requiredHeaders: requiredHeaders,
          state: snapshot,
          error: nil
        )
        return response
      }
    } catch {
      return unauthorizedResponse(
        on: request,
        summary: "approov_failed:token_verification_failed",
        requiredHeaders: requiredHeaders,
        state: snapshot,
        error: error
      )
    }
  }

  private func requiredHeaders(
    for requirement: ProtectedRouteRequirement,
    state: ApproovStateSnapshot
  ) -> [HTTPHeaders.Name] {
    guard state.approovEnabled else {
      return []
    }
    var headers: [HTTPHeaders.Name] = [ApproovHeaders.approovToken]
    if state.tokenBindingEnabled {
      headers.append(contentsOf: requirement.bindingHeaders)
    }
    return headers
  }

  private func unauthorizedResponse(
    on request: Request,
    summary: String,
    requiredHeaders: [HTTPHeaders.Name],
    state: ApproovStateSnapshot,
    error: Error?
  ) -> EventLoopFuture<Response> {
    let response = Response(status: .unauthorized)
    logCompletion(
      request: request,
      response: response,
      summary: summary,
      requiredHeaders: requiredHeaders,
      state: state,
      error: error
    )
    return request.eventLoop.makeSucceededFuture(response)
  }

  private func logCompletion(
    request: Request,
    response: Response,
    summary: String,
    requiredHeaders: [HTTPHeaders.Name],
    state: ApproovStateSnapshot,
    error: Error?
  ) {
    guard response.status == .ok || response.status == .unauthorized else {
      return
    }

    let ipAddress = request.remoteAddress?.ipAddress ?? "unknown"
    let port = request.application.http.server.configuration.port
    var metadata: Logger.Metadata = [
      "summary": .string(summary),
      "method": .string(request.method.rawValue),
      "path": .string(request.url.path),
      "status": .string("\(response.status.code)"),
      "ip": .string(ipAddress),
      "port": .string("\(port)"),
      "approovEnabled": .string("\(state.approovEnabled)"),
      "tokenBindingEnabled": .string("\(state.tokenBindingEnabled)"),
    ]

    if !requiredHeaders.isEmpty {
      let headerValues = requiredHeaders.map { Logger.MetadataValue.string($0.description) }
      metadata["required_headers"] = .array(headerValues)
    }
    if let error {
      metadata["error"] = .string(String(describing: error))
    }

    if response.status == .unauthorized {
      request.logger.warning("http.request.completed", metadata: metadata)
    } else {
      request.logger.notice("http.request.completed", metadata: metadata)
    }
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
    ProtectedRouteRequirement(
      path: "/token-binding", bindingHeaders: [ApproovHeaders.authorization]),
    ProtectedRouteRequirement(
      path: "/token-double-binding",
      bindingHeaders: [ApproovHeaders.authorization, ApproovHeaders.sessionId]
    ),
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
  let sessionIdHeaderPresent: Bool?
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
    return
      base64
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }

  static func decode(_ value: String) -> Data? {
    var base64 =
      value
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
  static func load(logger: Logger) throws -> Data {
    guard let rawSecret = Environment.get("APPROOV_BASE64URL_SECRET")?.trimmed,
      !rawSecret.isEmpty,
      rawSecret != "approov_base64url_secret_here"
    else {
      logger.error("Required secret is not set")
      throw Abort(.internalServerError, reason: "Required secret is not set")
    }
    guard let decoded = Base64URL.decode(rawSecret) else {
      logger.error("Required secret is invalid")
      throw Abort(.internalServerError, reason: "Required secret is invalid")
    }
    return decoded
  }
}

enum ApproovHeaders {
  static let approovToken = HTTPHeaders.Name("Approov-Token")
  static let authorization = HTTPHeaders.Name.authorization
  static let sessionId = HTTPHeaders.Name("SessionId")
}

// String Helpers

extension String {
  var trimmed: String {
    trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
