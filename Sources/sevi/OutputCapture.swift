import CoreAudio
import Foundation
import SeviCore
import os

/// Owns the tap on the audio this Mac is playing (the system output mix).
///
/// Audio buffers are reduced to level numbers inside the IO callback and
/// dropped. Nothing but those numbers and the state leaves this type.
///
/// Every Core Audio call is made on a private control queue, never the main
/// queue: creating the tap can block for as long as the system-audio permission
/// prompt is on screen, and the helper must keep publishing meanwhile.
/// Unchecked because the object IDs are confined to that queue by this rule,
/// not by the compiler.
final class OutputCapture: @unchecked Sendable {
    struct Reading {
        var level: Double
        var peak: Double
        var state: OutputState
    }

    private struct Shared {
        var meter: ChannelMeter?
        var state: OutputState = .unsupported
        var callbacks = 0
        var loudest = LevelMath.floorDBFS
    }

    private let shared = OSAllocatedUnfairLock(initialState: Shared())
    private let controlQueue = DispatchQueue(label: "com.nerttiyana.sevi.output.control")
    private let ioQueue = DispatchQueue(label: "com.nerttiyana.sevi.output.io")

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var deviceListener: AudioObjectPropertyListenerBlock?

    private static var defaultOutputAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    /// Returns at once; the tap is built in the background.
    func start() {
        controlQueue.async {
            self.build()

            // The tap is tied to the output device that was the default when it
            // was built, so it is rebuilt whenever the default changes.
            let listener: AudioObjectPropertyListenerBlock = { _, _ in
                Log.helper.notice("default output device changed")
                self.tearDown()
                self.build()
            }
            var address = Self.defaultOutputAddress
            if AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, self.controlQueue, listener
            ) == noErr {
                self.deviceListener = listener
            }
        }
    }

    /// Tears the tap down, waiting at most a second. If the control queue is
    /// still held up by a permission prompt, the process is about to exit anyway
    /// and the system removes the private tap and device with it.
    func stop() {
        let done = DispatchSemaphore(value: 0)
        controlQueue.async {
            if let deviceListener = self.deviceListener {
                var address = Self.defaultOutputAddress
                AudioObjectRemovePropertyListenerBlock(
                    AudioObjectID(kAudioObjectSystemObject), &address, self.controlQueue, deviceListener
                )
                self.deviceListener = nil
            }
            self.tearDown()
            done.signal()
        }
        _ = done.wait(timeout: .now() + 1)
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

    // MARK: - Tap lifecycle

    private func build() {
        guard let outputUID = Self.defaultOutputDeviceUID() else {
            fail(step: "default-device", status: 0)
            return
        }

        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr else {
            tapID = AudioObjectID(kAudioObjectUnknown)
            fail(step: "create-tap", status: status)
            return
        }

        guard let meterRate = Self.meterSampleRate(ofTap: tapID) else {
            fail(step: "tap-format", status: 0)
            return
        }

        // A private aggregate device is what makes the tap readable: it pairs
        // the tap with the real output device and gives us an IO callback.
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Sevi",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: description.uuid.uuidString,
            ]],
        ]
        status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID)
        guard status == noErr else {
            aggregateID = AudioObjectID(kAudioObjectUnknown)
            fail(step: "create-aggregate", status: status)
            return
        }

        shared.withLock {
            $0.meter = ChannelMeter(sampleRate: meterRate)
            $0.state = .ok
        }
        let shared = self.shared
        status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, ioQueue) { _, input, _, _, _ in
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            guard let first = buffers.first, let data = first.mData else { return }
            let samples = UnsafeBufferPointer(
                start: data.assumingMemoryBound(to: Float.self),
                count: Int(first.mDataByteSize) / MemoryLayout<Float>.size
            )
            shared.withLockUnchecked {
                $0.meter?.process(samples)
                $0.callbacks += 1
                $0.loudest = max($0.loudest, $0.meter?.level ?? LevelMath.floorDBFS)
            }
        }
        guard status == noErr, let procID else {
            fail(step: "create-io-proc", status: status)
            return
        }

        status = AudioDeviceStart(aggregateID, procID)
        guard status == noErr else {
            fail(step: "start", status: status)
            return
        }
        Log.helper.notice("output capture started")
    }

    private func tearDown() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        procID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
        shared.withLock {
            $0.meter = nil
            $0.state = .unsupported
        }
    }

    /// Logs the step and the Core Audio status code, and leaves the capture torn
    /// down and reported as unsupported.
    private func fail(step: String, status: OSStatus) {
        Log.helper.error("output capture failed at \(step, privacy: .public), status \(status, privacy: .public)")
        tearDown()
    }

    // MARK: - Core Audio queries

    private static func defaultOutputDeviceUID() -> String? {
        var address = defaultOutputAddress
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        ) == noErr, device != kAudioObjectUnknown else {
            return nil
        }

        address.mSelector = kAudioDevicePropertyDeviceUID
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid) == noErr,
              let value = uid?.takeRetainedValue()
        else {
            return nil
        }
        return value as String
    }

    private static func meterSampleRate(ofTap tap: AudioObjectID) -> Double? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format) == noErr else {
            return nil
        }
        let isFloat32 = format.mFormatID == kAudioFormatLinearPCM
            && format.mFormatFlags & kAudioFormatFlagIsFloat != 0
            && format.mBitsPerChannel == 32
        return TapFormat.meterSampleRate(
            sampleRate: format.mSampleRate,
            channels: Int(format.mChannelsPerFrame),
            isInterleaved: format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0,
            isFloat32: isFloat32
        )
    }
}
