public enum MicState: String, Sendable {
    case ok, denied, nodevice
}

public enum OutputState: String, Sendable {
    case ok, denied, unsupported
}

/// One published reading, and its state-file form.
///
/// Shared invariant with the prompt plugin (`sevi.plugin.zsh`, `_sevi_segment`):
/// the plugin accepts only the exact line `stateLine` produces, matched by a
/// strict pattern. Any change to the fields, their order, the number format or
/// the state words must be made on both sides, with a new contract version.
public struct LevelsSnapshot: Equatable, Sendable {
    public static let contractVersion = 1

    /// Unix time in milliseconds.
    public var timestampMs: Int64
    public var micLevel: Double
    public var micPeak: Double
    public var outLevel: Double
    public var outPeak: Double
    public var micState: MicState
    public var outState: OutputState

    public init(
        timestampMs: Int64,
        micLevel: Double,
        micPeak: Double,
        outLevel: Double,
        outPeak: Double,
        micState: MicState,
        outState: OutputState
    ) {
        self.timestampMs = timestampMs
        self.micLevel = micLevel
        self.micPeak = micPeak
        self.outLevel = outLevel
        self.outPeak = outPeak
        self.micState = micState
        self.outState = outState
    }

    /// `1 <unix ms> <mic> <mic peak> <out> <out peak> <mic state> <out state>`
    /// followed by a newline. Levels are dBFS with one decimal.
    public var stateLine: String {
        let fields = [
            String(Self.contractVersion),
            String(max(0, timestampMs)),
            Self.field(micLevel),
            Self.field(micPeak),
            Self.field(outLevel),
            Self.field(outPeak),
            micState.rawValue,
            outState.rawValue,
        ]
        return fields.joined(separator: " ") + "\n"
    }

    /// One decimal, always with a dot, never "-0.0", clamped to the dBFS range.
    /// Built from integers so no locale can change the decimal separator.
    private static func field(_ dbfs: Double) -> String {
        let clamped = dbfs.isFinite
            ? min(0, max(LevelMath.floorDBFS, dbfs))
            : LevelMath.floorDBFS
        let tenths = Int((-clamped * 10).rounded())
        return (tenths == 0 ? "" : "-") + "\(tenths / 10).\(tenths % 10)"
    }
}
