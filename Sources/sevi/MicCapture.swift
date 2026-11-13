import AVFoundation
import SeviCore
import os

/// Owns the microphone tap on the system default input device.
///
/// Audio buffers are reduced to level numbers inside the tap and dropped.
/// Nothing but those numbers and the permission state leaves this type.
///
/// `start` and `stop` must be called on the main queue; `reading` may be called
/// from anywhere. Unchecked because the engine is confined to the main queue by
/// that rule, not by the compiler.
final class MicCapture: @unchecked Sendable {
    struct Reading {
        var level: Double
        var peak: Double
        var state: MicState
    }

    private struct Shared {
        var meter: ChannelMeter?
        // Until permission is granted the microphone is closed, which reads the
        // same to the prompt as a denial.
        var state: MicState = .denied
        var callbacks = 0
        var loudest = LevelMath.floorDBFS
    }

    private let shared = OSAllocatedUnfairLock(initialState: Shared())
    private let engine = AVAudioEngine()
    private var tapInstalled = false
    private var configurationObserver: NSObjectProtocol?

    func start() {
        // The engine stops itself when the input device or its format changes
        // (for example a headset is plugged in), so capture is set up again.
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            guard let self, AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return }
            Log.helper.notice("input device changed")
            self.removeTap()
            self.engine.stop()
            self.startEngine()
        }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            startEngine()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.startEngine()
                    } else {
                        Log.helper.notice("microphone permission denied")
                    }
                }
            }
        default:
            Log.helper.notice("microphone permission denied")
        }
    }

    func stop() {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
            self.configurationObserver = nil
        }
        removeTap()
        engine.stop()
    }

    private func removeTap() {
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
    }

    /// Counts for a bounded self-test run: numbers only.
    func diagnostics() -> (callbacks: Int, loudest: Double) {
        shared.withLock { ($0.callbacks, $0.loudest) }
    }

    func reading() -> Reading {
        shared.withLock { shared in
            Reading(
                level: shared.meter?.level ?? LevelMath.floorDBFS,
                peak: shared.meter?.peak ?? LevelMath.floorDBFS,
                state: shared.state
            )
        }
    }

    private func startEngine() {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            shared.withLock {
                $0.meter = nil
                $0.state = .nodevice
            }
            Log.helper.notice("no input device")
            return
        }

        shared.withLock {
            $0.meter = ChannelMeter(sampleRate: format.sampleRate)
            $0.state = .ok
        }
        let shared = self.shared
        // The level is taken from the first channel only.
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            guard let channels = buffer.floatChannelData else { return }
            let samples = UnsafeBufferPointer(start: channels[0], count: Int(buffer.frameLength))
            shared.withLockUnchecked {
                $0.meter?.process(samples)
                $0.callbacks += 1
                $0.loudest = max($0.loudest, $0.meter?.level ?? LevelMath.floorDBFS)
            }
        }
        tapInstalled = true

        do {
            try engine.start()
            Log.helper.notice("microphone capture started")
        } catch {
            removeTap()
            shared.withLock {
                $0.meter = nil
                $0.state = .nodevice
            }
            Log.helper.error("microphone capture failed to start")
        }
    }
}
