import Vapor

struct ResponseBody: Content {
  let message: String
}

func routes(_ app: Application) throws {
    app.get { req -> ResponseBody in
        return ResponseBody(message: "Hello, World!")
    }
}
