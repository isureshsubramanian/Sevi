import Foundation

/// The terminal sessions that currently want Sevi to listen.
///
/// Shared invariant with the prompt plugin (`sevi.plugin.zsh`,
/// `_sevi_register_session`): each interactive shell creates an empty file
/// named after its process ID in `<state directory>/sessions` when the plugin
/// loads and removes it when the shell exits. The helper listens only while at
/// least one of those shells is alive. Change the directory or the naming on
/// both sides together.
public struct SessionRegistry: Sendable {
    public let directory: String

    public init(paths: StatePaths) {
        directory = paths.directory + "/sessions"
    }

    /// Counts the sessions whose shell is still running and removes the files
    /// of those that are gone.
    ///
    /// A shell that was killed leaves its file behind, and its process ID may
    /// later be given to an unrelated program. So a file only counts when the
    /// process with that ID started before the file was last written.
    public func liveSessions(
        processStart: (pid_t) -> Date? = SessionRegistry.processStartTime
    ) -> Int {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
            return 0
        }
        var live = 0
        for name in names {
            // Anything that is not a plain process ID is not ours to judge.
            guard name.utf8.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }),
                  let pid = pid_t(name), pid > 1
            else { continue }

            let path = directory + "/" + name
            var info = stat()
            guard lstat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { continue }
            let written = Date(
                timeIntervalSince1970: Double(info.st_mtimespec.tv_sec)
                    + Double(info.st_mtimespec.tv_nsec) / 1e9
            )

            // One second of slack covers clock granularity between the two stamps.
            if let started = processStart(pid), started <= written.addingTimeInterval(1) {
                live += 1
            } else {
                unlink(path)
            }
        }
        return live
    }

    /// When the process with this ID started, or nil if there is none.
    public static func processStartTime(_ pid: pid_t) -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&name, UInt32(name.count), &info, &size, nil, 0) == 0, size > 0,
              info.kp_proc.p_pid == pid
        else {
            return nil
        }
        let started = info.kp_proc.p_starttime
        return Date(timeIntervalSince1970: Double(started.tv_sec) + Double(started.tv_usec) / 1e6)
    }
}

/// Decides when the helper should stop because nobody is using it.
public struct IdleExit: Sendable {
    /// How long the helper keeps listening after the last session has gone, in
    /// seconds, so that closing one terminal and opening another does not stop
    /// and restart it.
    public let grace: Double
    private var idleSince: Double?

    public init(grace: Double = 30) {
        self.grace = grace
    }

    /// `time` is seconds on any monotonic clock.
    public mutating func shouldExit(liveSessions: Int, at time: Double) -> Bool {
        guard liveSessions <= 0 else {
            idleSince = nil
            return false
        }
        let since = idleSince ?? time
        idleSince = since
        return time - since >= grace
    }
}
