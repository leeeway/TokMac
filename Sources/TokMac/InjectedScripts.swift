import Foundation

enum InjectedScripts {
    static let keyboardAndNavigationJS: String = {
        let bundle = Bundle.main.resourceURL.flatMap {
            Bundle(url: $0.appendingPathComponent("TokMac_TokMac.bundle"))
        } ?? Bundle.module
        guard let url = bundle.url(forResource: "tokmac", withExtension: "js"),
              let script = try? String(contentsOf: url, encoding: .utf8) else {
            preconditionFailure("Missing bundled tokmac.js")
        }
        return script
    }()
}
