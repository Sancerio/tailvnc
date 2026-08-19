import Foundation

enum RFBAuthentication: Equatable, Sendable {
    case macAccount(username: String, password: String)
    case vncPassword(String)
}

struct MacCredentials: Codable, Equatable, Sendable {
    let username: String
    let password: String
}
