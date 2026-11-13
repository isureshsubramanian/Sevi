import Foundation

/// Where the helper publishes its state.
///
/// Shared invariant with the prompt plugin (`sevi.plugin.zsh`): both sides
/// derive the directory as the per-user temporary folder macOS assigns
/// (`DARWIN_USER_TEMP_DIR`, one trailing slash removed) + `/sevi-<uid>`, and
/// fall back to `$TMPDIR`, then `/tmp`, only if the system gives no answer.
/// `$TMPDIR` is not the first choice because a shell may override it while the
/// app, opened by macOS, never sees that override. Change the rule in both
/// places, or the prompt reads a file nobody writes and shows a stale reading.
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
        let base = userTemporaryDirectory() ?? ProcessInfo.processInfo.environment["TMPDIR"]
        return StatePaths(tmpdir: base, uid: getuid())
    }

    private static func userTemporaryDirectory() -> String? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        let length = confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, buffer.count)
        guard length > 1, length <= buffer.count else { return nil }
        return buffer.withUnsafeBufferPointer { $0.baseAddress.map { String(cString: $0) } }
    }
}
