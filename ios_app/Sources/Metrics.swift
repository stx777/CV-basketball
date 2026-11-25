import Foundation
import CoreGraphics
import QuartzCore

struct BasketballMetrics {
    var realBounces: Int = 0
    var falseBounces: Int = 0
    var shots: Int = 0
    var tempo: Double = 0.0
    var avgBounceHeightCm: Double = 0.0
}

final class MetricsCalculator {
    private let ballDiameterCm: CGFloat = 24.0
    private let minPeakDistanceFrames: Int = 8

    // Полная история за всю тренировку (без скользящего окна)
    private var xHistory: [CGFloat?] = []
    private var yHistory: [CGFloat?] = []
    private var wHistory: [CGFloat?] = []
    private var shoulderYHistory: [CGFloat?] = []
    private var leftWristHistory: [CGPoint?] = []
    private var rightWristHistory: [CGPoint?] = []
    private var timestamps: [CFTimeInterval] = []

    // Накопленные итоги по уже подтверждённым событиям
    private var realBouncesCount: Int = 0
    private var falseBouncesCount: Int = 0
    private var shotsCount: Int = 0
    private var bounceHeightsCm: [CGFloat] = []
    private var processedBounceIndices: Set<Int> = []

    func reset() {
        xHistory.removeAll()
        yHistory.removeAll()
        wHistory.removeAll()
        shoulderYHistory.removeAll()
        leftWristHistory.removeAll()
        rightWristHistory.removeAll()
        timestamps.removeAll()

        realBouncesCount = 0
        falseBouncesCount = 0
        shotsCount = 0
        bounceHeightsCm.removeAll()
        processedBounceIndices.removeAll()
    }

    func update(
        ballRect: CGRect?,
        leftWrist: CGPoint?,
        rightWrist: CGPoint?,
        leftShoulder: CGPoint?,
        rightShoulder: CGPoint?,
        timestamp: CFTimeInterval,
        viewWidth: CGFloat,
        viewHeight: CGFloat
    ) -> BasketballMetrics {
        if let rect = ballRect {
            xHistory.append(rect.midX)
            yHistory.append(rect.midY)
            wHistory.append(rect.width)
        } else {
            xHistory.append(nil)
            yHistory.append(nil)
            wHistory.append(nil)
        }

        let shoulderY: CGFloat?
        if let ls = leftShoulder, let rs = rightShoulder {
            shoulderY = (ls.y + rs.y) / 2.0
        } else {
            shoulderY = leftShoulder?.y ?? rightShoulder?.y
        }

        shoulderYHistory.append(shoulderY)
        leftWristHistory.append(leftWrist)
        rightWristHistory.append(rightWrist)
        timestamps.append(timestamp)

        return evaluateIncremental(viewWidth: viewWidth, viewHeight: viewHeight)
    }

    private func evaluateIncremental(viewWidth: CGFloat, viewHeight: CGFloat) -> BasketballMetrics {
        let count = yHistory.count
        let lookahead = max(minPeakDistanceFrames * 2, 16)

        guard count > lookahead,
              yHistory.contains(where: { $0 != nil }),
              let xArr = linearInterpolate(xHistory),
              let yArr = linearInterpolate(yHistory),
              let wArr = linearInterpolate(wHistory) else {
            return currentSnapshot()
        }

        let shouldersArr = linearInterpolate(shoulderYHistory)

        let safeEnd = count - lookahead
        guard safeEnd >= 3 else {
            return currentSnapshot()
        }

        let confirmedY = Array(yArr[0..<safeEnd])
        let prominence = max(18.0, viewHeight * 0.035)
        let controlThreshold = max(90.0, viewWidth * 0.35)

        let bounces = findPeaks(in: confirmedY, distance: minPeakDistanceFrames, prominence: prominence, findMax: true)
        let hands = findPeaks(in: confirmedY, distance: minPeakDistanceFrames, prominence: prominence, findMax: false)

        if !hands.isEmpty {
            for bounceIdx in bounces where !processedBounceIndices.contains(bounceIdx) {
                processedBounceIndices.insert(bounceIdx)

                guard let closestHandIdx = hands.min(by: { abs($0 - bounceIdx) < abs($1 - bounceIdx) }) else {
                    continue
                }

                let ballX = xArr[closestHandIdx]
                let ballY = yArr[closestHandIdx]

                if let sArr = shouldersArr {
                    let shoulderY = sArr[closestHandIdx]
                    if ballY < shoulderY {
                        shotsCount += 1
                        continue
                    }
                }

                var distLeft = CGFloat.infinity
                var distRight = CGFloat.infinity

                if let lw = leftWristHistory[closestHandIdx] {
                    distLeft = hypot(ballX - lw.x, ballY - lw.y)
                }
                if let rw = rightWristHistory[closestHandIdx] {
                    distRight = hypot(ballX - rw.x, ballY - rw.y)
                }

                if min(distLeft, distRight) < controlThreshold {
                    realBouncesCount += 1

                    let startIdx = min(closestHandIdx, bounceIdx)
                    let endIdx = max(closestHandIdx, bounceIdx)
                    let slice = wArr[startIdx...endIdx]
                    let avgWidth = slice.reduce(0, +) / CGFloat(slice.count)

                    if avgWidth > 0 {
                        let cmPerPx = ballDiameterCm / avgWidth
                        let heightPx = max(0, yArr[bounceIdx] - yArr[closestHandIdx])
                        bounceHeightsCm.append(heightPx * cmPerPx)
                    }
                } else {
                    falseBouncesCount += 1
                }
            }
        }

        return currentSnapshot()
    }

    private func currentSnapshot() -> BasketballMetrics {
        let durationSec: Double
        if let first = timestamps.first, let last = timestamps.last, last > first {
            durationSec = last - first
        } else {
            durationSec = 0
        }

        let tempo = durationSec > 0 ? Double(realBouncesCount) / durationSec : 0.0
        let avgHeight = bounceHeightsCm.isEmpty
            ? 0.0
            : Double(bounceHeightsCm.reduce(0, +)) / Double(bounceHeightsCm.count)

        return BasketballMetrics(
            realBounces: realBouncesCount,
            falseBounces: falseBouncesCount,
            shots: shotsCount,
            tempo: tempo,
            avgBounceHeightCm: avgHeight
        )
    }

    private func linearInterpolate(_ values: [CGFloat?]) -> [CGFloat]? {
        let validIndices = values.indices.filter { values[$0] != nil }
        guard !validIndices.isEmpty else { return nil }

        var result = Array(repeating: CGFloat(0), count: values.count)
        let firstIdx = validIndices.first!
        let lastIdx = validIndices.last!

        for i in 0...firstIdx {
            result[i] = values[firstIdx]!
        }
        for i in lastIdx..<values.count {
            result[i] = values[lastIdx]!
        }

        for k in 0..<(validIndices.count - 1) {
            let i0 = validIndices[k]
            let i1 = validIndices[k + 1]
            let v0 = values[i0]!
            let v1 = values[i1]!
            result[i0] = v0
            if i1 - i0 > 1 {
                for i in (i0 + 1)..<i1 {
                    let t = CGFloat(i - i0) / CGFloat(i1 - i0)
                    result[i] = v0 + t * (v1 - v0)
                }
            }
        }
        result[lastIdx] = values[lastIdx]!
        return result
    }

    private func findPeaks(in arr: [CGFloat], distance: Int, prominence: CGFloat, findMax: Bool) -> [Int] {
        guard arr.count >= 3 else { return [] }
        let signed = findMax ? arr : arr.map { -$0 }
        var candidates: [(index: Int, value: CGFloat)] = []

        for i in 1..<(signed.count - 1) {
            if signed[i] > signed[i - 1] && signed[i] >= signed[i + 1] {
                let leftStart = max(0, i - distance * 2)
                let rightEnd = min(signed.count - 1, i + distance * 2)
                let leftMin = signed[leftStart...i].min() ?? signed[i]
                let rightMin = signed[i...rightEnd].min() ?? signed[i]
                let prom = signed[i] - max(leftMin, rightMin)

                if prom >= prominence {
                    candidates.append((i, signed[i]))
                }
            }
        }

        let sortedByHeight = candidates.sorted { $0.value > $1.value }
        var selected: [Int] = []

        for cand in sortedByHeight {
            if selected.allSatisfy({ abs($0 - cand.index) >= distance }) {
                selected.append(cand.index)
            }
        }

        return selected.sorted()
    }
}