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

    /// Reads a state line back. Accepts exactly what `stateLine` writes (with or
    /// without the final newline) and nothing else, the same rule the plugin
    /// applies.
    public init?(stateLine: String) {
        var line = Substring(stateLine)
        if line.hasSuffix("\n") { line = line.dropLast() }
        let fields = line.split(separator: " ", omittingEmptySubsequences: false)
        guard line.utf8.count <= 96, fields.count == 8,
              fields[0] == String(Self.contractVersion),
              (1...15).contains(fields[1].utf8.count),
              fields[1].utf8.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }),
              let timestamp = Int64(fields[1]),
              let micLevel = Self.level(fields[2]), let micPeak = Self.level(fields[3]),
              let outLevel = Self.level(fields[4]), let outPeak = Self.level(fields[5]),
              let micState = MicState(rawValue: String(fields[6])),
              let outState = OutputState(rawValue: String(fields[7]))
        else {
            return nil
        }
        self.init(
            timestampMs: timestamp,
            micLevel: micLevel, micPeak: micPeak, outLevel: outLevel, outPeak: outPeak,
            micState: micState, outState: outState
        )
    }

    /// An optional minus, one to three digits, a dot, one digit.
    private static func level(_ field: Substring) -> Double? {
        let digits = field.hasPrefix("-") ? field.dropFirst() : field
        let parts = digits.split(separator: ".", omittingEmptySubsequences: false)
        let isDigit: (UInt8) -> Bool = { $0 >= 0x30 && $0 <= 0x39 }
        guard parts.count == 2,
              (1...3).contains(parts[0].utf8.count), parts[0].utf8.allSatisfy(isDigit),
              parts[1].utf8.count == 1, parts[1].utf8.allSatisfy(isDigit)
        else {
            return nil
        }
        return Double(field)
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
