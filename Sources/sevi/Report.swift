import AVFoundation
import SeviCore

/// The helper's own identifier, as declared in the app bundle.
private let bundleIdentifier = "com.nerttiyana.sevi"

/// The Sevi.app this command belongs to, also when it was started through a
/// link on the PATH. Nil when it is not inside an app bundle at all.
func appBundle() -> Bundle? {
    let started = Bundle.main.executablePath ?? CommandLine.arguments[0]
    return AppBundle.containing(executable: started).flatMap { Bundle(path: $0) }
}

private struct HelperState {
    var pid: pid_t
    var since: Date?
    var snapshot: LevelsSnapshot?
    var ageSeconds: Double?
    var sessions: Int
}

private func helperState() -> HelperState? {
    let paths = StatePaths.current()
    guard let pid = InstanceLock.holderPID(path: paths.lockFile) else { return nil }

    // The lock file is rewritten when the helper takes the lock, so its
    // modification time is when listening began.
    var info = stat()
    let since = stat(paths.lockFile, &info) == 0
        ? Date(timeIntervalSince1970: Double(info.st_mtimespec.tv_sec))
        : nil

    let snapshot = (try? String(contentsOfFile: paths.levelsFile, encoding: .utf8))
        .flatMap { LevelsSnapshot(stateLine: $0) }
    let age = snapshot.map { Date().timeIntervalSince1970 - Double($0.timestampMs) / 1000 }
    return HelperState(
        pid: pid, since: since, snapshot: snapshot, ageSeconds: age,
        sessions: SessionRegistry(paths: paths).liveSessions()
    )
}

private func clock(_ date: Date?) -> String {
    guard let date else { return "an unknown time" }
    let formatter = DateFormatter()
    formatter.dateStyle = Calendar.current.isDateInToday(date) ? .none : .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
}

private func describe(mic snapshot: LevelsSnapshot) -> String {
    switch snapshot.micState {
    case .ok: "\(Int(snapshot.micLevel.rounded())) dBFS"
    case .denied: "off (microphone permission not granted)"
    case .nodevice: "off (no input device)"
    }
}

private func describe(out snapshot: LevelsSnapshot) -> String {
    switch snapshot.outState {
    case .ok: "\(Int(snapshot.outLevel.rounded())) dBFS"
    case .denied: "off (system audio permission not granted)"
    case .unsupported: "off (output capture not available)"
    }
}

private func isFresh(_ state: HelperState) -> Bool {
    guard let age = state.ageSeconds else { return false }
    return abs(age) <= 2
}

/// Says whether Sevi is listening and since when. Returns the exit code.
func runStatus() -> Int32 {
    guard let state = helperState() else {
        print("Sevi is not listening.")
        return 0
    }
    print("Sevi is listening (since \(clock(state.since))).")
    print("  terminals using it: \(state.sessions)")
    if let snapshot = state.snapshot, isFresh(state) {
        print("  mic: \(describe(mic: snapshot))")
        print("  out: \(describe(out: snapshot))")
    } else {
        print("  no fresh reading yet")
    }
    return 0
}

/// Prints this process's microphone permission. Meant to be run by macOS
/// opening the app (see `microphonePermission`), so the answer is Sevi's own.
func runPermissionReport() -> Int32 {
    let word = switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized: "authorized"
    case .denied: "denied"
    case .restricted: "restricted"
    case .notDetermined: "notDetermined"
    @unknown default: "unknown"
    }
    print("mic=\(word)")
    return 0
}

/// Asks a second, short-lived copy of the app for its microphone permission.
///
/// Asking from this process would be wrong when it was started from a shell:
/// macOS would answer for the terminal app. A copy opened by macOS answers for
/// Sevi. It only reads the permission; it does not open the microphone.
private func microphonePermission(bundlePath: String) -> String? {
    let paths = StatePaths.current()
    guard (try? StateFileWriter(paths: paths).prepareDirectory()) != nil else { return nil }
    let answerFile = paths.directory + "/permission-report"
    unlink(answerFile)
    defer { unlink(answerFile) }

    let open = Process()
    open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    open.arguments = [
        "-n", "-W", "-g", "-j", "--stdout", answerFile, "--stderr", "/dev/null",
        bundlePath, "--args", "permission-report",
    ]
    open.standardOutput = FileHandle.nullDevice
    open.standardError = FileHandle.nullDevice
    guard (try? open.run()) != nil else { return nil }
    open.waitUntilExit()

    guard let answer = try? String(contentsOfFile: answerFile, encoding: .utf8) else { return nil }
    let word = answer.trimmingCharacters(in: .whitespacesAndNewlines)
    return word.hasPrefix("mic=") ? String(word.dropFirst(4)) : nil
}

/// Checks the things that most often stop Sevi from working. Opens no audio.
/// Returns 0 when nothing needs fixing, 1 otherwise.
func runDoctor() -> Int32 {
    var problems = 0
    func ok(_ text: String) { print("  ok    \(text)") }
    func note(_ text: String) { print("  note  \(text)") }
    func fix(_ text: String) {
        problems += 1
        print("  FIX   \(text)")
    }

    print("Sevi doctor")

    let version = ProcessInfo.processInfo.operatingSystemVersion
    let versionText = "\(version.majorVersion).\(version.minorVersion)"
    if ProcessInfo.processInfo.isOperatingSystemAtLeast(
        OperatingSystemVersion(majorVersion: 14, minorVersion: 2, patchVersion: 0)
    ) {
        ok("macOS \(versionText) (14.2 or later is needed)")
    } else {
        fix("macOS \(versionText) is too old; Sevi needs 14.2 or later.")
    }

    let bundle = appBundle()
    let bundlePath = bundle?.bundlePath ?? ""
    let inBundle = bundle?.bundleIdentifier == bundleIdentifier
    if !inBundle {
        fix("This is not running from Sevi.app, so macOS cannot ask for permissions in Sevi's name.")
    } else if bundlePath.contains("/Applications/") {
        ok("Sevi.app is installed in an Applications folder")
    } else {
        fix("Sevi.app is not in an Applications folder. Move it to /Applications or ~/Applications.")
    }

    // Two copies share one identifier, so macOS may open either of them.
    let standardCopies = ["/Applications/Sevi.app", NSHomeDirectory() + "/Applications/Sevi.app"]
    if standardCopies.allSatisfy({ FileManager.default.fileExists(atPath: $0) }) {
        fix("Sevi.app is installed twice, in /Applications and in ~/Applications. Remove one so macOS always opens the same copy.")
    }

    if inBundle {
        switch microphonePermission(bundlePath: bundlePath) {
        case "authorized":
            ok("microphone permission: allowed")
        case "notDetermined":
            note("microphone permission: not asked yet. macOS asks the first time Sevi listens.")
        case "denied":
            fix("microphone permission: denied. Allow Sevi under System Settings > Privacy & Security > Microphone.")
        case "restricted":
            fix("microphone permission: blocked by a device policy.")
        default:
            note("microphone permission: could not be checked.")
        }
    }
    note("system audio permission: macOS offers no way to check it directly; see the reading below.")

    if let state = helperState() {
        ok("listening since \(clock(state.since)), used by \(state.sessions) terminal(s)")
        if let snapshot = state.snapshot, isFresh(state) {
            ok("fresh reading: mic \(describe(mic: snapshot)), out \(describe(out: snapshot))")
            // A denied system-audio permission gives no error: the tap keeps
            // delivering buffers of pure silence, exactly as it does when
            // nothing is playing. So the two cannot be told apart from here.
            if snapshot.outState == .ok, snapshot.outLevel <= LevelMath.floorDBFS {
                note("\"out\" is complete silence. That is normal when nothing is playing. If audio is playing right now, Sevi has not been allowed to record system audio: allow it under System Settings > Privacy & Security, then run 'sevi stop' and open a new terminal.")
            }
            if snapshot.micState == .nodevice {
                note("no input device was found; connect or select a microphone.")
            }
        } else {
            fix("the helper is running but its reading is stale. Run 'sevi stop', then open a new terminal.")
        }
    } else {
        note("not listening right now. Sevi starts when a terminal with the plugin opens ('sevi init zsh' prints the line for .zshrc).")
    }

    print(problems == 0 ? "Nothing needs fixing." : "\(problems) thing(s) to fix.")
    return problems == 0 ? 0 : 1
}
