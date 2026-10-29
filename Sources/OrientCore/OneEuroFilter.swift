import Foundation

/// Single-channel 1-Euro adaptive low-pass filter (Casiez et al., CHI 2012).
/// Heavily smooths jitter when stationary/slow, while raising the cutoff frequency
/// proportionally to signal speed so fast flicks experience near-zero phase lag.
public struct OneEuroFilter1D: Sendable {
    public var minCutoff: Double
    public var beta: Double
    public var derivativeCutoff: Double

    private var lastTimestamp: TimeInterval?
    private var prevFilteredValue: Double = 0
    private var prevFilteredDerivative: Double = 0
    public private(set) var lastEstimatedLagMs: Double = 0

    public init(minCutoff: Double = 1.6, beta: Double = 0.085, derivativeCutoff: Double = 1.0) {
        self.minCutoff = max(0.05, minCutoff)
        self.beta = max(0.0, beta)
        self.derivativeCutoff = max(0.05, derivativeCutoff)
    }

    public mutating func reset() {
        lastTimestamp = nil
        prevFilteredValue = 0
        prevFilteredDerivative = 0
        lastEstimatedLagMs = 0
    }

    public mutating func filter(_ value: Double, timestamp: TimeInterval) -> Double {
        guard let lastTime = lastTimestamp else {
            lastTimestamp = timestamp
            prevFilteredValue = value
            prevFilteredDerivative = 0
            lastEstimatedLagMs = 0
            return value
        }

        let dt = max(1e-4, min(0.25, timestamp - lastTime))
        lastTimestamp = timestamp

        // 1. Estimate derivative and low-pass filter it
        let rawDerivative = (value - prevFilteredValue) / dt
        let alphaD = Self.smoothingFactor(dt: dt, cutoff: derivativeCutoff)
        let filteredDerivative = alphaD * rawDerivative + (1.0 - alphaD) * prevFilteredDerivative
        prevFilteredDerivative = filteredDerivative

        // 2. Compute adaptive cutoff frequency
        let adaptiveCutoff = max(0.05, minCutoff + beta * abs(filteredDerivative))
        let alpha = Self.smoothingFactor(dt: dt, cutoff: adaptiveCutoff)
        let filteredValue = alpha * value + (1.0 - alpha) * prevFilteredValue
        prevFilteredValue = filteredValue

        // Instantaneous RC time constant tau = 1 / (2 * pi * f_c), effective lag ~ (1 - alpha) * dt
        lastEstimatedLagMs = (1.0 - alpha) * dt * 1000.0
        return filteredValue
    }

    private static func smoothingFactor(dt: Double, cutoff: Double) -> Double {
        let tau = 1.0 / (2.0 * Double.pi * max(0.01, cutoff))
        return 1.0 / (1.0 + tau / dt)
    }
}

