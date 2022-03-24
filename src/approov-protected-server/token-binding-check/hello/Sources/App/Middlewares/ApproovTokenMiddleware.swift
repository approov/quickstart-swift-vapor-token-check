import Vapor

// Using JWTKit because the JWT package assumes the token has the prefix `Bearer`.
import JWTKit

struct ApproovJWTPayload: JWTPayload {
    // Maps the longer Swift property names to the shortened keys used in the
    // JWT payload.
    enum CodingKeys: String, CodingKey {
        case expiration = "exp"
        case token_binding = "pay"
    }

    var expiration: ExpirationClaim

    var token_binding: String?

    // Run any additional verification logic beyond signature verification here.
    // Since we have an ExpirationClaim, we will call its verify method.
    func verify(using signer: JWTSigner) throws {
        try self.expiration.verifyNotExpired()
    }
}

final class ApproovTokenMiddleware: Middleware {
    public func respond(to request: Request, chainingTo next: Responder) -> EventLoopFuture<Response> {
        let approov_token_claims = verifyApproovToken(in: request)

        if approov_token_claims == nil {
            // You may want to add some logging here
            return request.eventLoop.makeFailedFuture(Abort(.unauthorized))
        }

        if !verifyApproovTokenBinding(in: request, claims: approov_token_claims) {
            // You may want to add some logging here
            return request.eventLoop.makeFailedFuture(Abort(.unauthorized))
        }

        return next.respond(to: request)
    }

    private func verifyApproovToken(in request: Request) -> ApproovJWTPayload? {
        if request.headers["Approov-Token"].isEmpty {
            // You may want to add some logging here
            return nil
        }

        let approov_token = request.headers["Approov-Token"][0]

        // Returns `nil` when the token signature is invalid or has expired.
        return try? request.application.jwt.signers.verify(approov_token, as: ApproovJWTPayload.self)
    }

    private func verifyApproovTokenBinding(in request: Request, claims approov_token_claims: ApproovJWTPayload?) -> Bool {
        if approov_token_claims!.token_binding == nil {
            // You may want to add some logging here
            return false
        }

        if request.headers["Authorization"].isEmpty {
            // You may want to add some logging here
            return false
        }

        let token_binding_header: String = request.headers["Authorization"][0]
        let hash_digest: SHA256Digest = SHA256.hash(data: Data(token_binding_header.utf8))
        let token_binding_header_encoded: String = Data(hash_digest).base64EncodedString()

        if approov_token_claims!.token_binding != token_binding_header_encoded {
            // You may want to add some logging here
            return false
        }

        return true
    }
}
