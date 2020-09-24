import Vapor
import JWT

// configures your application
public func configure(_ app: Application) throws {
    // register the Approov middleware for all routes.
    try registerApproovMiddleware(app)

    // register routes
    try routes(app)
}

private func registerApproovMiddleware(_ app: Application) throws {
    let secret: String = Environment.get("APPROOV_BASE64_SECRET") ?? ""
    let approov_base64_secret: String = secret.trimmingCharacters(in: .whitespacesAndNewlines)

    if approov_base64_secret == "" {
        throw Abort(.internalServerError, reason: "Missing value for the environment variable APPROOV_BASE64_SECRET")
    }

    let approov_secret: Data? = Data(base64Encoded: approov_base64_secret)

    if approov_secret == nil {
        throw Abort(.internalServerError, reason: "The value in APPROOV_BASE64_SECRET env var is not a valid base64 encoded string.")
    }

    app.jwt.signers.use(.hs256(key: approov_secret!))
    app.middleware.use(ApproovTokenMiddleware())
}
