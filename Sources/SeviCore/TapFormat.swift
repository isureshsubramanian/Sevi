/// Decides how a system-output tap's sample stream is fed to a `ChannelMeter`.
public enum TapFormat {
    /// Samples per second in the first buffer the tap delivers, or nil when the
    /// format is one the meter cannot read.
    ///
    /// An interleaved buffer carries every channel's samples in turn, so it
    /// holds `channels` samples per frame and the level covers all channels. A
    /// non-interleaved tap delivers one buffer per channel and only the first
    /// is measured.
    public static func meterSampleRate(
        sampleRate: Double, channels: Int, isInterleaved: Bool, isFloat32: Bool
    ) -> Double? {
        guard isFloat32, sampleRate.isFinite, sampleRate > 0, channels > 0, channels <= 64 else {
            return nil
        }
        return isInterleaved ? sampleRate * Double(channels) : sampleRate
    }
}
