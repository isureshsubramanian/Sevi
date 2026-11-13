import Foundation

/// Converts raw samples to dBFS (decibels relative to digital full scale):
/// 0 is the loudest possible, more negative is quieter.
public enum LevelMath {
    /// Reported for digital silence and anything quieter. A design choice, not a
    /// measured limit: it fits the state line's three-digit field and sits well
    /// below the -60 dBFS bottom of the prompt glyph.
    public static let floorDBFS: Double = -120.0

    /// Root mean square of one window of samples. An empty window is silence.
    public static func rms(_ samples: UnsafeBufferPointer<Float>) -> Double {
        guard !samples.isEmpty else { return 0 }
        var sum = 0.0
        for sample in samples {
            sum += Double(sample) * Double(sample)
        }
        return (sum / Double(samples.count)).squareRoot()
    }

    /// Linear amplitude (1.0 = full scale) to dBFS, clamped to `floorDBFS...0`.
    /// Non-finite or non-positive input reads as the floor.
    public static func dbfs(amplitude: Double) -> Double {
        guard amplitude.isFinite, amplitude > 0 else { return floorDBFS }
        return min(0, max(floorDBFS, 20 * log10(amplitude)))
    }
}
