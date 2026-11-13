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
    }

    private let shared = OSAllocatedUnfairLock(initialState: Shared())
    private let engine = AVAudioEngine()
    private var tapInstalled = false

    func start() {
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
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine.stop()
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
            shared.withLock { $0.state = .nodevice }
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
            shared.withLockUnchecked { $0.meter?.process(samples) }
        }
        tapInstalled = true

        do {
            try engine.start()
            Log.helper.notice("microphone capture started")
        } catch {
            input.removeTap(onBus: 0)
            tapInstalled = false
            shared.withLock {
                $0.meter = nil
                $0.state = .nodevice
            }
            Log.helper.error("microphone capture failed to start")
        }
    }
}
