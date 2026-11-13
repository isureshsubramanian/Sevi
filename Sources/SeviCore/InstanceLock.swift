import Foundation

/// Makes sure only one helper listens per user, and lets `stop` find it.
///
/// The lock is an advisory lock on a file that also holds the holder's process
/// ID. The system drops the lock when the holder exits, however it exits, so a
/// crashed helper never leaves a stale lock behind.
public struct InstanceLock: Sendable {
    private let descriptor: Int32

    /// Takes the lock and records this process's ID. Returns nil when another
    /// process holds it or the file cannot be opened.
    public static func acquire(path: String) -> InstanceLock? {
        let descriptor = open(path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { return nil }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return nil
        }
        let text = Array("\(getpid())\n".utf8)
        guard ftruncate(descriptor, 0) == 0,
              text.withUnsafeBytes({ pwrite(descriptor, $0.baseAddress, $0.count, 0) }) == text.count
        else {
            close(descriptor)
            return nil
        }
        return InstanceLock(descriptor: descriptor)
    }

    /// The process ID of whoever holds the lock, or nil when nobody does.
    public static func holderPID(path: String) -> pid_t? {
        let descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
            flock(descriptor, LOCK_UN)
            return nil
        }
        var buffer = [UInt8](repeating: 0, count: 16)
        let count = buffer.withUnsafeMutableBytes { pread(descriptor, $0.baseAddress, $0.count, 0) }
        guard count > 0 else { return nil }
        let text = String(decoding: buffer[..<count], as: UTF8.self)
        guard let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 1 else {
            return nil
        }
        return pid
    }

    /// Gives the lock up. Exiting the process does the same.
    public func release() {
        close(descriptor)
    }
}
