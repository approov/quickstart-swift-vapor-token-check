import Vapor

// Using JWTKit because the JWT package assumes the token has the prefix `Bearer`.
import JWTKit

struct ApproovJWTPayload: JWTPayload {
    // Maps the longer Swift property names to the shortened keys used in the
    // JWT payload.
    enum CodingKeys: String, CodingKey {
        case expiration = "exp"
    }

    var expiration: ExpirationClaim

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
}
