import Foundation
import Testing

@testable import SeviCore

@Suite struct LevelMathTests {
    private func rms(_ samples: [Float]) -> Double {
        samples.withUnsafeBufferPointer { LevelMath.rms($0) }
    }

    @Test func fullScaleIsZeroDBFS() {
        #expect(LevelMath.dbfs(amplitude: 1.0) == 0)
    }

    @Test func halfAmplitudeIsAboutMinusSix() {
        #expect(abs(LevelMath.dbfs(amplitude: 0.5) - -6.0206) < 0.001)
    }

    @Test func tenthAmplitudeIsMinusTwenty() {
        #expect(abs(LevelMath.dbfs(amplitude: 0.1) - -20) < 0.0001)
    }

    @Test func silenceAndBadInputReadAsFloor() {
        #expect(LevelMath.dbfs(amplitude: 0) == LevelMath.floorDBFS)
        #expect(LevelMath.dbfs(amplitude: -1) == LevelMath.floorDBFS)
        #expect(LevelMath.dbfs(amplitude: .nan) == LevelMath.floorDBFS)
        #expect(LevelMath.dbfs(amplitude: .infinity) == LevelMath.floorDBFS)
        #expect(LevelMath.dbfs(amplitude: 1e-12) == LevelMath.floorDBFS)
    }

    @Test func overFullScaleClampsToZero() {
        #expect(LevelMath.dbfs(amplitude: 2.0) == 0)
    }

    @Test func rmsOfConstantAndSquareWave() {
        #expect(rms([]) == 0)
        #expect(rms([0.5, 0.5, 0.5]) == 0.5)
        #expect(rms([1, -1, 1, -1]) == 1)
    }

    @Test func rmsOfFullScaleSineIsMinusThreeDBFS() {
        let samples = (0..<4800).map { Float(sin(2 * Double.pi * Double($0) / 48)) }
        #expect(abs(LevelMath.dbfs(amplitude: rms(samples)) - -3.0103) < 0.001)
    }
}

@Suite struct LevelMeterTests {
    @Test func startsAtFloor() {
        let meter = LevelMeter()
        #expect(meter.level == LevelMath.floorDBFS)
        #expect(meter.peak == LevelMath.floorDBFS)
    }

    @Test func risesAtOnce() {
        var meter = LevelMeter()
        meter.update(windowDBFS: -10, at: 0)
        #expect(meter.level == -10)
        #expect(meter.peak == -10)
    }

    @Test func fallsAtTheDecayRate() {
        var meter = LevelMeter(settings: .init(decayPerSecond: 20, peakHold: 1.5))
        meter.update(windowDBFS: -10, at: 0)
        meter.update(windowDBFS: -80, at: 0.5)
        #expect(meter.level == -20)
        meter.update(windowDBFS: -80, at: 1.0)
        #expect(meter.level == -30)
    }

    @Test func neverFallsBelowTheWindowOrTheFloor() {
        var meter = LevelMeter(settings: .init(decayPerSecond: 20, peakHold: 1.5))
        meter.update(windowDBFS: -10, at: 0)
        meter.update(windowDBFS: -15, at: 10)
        #expect(meter.level == -15)
        meter.update(windowDBFS: -.infinity, at: 100)
        #expect(meter.level == LevelMath.floorDBFS)
    }

    @Test func peakHoldsThenDropsToCurrentLevel() {
        var meter = LevelMeter(settings: .init(decayPerSecond: 20, peakHold: 1.5))
        meter.update(windowDBFS: -10, at: 0)
        meter.update(windowDBFS: -80, at: 1.0)
        #expect(meter.peak == -10)
        meter.update(windowDBFS: -80, at: 1.5)
        #expect(meter.peak == -40)
        #expect(meter.level == -40)
    }

    @Test func louderWindowReplacesPeakAndRestartsHold() {
        var meter = LevelMeter(settings: .init(decayPerSecond: 20, peakHold: 1.5))
        meter.update(windowDBFS: -10, at: 0)
        meter.update(windowDBFS: -5, at: 1.0)
        meter.update(windowDBFS: -80, at: 2.0)
        #expect(meter.peak == -5)
    }

    @Test func timeGoingBackwardsDoesNotRaiseTheLevel() {
        var meter = LevelMeter()
        meter.update(windowDBFS: -10, at: 5)
        meter.update(windowDBFS: -80, at: 4)
        #expect(meter.level == -10)
    }
}

@Suite struct LevelsSnapshotTests {
    private func snapshot(
        mic: Double = -41.2, micPeak: Double = -28.5,
        out: Double = -13.8, outPeak: Double = -9.0,
        micState: MicState = .ok, outState: OutputState = .ok
    ) -> LevelsSnapshot {
        LevelsSnapshot(
            timestampMs: 1_794_582_555_927,
            micLevel: mic, micPeak: micPeak, outLevel: out, outPeak: outPeak,
            micState: micState, outState: outState
        )
    }

    /// The same literal is the "valid" case in Tests/plugin/run.zsh, which pins
    /// both sides of the contract to one line.
    @Test func formatsTheContractExample() {
        #expect(snapshot().stateLine == "1 1794582555927 -41.2 -28.5 -13.8 -9.0 ok ok\n")
    }

    @Test func formatsStates() {
        let line = snapshot(micState: .denied, outState: .unsupported).stateLine
        #expect(line.hasSuffix(" denied unsupported\n"))
        #expect(snapshot(micState: .nodevice, outState: .denied).stateLine.hasSuffix(" nodevice denied\n"))
    }

    @Test func roundsToOneDecimalWithoutNegativeZero() {
        let line = snapshot(mic: -0.04, micPeak: 0, out: -0.05, outPeak: -59.96).stateLine
        #expect(line == "1 1794582555927 0.0 0.0 -0.1 -60.0 ok ok\n")
    }

    @Test func clampsOutOfRangeAndNonFiniteLevels() {
        let line = snapshot(mic: 3, micPeak: -500, out: .nan, outPeak: -.infinity).stateLine
        #expect(line == "1 1794582555927 0.0 -120.0 -120.0 -120.0 ok ok\n")
    }
}

@Suite struct StatePathsTests {
    @Test func stripsOneTrailingSlash() {
        let paths = StatePaths(tmpdir: "/var/folders/ab/T/", uid: 501)
        #expect(paths.directory == "/var/folders/ab/T/sevi-501")
        #expect(paths.levelsFile == "/var/folders/ab/T/sevi-501/levels")
    }

    @Test func fallsBackToTmp() {
        #expect(StatePaths(tmpdir: nil, uid: 501).directory == "/tmp/sevi-501")
        #expect(StatePaths(tmpdir: "", uid: 501).directory == "/tmp/sevi-501")
    }
}

@Suite struct StateFileWriterTests {
    private let root: String
    private let sample = LevelsSnapshot(
        timestampMs: 1_794_582_555_927,
        micLevel: -41.2, micPeak: -28.5, outLevel: -13.8, outPeak: -9.0,
        micState: .ok, outState: .ok
    )

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sevi-tests-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
    }

    private func mode(_ path: String) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }

    private func cleanUp() {
        try? FileManager.default.removeItem(atPath: root)
    }

    @Test func writesTheLineWithPrivateModes() throws {
        defer { cleanUp() }
        let paths = StatePaths(tmpdir: root, uid: getuid())
        let writer = StateFileWriter(paths: paths)
        try writer.prepareDirectory()
        try writer.write(sample)

        #expect(try String(contentsOfFile: paths.levelsFile, encoding: .utf8) == sample.stateLine)
        #expect(try mode(paths.directory) == 0o700)
        #expect(try mode(paths.levelsFile) == 0o600)
        #expect(try FileManager.default.contentsOfDirectory(atPath: paths.directory) == ["levels"])
    }

    @Test func replacesThePreviousReading() throws {
        defer { cleanUp() }
        let paths = StatePaths(tmpdir: root, uid: getuid())
        let writer = StateFileWriter(paths: paths)
        try writer.prepareDirectory()
        try writer.write(sample)
        var later = sample
        later.timestampMs += 250
        later.micLevel = -12
        try writer.write(later)

        #expect(try String(contentsOfFile: paths.levelsFile, encoding: .utf8) == later.stateLine)
    }

    @Test func tightensALooseExistingDirectory() throws {
        defer { cleanUp() }
        let paths = StatePaths(tmpdir: root, uid: getuid())
        try FileManager.default.createDirectory(
            atPath: paths.directory, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o755]
        )
        try StateFileWriter(paths: paths).prepareDirectory()
        #expect(try mode(paths.directory) == 0o700)
    }

    @Test func refusesASymlinkedDirectory() throws {
        defer { cleanUp() }
        let paths = StatePaths(tmpdir: root, uid: getuid())
        let elsewhere = root + "/elsewhere"
        try FileManager.default.createDirectory(atPath: elsewhere, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(atPath: paths.directory, withDestinationPath: elsewhere)

        #expect(throws: StateFileWriter.WriteError.directoryUnsafe) {
            try StateFileWriter(paths: paths).prepareDirectory()
        }
    }

    @Test func reportsAMissingDirectory() {
        defer { cleanUp() }
        let writer = StateFileWriter(paths: StatePaths(tmpdir: root, uid: getuid()))
        #expect(throws: StateFileWriter.WriteError.io(ENOENT)) {
            try writer.write(sample)
        }
    }
}

@Suite struct ChannelMeterTests {
    private func sine(frames: Int, period: Int, amplitude: Double = 1) -> [Float] {
        (0..<frames).map { Float(amplitude * sin(2 * Double.pi * Double($0) / Double(period))) }
    }

    @Test func windowComesFromTheSampleRate() {
        #expect(ChannelMeter(sampleRate: 16_000).windowFrames == 1_600)
        #expect(ChannelMeter(sampleRate: 48_000).windowFrames == 4_800)
        #expect(ChannelMeter(sampleRate: 44_100, windowSeconds: 0.05).windowFrames == 2_205)
    }

    @Test func badSampleRatesDoNotCrash() {
        #expect(ChannelMeter(sampleRate: 0).windowFrames == 1)
        #expect(ChannelMeter(sampleRate: .nan).windowFrames == 1)
        #expect(ChannelMeter(sampleRate: .infinity).windowFrames == 1)
    }

    @Test func noReadingUntilAWindowIsFull() {
        var meter = ChannelMeter(sampleRate: 16_000)
        sine(frames: 1_599, period: 16).withUnsafeBufferPointer { meter.process($0) }
        #expect(meter.level == LevelMath.floorDBFS)
        sine(frames: 1, period: 16).withUnsafeBufferPointer { meter.process($0) }
        #expect(meter.level > -4)
    }

    /// The device used in the spike delivered 4800-frame buffers at 16 kHz.
    @Test func sineReadsMinusThreeWhateverTheBufferSize() {
        let samples = sine(frames: 16_000, period: 16)
        for bufferSize in [4_800, 1_024, 333, 16_000] {
            var meter = ChannelMeter(sampleRate: 16_000)
            var offset = 0
            while offset < samples.count {
                let end = min(offset + bufferSize, samples.count)
                samples[offset..<end].withUnsafeBufferPointer { meter.process($0) }
                offset = end
            }
            #expect(abs(meter.level - -3.0103) < 0.01, "buffer size \(bufferSize)")
            #expect(abs(meter.peak - -3.0103) < 0.01, "buffer size \(bufferSize)")
        }
    }

    @Test func levelDecaysOnTheSampleClock() {
        var meter = ChannelMeter(sampleRate: 16_000, settings: .init(decayPerSecond: 20, peakHold: 1.5))
        sine(frames: 1_600, period: 16).withUnsafeBufferPointer { meter.process($0) }
        let loud = meter.level
        [Float](repeating: 0, count: 8_000).withUnsafeBufferPointer { meter.process($0) }
        #expect(abs(meter.level - (loud - 10)) < 0.001)
        #expect(meter.peak == loud)
    }
}

@Suite struct InstanceLockTests {
    private let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("sevi-lock-\(UUID().uuidString)").path

    @Test func onlyOneHolderAtATime() throws {
        defer { unlink(path) }
        #expect(InstanceLock.holderPID(path: path) == nil)

        let first = try #require(InstanceLock.acquire(path: path))
        #expect(InstanceLock.acquire(path: path) == nil)
        #expect(InstanceLock.holderPID(path: path) == getpid())

        first.release()
        #expect(InstanceLock.holderPID(path: path) == nil)
        let second = try #require(InstanceLock.acquire(path: path))
        second.release()
    }

    @Test func refusesASymlink() throws {
        let target = path + "-target"
        defer {
            unlink(path)
            unlink(target)
        }
        FileManager.default.createFile(atPath: target, contents: nil)
        try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: target)
        #expect(InstanceLock.acquire(path: path) == nil)
    }
}

@Suite struct CurrentStatePathsTests {
    /// The app is opened by macOS and never sees a shell's TMPDIR, so the real
    /// path must not follow it.
    @Test func ignoresTheTmpdirVariable() {
        let before = StatePaths.current()
        let saved = getenv("TMPDIR").map { String(cString: $0) }
        setenv("TMPDIR", "/somewhere/else", 1)
        defer {
            if let saved { setenv("TMPDIR", saved, 1) } else { unsetenv("TMPDIR") }
        }
        #expect(StatePaths.current() == before)
        #expect(before.directory.hasSuffix("/sevi-\(getuid())"))
        #expect(!before.directory.hasPrefix("/somewhere"))
    }
}

@Suite struct TapFormatTests {
    @Test func interleavedStereoCountsBothChannels() {
        #expect(TapFormat.meterSampleRate(sampleRate: 16_000, channels: 2, isInterleaved: true, isFloat32: true) == 32_000)
    }

    @Test func nonInterleavedUsesOneChannel() {
        #expect(TapFormat.meterSampleRate(sampleRate: 48_000, channels: 2, isInterleaved: false, isFloat32: true) == 48_000)
    }

    @Test func rejectsFormatsTheMeterCannotRead() {
        #expect(TapFormat.meterSampleRate(sampleRate: 48_000, channels: 2, isInterleaved: true, isFloat32: false) == nil)
        #expect(TapFormat.meterSampleRate(sampleRate: 0, channels: 2, isInterleaved: true, isFloat32: true) == nil)
        #expect(TapFormat.meterSampleRate(sampleRate: .nan, channels: 2, isInterleaved: true, isFloat32: true) == nil)
        #expect(TapFormat.meterSampleRate(sampleRate: 48_000, channels: 0, isInterleaved: true, isFloat32: true) == nil)
    }
}

@Suite struct SessionRegistryTests {
    private let root: String
    private let registry: SessionRegistry

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sevi-sessions-\(UUID().uuidString)").path
        registry = SessionRegistry(paths: StatePaths(tmpdir: root, uid: getuid()))
        try FileManager.default.createDirectory(atPath: registry.directory, withIntermediateDirectories: true)
    }

    private func register(_ name: String) {
        FileManager.default.createFile(atPath: registry.directory + "/" + name, contents: nil)
    }

    private func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: registry.directory + "/" + name)
    }

    private func cleanUp() {
        try? FileManager.default.removeItem(atPath: root)
    }

    @Test func noDirectoryMeansNoSessions() {
        defer { cleanUp() }
        let elsewhere = SessionRegistry(paths: StatePaths(tmpdir: root + "/missing", uid: getuid()))
        #expect(elsewhere.liveSessions() == 0)
    }

    @Test func countsARunningShellAndKeepsItsFile() {
        defer { cleanUp() }
        register("\(getpid())")
        #expect(registry.liveSessions() == 1)
        #expect(exists("\(getpid())"))
    }

    @Test func removesTheFileOfAProcessThatIsGone() {
        defer { cleanUp() }
        register("4242")
        #expect(registry.liveSessions(processStart: { _ in nil }) == 0)
        #expect(!exists("4242"))
    }

    /// The shell died and its process ID now belongs to something newer.
    @Test func aReusedProcessIDDoesNotCount() {
        defer { cleanUp() }
        register("4242")
        let later = Date().addingTimeInterval(60)
        #expect(registry.liveSessions(processStart: { _ in later }) == 0)
        #expect(!exists("4242"))
    }

    @Test func countsEachLiveSession() {
        defer { cleanUp() }
        register("4242")
        register("4243")
        register("4244")
        let earlier = Date().addingTimeInterval(-60)
        #expect(registry.liveSessions(processStart: { $0 == 4243 ? nil : earlier }) == 2)
        #expect(exists("4242") && !exists("4243") && exists("4244"))
    }

    @Test func ignoresNamesThatAreNotProcessIDs() {
        defer { cleanUp() }
        for name in ["notes", "12x", "-5", "1", "0", "99999999999999999999"] {
            register(name)
        }
        let earlier = Date().addingTimeInterval(-60)
        #expect(registry.liveSessions(processStart: { _ in earlier }) == 0)
        #expect(exists("notes") && exists("12x") && exists("1"))
    }

    @Test func aDirectoryNamedLikeAProcessIDDoesNotCount() throws {
        defer { cleanUp() }
        try FileManager.default.createDirectory(atPath: registry.directory + "/4242", withIntermediateDirectories: false)
        let earlier = Date().addingTimeInterval(-60)
        #expect(registry.liveSessions(processStart: { _ in earlier }) == 0)
    }

    @Test func findsTheStartTimeOfThisProcessOnly() {
        defer { cleanUp() }
        let started = SessionRegistry.processStartTime(getpid())
        #expect(started != nil)
        #expect((started ?? .distantFuture) <= Date())
        #expect(SessionRegistry.processStartTime(99_999_999) == nil)
    }
}

@Suite struct IdleExitTests {
    /// Feeds (live sessions, time) pairs in order and returns each answer.
    private func answers(_ steps: [(Int, Double)], grace: Double = 30) -> [Bool] {
        var idle = IdleExit(grace: grace)
        return steps.map { idle.shouldExit(liveSessions: $0.0, at: $0.1) }
    }

    @Test func staysWhileASessionIsLive() {
        #expect(answers([(1, 0), (2, 1_000)]) == [false, false])
    }

    @Test func exitsOnlyAfterTheGracePeriod() {
        #expect(answers([(0, 100), (0, 129.9), (0, 130)]) == [false, false, true])
    }

    @Test func aNewSessionResetsTheCountdown() {
        #expect(answers([(0, 0), (1, 20), (0, 40), (0, 69), (0, 70)]) == [false, false, false, false, true])
    }
}

@Suite struct StateLineParsingTests {
    private let example = "1 1794582555927 -41.2 -28.5 -13.8 -9.0 ok ok"

    @Test func readsTheContractExample() throws {
        let snapshot = try #require(LevelsSnapshot(stateLine: example + "\n"))
        #expect(snapshot.timestampMs == 1_794_582_555_927)
        #expect(snapshot.micLevel == -41.2 && snapshot.micPeak == -28.5)
        #expect(snapshot.outLevel == -13.8 && snapshot.outPeak == -9.0)
        #expect(snapshot.micState == .ok && snapshot.outState == .ok)
        #expect(LevelsSnapshot(stateLine: example) == snapshot)
    }

    @Test func roundTripsWhatItWrites() {
        let written = LevelsSnapshot(
            timestampMs: 42, micLevel: -120, micPeak: 0, outLevel: -0.1, outPeak: -59.9,
            micState: .nodevice, outState: .denied
        )
        #expect(LevelsSnapshot(stateLine: written.stateLine) == written)
    }

    /// The same malformed and hostile lines the plugin tests reject.
    @Test(arguments: [
        "",
        "2 1794582555927 -41.2 -28.5 -13.8 -9.0 ok ok",
        "1 1794582555927 -41.2 -28.5",
        "1 1794582555927 -41.2 -28.5 -13.8 -9.0 ok ok ok",
        "1 1794582555927 -41 -28 -13 -9 ok ok",
        "1 1794582555927 -41.2 -28.5 -13.8 -9.0 ok maybe",
        "1 1794582555927 -41.2 -28.5 -13.8 -9.0 unsupported nodevice",
        " 1 1794582555927 -41.2 -28.5 -13.8 -9.0 ok ok",
        "1 1794582555927 -41.2 -28.5 -13.8 -9.0 ok ok ",
        "1 1794582555927  -41.2 -28.5 -13.8 -9.0 ok ok",
        "1 1794582555927 -4111.2 -28.5 -13.8 -9.0 ok ok",
        "1 1794582555927179458255 -41.2 -28.5 -13.8 -9.0 ok ok",
        "1 +1794582555927 -41.2 -28.5 -13.8 -9.0 ok ok",
        "1 1794582555927 --41.2 -28.5 -13.8 -9.0 ok ok",
        "1 1794582555927 -4e1.2 -28.5 -13.8 -9.0 ok ok",
        "1 1794582555927 nan.0 -28.5 -13.8 -9.0 ok ok",
        "1 1794582555927 -41.2 -28.5 -13.8 -9.0 ok $(touch pwned)",
        "1 1794582555927 -41.2 -28.5 -13.8 -9.0 ok ok%F{red}%n%f",
        "1 1794582555927 -41.2 -28.5 -13.8 -9.0 ok ok\n\n",
    ])
    func rejects(line: String) {
        #expect(LevelsSnapshot(stateLine: line) == nil)
    }
}
