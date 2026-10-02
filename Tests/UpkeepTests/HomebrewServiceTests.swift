import Foundation
import Testing
@testable import Upkeep

@Test func homebrewServicesDecodeCurrentUserStatusesWithoutInferringUnknownStates() throws {
    let data = Data(#"[{"name":"redis","status":"started","user":"fixture","file":"/fixture/redis.plist","exit_code":0},{"name":"postgresql","status":"error","user":null,"file":null,"exit_code":1},{"name":"future","status":"new-status"}]"#.utf8)
    let services = try JSONDecoder().decode([HomebrewService].self, from: data)
    #expect(services.map(\.isStarted) == [true, false, false])
    #expect(services[1].exitCode == 1)
    #expect(services[2].status == "new-status")
    #expect(services[2].user == nil)
    #expect(try JSONDecoder().decode([HomebrewService].self, from: Data("[]".utf8)).isEmpty)
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode([HomebrewService].self, from: Data(#"[{"name":"missing-status"}]"#.utf8))
    }
}
