/// Turns one channel's raw sample buffers into a smoothed level and peak.
///
/// Buffers arrive in whatever size the audio device chooses, so this cuts its
/// own fixed windows from the sample rate and feeds each window's RMS to a
/// `LevelMeter`. Time is counted in samples, so the result does not depend on
/// when the buffers happen to be delivered.
public struct ChannelMeter: Sendable {
    /// Frames per window, derived from the sample rate.
    public let windowFrames: Int

    private let windowSeconds: Double
    private var meter: LevelMeter
    private var sumOfSquares = 0.0
    private var frames = 0
    private var time = 0.0

    /// `windowSeconds` is a starting value, to tune.
    public init(
        sampleRate: Double,
        windowSeconds: Double = 0.1,
        settings: LevelMeter.Settings = LevelMeter.Settings()
    ) {
        let wanted = (sampleRate * windowSeconds).rounded()
        let usable = wanted.isFinite && wanted >= 1 && wanted <= 10_000_000
        windowFrames = usable ? Int(wanted) : 1
        self.windowSeconds = sampleRate.isFinite && sampleRate > 0
            ? Double(windowFrames) / sampleRate
            : windowSeconds
        meter = LevelMeter(settings: settings)
    }

    public var level: Double { meter.level }
    public var peak: Double { meter.peak }

    /// Consumes a buffer of samples. The samples are only summed; none are kept.
    public mutating func process(_ samples: UnsafeBufferPointer<Float>) {
        for sample in samples {
            sumOfSquares += Double(sample) * Double(sample)
            frames += 1
            if frames == windowFrames {
                let rms = (sumOfSquares / Double(frames)).squareRoot()
                time += windowSeconds
                meter.update(windowDBFS: LevelMath.dbfs(amplitude: rms), at: time)
                sumOfSquares = 0
                frames = 0
            }
        }
    }
}
