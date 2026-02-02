import App
import Vapor

@main
struct Run {
    static func main() async throws {
        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)
        let app = try await Application.make(env)
        do {
            try configure(app)
            try await app.execute()
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }
}
