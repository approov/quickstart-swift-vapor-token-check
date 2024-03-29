# Approov Backend Quickstart - Swift Vapor Token Check

[Approov](https://approov.io) is an API security solution used to verify that requests received by your backend services originate from trusted versions of your mobile apps.

This repo implements the Approov server-side request verification code in Swift, with the Vapor framework, which performs the verification check before allowing valid traffic to be processed by the API endpoint.


## Approov Integration Quickstart

The quickstart was tested with the following Operating Systems:

* Ubuntu 20.04
* MacOS Big Sur
* Windows 10 WSL2 - Ubuntu 20.04

First, setup the [Approov CLI](https://approov.io/docs/latest/approov-installation/index.html#initializing-the-approov-cli).

Now, register the API domain for which Approov will issues tokens:

```bash
approov api -add api.example.com
```

> **NOTE:** By default a symmetric key (HS256) is used to sign the Approov token on a valid attestation of the mobile app for each API domain it's added with the Approov CLI, so that all APIs will share the same secret and the backend needs to take care to keep this secret secure.
>
> A more secure alternative is to use asymmetric keys (RS256 or others) that allows for a different keyset to be used on each API domain and for the Approov token to be verified with a public key that can only verify, but not sign, Approov tokens.
>
> To implement the asymmetric key you need to change from using the symmetric HS256 algorithm to an asymmetric algorithm, for example RS256, that requires you to first [add a new key](https://approov.io/docs/latest/approov-usage-documentation/#adding-a-new-key), and then specify it when [adding each API domain](https://approov.io/docs/latest/approov-usage-documentation/#keyset-key-api-addition). Please visit [Managing Key Sets](https://approov.io/docs/latest/approov-usage-documentation/#managing-key-sets) on the Approov documentation for more details.

Next, enable your Approov `admin` role with:

```bash
eval `approov role admin`
````

For the Windows powershell:

```bash
set APPROOV_ROLE=admin:___YOUR_APPROOV_ACCOUNT_NAME_HERE___
````

Now, retrieve the [Approov secret](https://approov.io/docs/latest/approov-usage-documentation/#account-secret-key-export):

```bash
approov secret -get base64
```

Next, add the Approov secret to your project `.env` file:

```env
APPROOV_BASE64_SECRET=approov_base64_secret_here
```

Now, add to your `Package.swift` file the [JWT dependency](https://github.com/vapor/jwt.git):

```swift
.package(url: "https://github.com/vapor/jwt.git", from: "4.0.0"),
```

Next, create the Approov Middleware at `./Sources/App/Middlewares/ApproovTokenMiddleware.swift`:

```swift
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
```

Now, register the Approov middleware in the Vapor application configuration at `./Sources/App/configure.swift`:

```swift
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
```

Not enough details in the bare bones quickstart? No worries, check the [detailed quickstarts](QUICKSTARTS.md) that contain a more comprehensive set of instructions, including how to test the Approov integration.


## More Information

* [Approov Overview](OVERVIEW.md)
* [Detailed Quickstarts](QUICKSTARTS.md)
* [Step by Step Examples](EXAMPLES.md)
* [Testing](TESTING.md)

### System Clock

In order to correctly check for the expiration times of the Approov tokens is very important that the backend server is synchronizing automatically the system clock over the network with an authoritative time source. In Linux this is usually done with a NTP server.


## Issues

If you find any issue while following our instructions then just report it [here](https://github.com/approov/quickstart-swift-vapor-token-check/issues), with the steps to reproduce it, and we will sort it out and/or guide you to the correct path.


## Useful Links

If you wish to explore the Approov solution in more depth, then why not try one of the following links as a jumping off point:

* [Approov Free Trial](https://approov.io/signup)(no credit card needed)
* [Approov Get Started](https://approov.io/product/demo)
* [Approov QuickStarts](https://approov.io/docs/latest/approov-integration-examples/)
* [Approov Docs](https://approov.io/docs)
* [Approov Blog](https://approov.io/blog/)
* [Approov Resources](https://approov.io/resource/)
* [Approov Customer Stories](https://approov.io/customer)
* [Approov Support](https://approov.io/contact)
* [About Us](https://approov.io/company)
* [Contact Us](https://approov.io/contact)
