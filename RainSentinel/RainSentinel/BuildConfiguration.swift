import Foundation

enum BuildConfiguration {
    static let isDebug: Bool = {
        #if DEBUG
        true
        #else
        false
        #endif
    }()

    static func debugAssert(
        _ condition: @autoclosure () -> Bool,
        _ message: @autoclosure () -> String = { "" }(),
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard isDebug else { return }
        if !condition() {
            assertionFailure(message(), file: file, line: line)
        }
    }
}
