import Foundation
import SeviCore
import os

/// Lifecycle events and error codes only: never audio, paths or user names.
enum Log {
    static let helper = Logger(subsystem: "com.nerttiyana.sevi", category: "helper")
}

/// How often the state file is rewritten. Starting value; the prompt only reads
/// when it is drawn, so a faster rate buys nothing.
private let writeInterval = DispatchTimeInterval.milliseconds(250)

/// Listens and publishes levels until told to stop.
///
/// This must run inside Sevi.app, started by macOS opening the app. Run from a
/// shell, the microphone request is made in the terminal's name instead of
/// Sevi's.
func runDaemon(maxSeconds: Double?) -> Never {
    let paths = StatePaths.current()
    let writer = StateFileWriter(paths: paths)
    do {
        try writer.prepareDirectory()
    } catch {
        Log.helper.error("state directory unusable")
        exit(1)
    }
    guard InstanceLock.acquire(path: paths.lockFile) != nil else {
        Log.helper.notice("already running")
        exit(0)
    }

    // A bounded run counts from here, so the time the microphone and system
    // audio are open never exceeds what was asked for.
    let started = DispatchTime.now()
    let mic = MicCapture()
    mic.start()
    let output = OutputCapture()
    output.start()
    Log.helper.notice("helper started")

    let shutDown: @Sendable () -> Never = {
        if maxSeconds != nil {
            // A bounded run is a self-test: report what was received.
            let micCounts = mic.diagnostics()
            let outCounts = output.diagnostics()
            print("mic: state \(mic.reading().state.rawValue), buffers \(micCounts.callbacks), loudest \(Int(micCounts.loudest.rounded())) dBFS")
            print("out: state \(output.reading().state.rawValue), buffers \(outCounts.callbacks), loudest \(Int(outCounts.loudest.rounded())) dBFS")
        }
        mic.stop()
        output.stop()
        unlink(paths.levelsFile)
        Log.helper.notice("helper stopped")
        exit(0)
    }

    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now(), repeating: writeInterval)
    timer.setEventHandler {
        let micReading = mic.reading()
        let outReading = output.reading()
        let snapshot = LevelsSnapshot(
            timestampMs: Int64(Date().timeIntervalSince1970 * 1000),
            micLevel: micReading.level,
            micPeak: micReading.peak,
            outLevel: outReading.level,
            outPeak: outReading.peak,
            micState: micReading.state,
            outState: outReading.state
        )
        // A failed write leaves the last reading in place; the prompt shows it
        // as stale after two seconds.
        try? writer.write(snapshot)

        if let maxSeconds {
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1e9
            if elapsed >= maxSeconds {
                shutDown()
            }
        }
    }
    timer.resume()

    var signalSources: [DispatchSourceSignal] = []
    for number in [SIGTERM, SIGINT] {
        signal(number, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
        source.setEventHandler { shutDown() }
        source.resume()
        signalSources.append(source)
    }

    withExtendedLifetime((timer, signalSources)) {
        dispatchMain()
    }
}

/// Ends listening now. Returns the process exit code.
func runStop() -> Int32 {
    let paths = StatePaths.current()
    guard let pid = InstanceLock.holderPID(path: paths.lockFile) else {
        print("Sevi is not listening.")
        return 0
    }
    guard kill(pid, SIGTERM) == 0 else {
        print("Could not stop Sevi (error \(errno)).")
        return 1
    }
    print("Sevi stopped listening.")
    return 0
}
