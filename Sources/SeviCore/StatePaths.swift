import Foundation

/// Where the helper publishes its state.
///
/// Shared invariant with the prompt plugin (`sevi.plugin.zsh`): both sides
/// derive the directory as `$TMPDIR` (one trailing slash removed, `/tmp` when
/// unset or empty) + `/sevi-<uid>`. Change the rule in both places, or the
/// prompt reads a file nobody writes and shows a stale reading.
public struct StatePaths: Equatable, Sendable {
    public let directory: String

    public var levelsFile: String { directory + "/levels" }
    public var lockFile: String { directory + "/lock" }

    public init(tmpdir: String?, uid: uid_t) {
        var base = tmpdir.flatMap { $0.isEmpty ? nil : $0 } ?? "/tmp"
        if base.hasSuffix("/") {
            base.removeLast()
        }
        directory = base + "/sevi-\(uid)"
    }

    public static func current() -> StatePaths {
        StatePaths(tmpdir: ProcessInfo.processInfo.environment["TMPDIR"], uid: getuid())
    }
}
