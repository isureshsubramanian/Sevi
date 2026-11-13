import Foundation

/// Publishes snapshots to the state file: directory 0700, file 0600, replaced
/// atomically so a reader sees either the old line or the new one, never a
/// partial write.
///
/// Assumes a single writer per user. Two helpers writing at once would share
/// the temporary file name.
public struct StateFileWriter: Sendable {
    public enum WriteError: Error, Equatable {
        /// The state directory is not a real directory owned by this user.
        case directoryUnsafe
        /// A system call failed; the value is `errno`.
        case io(Int32)
    }

    public let paths: StatePaths

    public init(paths: StatePaths) {
        self.paths = paths
    }

    /// Creates the state directory if needed and refuses one that is a symlink,
    /// not a directory, or owned by someone else (possible when `TMPDIR` is a
    /// shared location such as `/tmp`).
    public func prepareDirectory() throws(WriteError) {
        if mkdir(paths.directory, 0o700) != 0, errno != EEXIST {
            throw .io(errno)
        }
        var info = stat()
        guard lstat(paths.directory, &info) == 0 else {
            throw .io(errno)
        }
        guard (info.st_mode & S_IFMT) == S_IFDIR, info.st_uid == getuid() else {
            throw .directoryUnsafe
        }
        if (info.st_mode & 0o777) != 0o700, chmod(paths.directory, 0o700) != 0 {
            throw .io(errno)
        }
    }

    public func write(_ snapshot: LevelsSnapshot) throws(WriteError) {
        let temporary = paths.directory + "/levels.tmp"
        let descriptor = open(
            temporary,
            O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW | O_CLOEXEC,
            0o600
        )
        guard descriptor >= 0 else {
            throw .io(errno)
        }

        var failure: Int32?
        if fchmod(descriptor, 0o600) != 0 {
            failure = errno
        }
        if failure == nil {
            failure = Self.writeAll(Array(snapshot.stateLine.utf8), to: descriptor)
        }
        if close(descriptor) != 0, failure == nil {
            failure = errno
        }
        if failure == nil, rename(temporary, paths.levelsFile) != 0 {
            failure = errno
        }
        if let failure {
            unlink(temporary)
            throw .io(failure)
        }
    }

    /// Returns `errno` on failure, nil on success.
    private static func writeAll(_ bytes: [UInt8], to descriptor: Int32) -> Int32? {
        var offset = 0
        while offset < bytes.count {
            let written = bytes[offset...].withUnsafeBytes {
                Darwin.write(descriptor, $0.baseAddress, $0.count)
            }
            if written < 0 {
                if errno == EINTR { continue }
                return errno
            }
            offset += written
        }
        return nil
    }
}
