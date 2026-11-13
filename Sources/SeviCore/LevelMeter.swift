/// Smooths a stream of window levels for display: the level rises at once and
/// falls at a fixed rate, and the highest recent level is held as a peak.
///
/// Time is passed in by the caller (seconds on any monotonic clock), so the
/// meter has no clock of its own and can be tested with made-up times.
public struct LevelMeter: Sendable {
    public struct Settings: Sendable {
        /// How fast the shown level falls, in dB per second. Estimate, to tune.
        public var decayPerSecond: Double
        /// How long a peak stays before it drops to the current level, in
        /// seconds. Starting value, to tune.
        public var peakHold: Double

        public init(decayPerSecond: Double = 20, peakHold: Double = 1.5) {
            self.decayPerSecond = decayPerSecond
            self.peakHold = peakHold
        }
    }

    public let settings: Settings
    public private(set) var level: Double = LevelMath.floorDBFS
    public private(set) var peak: Double = LevelMath.floorDBFS
    private var peakSetAt: Double = 0
    private var lastUpdate: Double?

    public init(settings: Settings = Settings()) {
        self.settings = settings
    }

    /// Feeds one window's level in dBFS, measured at `time`.
    public mutating func update(windowDBFS: Double, at time: Double) {
        let window = windowDBFS.isFinite
            ? min(0, max(LevelMath.floorDBFS, windowDBFS))
            : LevelMath.floorDBFS
        let elapsed = lastUpdate.map { max(0, time - $0) } ?? 0
        lastUpdate = time

        let decayed = level - settings.decayPerSecond * elapsed
        level = max(LevelMath.floorDBFS, max(window, decayed))

        if level >= peak || time - peakSetAt >= settings.peakHold {
            peak = level
            peakSetAt = time
        }
    }
}
