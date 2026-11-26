import Foundation
import CoreGraphics

struct BasketballMetrics {
    var realBounces: Int = 0
    var falseBounces: Int = 0
    var shots: Int = 0
    var tempo: Double = 0.0
    var avgBounceHeightCm: Double = 0.0
}

final class MetricsCalculator {
    private struct FrameSample {
        let activeTime: Double
        let ballX: CGFloat?
        let ballY: CGFloat?
        let ballSize: CGFloat?
        let shoulderY: CGFloat?
        let leftWrist: CGPoint?
        let rightWrist: CGPoint?
    }

    // Физические и временные константы (не зависят от FPS)
    private let ballDiameterCm: CGFloat = 24.0
    private let windowDurationSec: Double = 5.0
    private let lookaheadSec: Double = 0.45
    private let minPeakDistanceSec: Double = 0.22
    private let prominenceWindowSec: Double = 0.45
    private let maxHandBounceDeltaSec: Double = 0.65
    private let maxInterpolationGapSec: Double = 0.35
    private let wristSearchWindowSec: Double = 0.10
    private let maxPauseGapSec: Double = 0.50

    // Скользящее окно последних кадров
    private var samples: [FrameSample] = []

    // Учёт только активного времени (без простоев на паузе)
    private var lastRawTimestamp: TimeInterval?
    private var activeTime: Double = 0.0

    // Накопленные итоги в O(1) по памяти
    private var realBouncesCount: Int = 0
    private var falseBouncesCount: Int = 0
    private var shotsCount: Int = 0
    private var totalBounceHeightCm: Double = 0.0
    private var validHeightSamples: Int = 0

    // Временные метки недавно учтённых событий для защиты от дублей
    private var countedBounceTimes: [Double] = []
    private var countedShotHandTimes: [Double] = []

    func reset() {
        samples.removeAll()
        lastRawTimestamp = nil
        activeTime = 0.0

        realBouncesCount = 0
        falseBouncesCount = 0
        shotsCount = 0
        totalBounceHeightCm = 0.0
        validHeightSamples = 0

        countedBounceTimes.removeAll()
        countedShotHandTimes.removeAll()
    }

    /// Вызывается при постановке на паузу, чтобы не смешивать траектории до и после паузы
    func notifyPause() {
        lastRawTimestamp = nil
        samples.removeAll()
    }

    /// Координаты должны передаваться в неискажённом пространстве ориентированного кадра (top-left origin)
    func update(
        ballRect: CGRect?,
        leftWrist: CGPoint?,
        rightWrist: CGPoint?,
        leftShoulder: CGPoint?,
        rightShoulder: CGPoint?,
        timestamp: TimeInterval,
        frameWidth: CGFloat,
        frameHeight: CGFloat
    ) -> BasketballMetrics {
        if let prev = lastRawTimestamp {
            let dt = timestamp - prev
            if dt > 0 && dt <= maxPauseGapSec {
                activeTime += dt
            } else if dt > maxPauseGapSec {
                // Обнаружен длительный разрыв (пауза / переключение камеры): очищаем окно, сохраняя счётчики
                samples.removeAll()
            }
        }
        lastRawTimestamp = timestamp

        let shoulderY: CGFloat?
        if let ls = leftShoulder, let rs = rightShoulder {
            shoulderY = (ls.y + rs.y) / 2.0
        } else {
            shoulderY = leftShoulder?.y ?? rightShoulder?.y
        }

        let ballSize = ballRect.map { ($0.width + $0.height) / 2.0 }
        let sample = FrameSample(
            activeTime: activeTime,
            ballX: ballRect?.midX,
            ballY: ballRect?.midY,
            ballSize: ballSize,
            shoulderY: shoulderY,
            leftWrist: leftWrist,
            rightWrist: rightWrist
        )
        samples.append(sample)

        trimWindow()
        evaluateWindow(frameWidth: frameWidth, frameHeight: frameHeight)
        return currentSnapshot()
    }

    private func trimWindow() {
        let minSampleTime = activeTime - windowDurationSec
        if let firstKeep = samples.firstIndex(where: { $0.activeTime >= minSampleTime }), firstKeep > 0 {
            samples.removeFirst(firstKeep)
        }

        let minHistoryTime = activeTime - (windowDurationSec + 2.0)
        countedBounceTimes.removeAll { $0 < minHistoryTime }
        countedShotHandTimes.removeAll { $0 < minHistoryTime }
    }

    private func evaluateWindow(frameWidth: CGFloat, frameHeight: CGFloat) {
        guard samples.count >= 5 else { return }

        let safeCutoffTime = activeTime - lookaheadSec
        guard let firstTime = samples.first?.activeTime, safeCutoffTime > firstTime else {
            return
        }

        let times = samples.map(\.activeTime)
        let xArr = linearInterpolate(samples.map(\.ballX), times: times, maxGap: maxInterpolationGapSec)
        let yArr = linearInterpolate(samples.map(\.ballY), times: times, maxGap: maxInterpolationGapSec)
        let sizeArr = linearInterpolate(samples.map(\.ballSize), times: times, maxGap: maxInterpolationGapSec)
        let shoulderArr = linearInterpolate(samples.map(\.shoulderY), times: times, maxGap: maxInterpolationGapSec)

        let prominence = max(18.0, frameHeight * 0.035)
        let controlThreshold = max(90.0, frameWidth * 0.35)

        // Нижние пики (удары об пол — максимум Y) подтверждаем только до safeCutoffTime
        let bounces = findPeaks(
            in: yArr,
            times: times,
            maxCandidateTime: safeCutoffTime,
            minDistanceSec: minPeakDistanceSec,
            prominence: prominence,
            findMax: true
        )

        // Верхние пики (мяч у рук — минимум Y) ищем по всему окну, включая хвост после удара
        let hands = findPeaks(
            in: yArr,
            times: times,
            maxCandidateTime: activeTime,
            minDistanceSec: minPeakDistanceSec,
            prominence: prominence,
            findMax: false
        )

        for bounceIdx in bounces {
            let bounceTime = times[bounceIdx]
            if isTimeAlreadyCounted(bounceTime, in: countedBounceTimes, tolerance: minPeakDistanceSec) {
                continue
            }

            // Ищем ближайший верхний пик в допустимом временном окне
            let closestHandIdx = hands
                .filter { abs(times[$0] - bounceTime) <= maxHandBounceDeltaSec }
                .min { abs(times[$0] - bounceTime) < abs(times[$1] - bounceTime) }

            guard let handIdx = closestHandIdx else {
                // Если окно ожидания пост-отскока истекло, а руки так и не нашлись — это потеря
                if activeTime - bounceTime > maxHandBounceDeltaSec + 0.15 {
                    countedBounceTimes.append(bounceTime)
                    falseBouncesCount += 1
                }
                continue
            }

            countedBounceTimes.append(bounceTime)

            guard let handBallY = yArr[handIdx], let bounceBallY = yArr[bounceIdx] else {
                continue
            }

            let handTime = times[handIdx]
            let avgSize = averageValidValue(in: sizeArr, from: min(handIdx, bounceIdx), to: max(handIdx, bounceIdx))

            // Проверка на бросок: мяч ощутимо выше линии плеч (с дедупликацией по верхнему пику)
            if let shoulderY = shoulderArr[handIdx] {
                let shotMargin = (avgSize ?? 40.0) * 0.5
                if handBallY < shoulderY - shotMargin {
                    if !isTimeAlreadyCounted(handTime, in: countedShotHandTimes, tolerance: minPeakDistanceSec) {
                        countedShotHandTimes.append(handTime)
                        shotsCount += 1
                    }
                    continue
                }
            }

            // Проверка контроля мяча кистями в окне ±0.10 с (защита от моргания Vision на 1 кадр)
            let minWristDist = minimumWristDistance(around: handIdx, xArr: xArr, yArr: yArr, times: times)

            if minWristDist < controlThreshold {
                realBouncesCount += 1

                if let sizePx = avgSize, sizePx > 0 {
                    let cmPerPx = ballDiameterCm / sizePx
                    let heightPx = max(0, bounceBallY - handBallY)
                    let heightCm = Double(heightPx * cmPerPx)
                    if heightCm > 5.0 && heightCm < 350.0 {
                        totalBounceHeightCm += heightCm
                        validHeightSamples += 1
                    }
                }
            } else {
                falseBouncesCount += 1
            }
        }
    }

    private func minimumWristDistance(
        around centerIdx: Int,
        xArr: [CGFloat?],
        yArr: [CGFloat?],
        times: [Double]
    ) -> CGFloat {
        let targetTime = times[centerIdx]
        var bestDist = CGFloat.infinity

        for i in samples.indices {
            if abs(times[i] - targetTime) > wristSearchWindowSec {
                continue
            }
            guard let bx = xArr[i], let by = yArr[i] else { continue }

            if let lw = samples[i].leftWrist {
                bestDist = min(bestDist, hypot(bx - lw.x, by - lw.y))
            }
            if let rw = samples[i].rightWrist {
                bestDist = min(bestDist, hypot(bx - rw.x, by - rw.y))
            }
        }
        return bestDist
    }

    private func averageValidValue(in arr: [CGFloat?], from startIdx: Int, to endIdx: Int) -> CGFloat? {
        guard startIdx <= endIdx else { return nil }
        var sum: CGFloat = 0
        var count = 0
        for i in startIdx...endIdx {
            if let v = arr[i], v > 0 {
                sum += v
                count += 1
            }
        }
        return count > 0 ? sum / CGFloat(count) : nil
    }

    private func isTimeAlreadyCounted(_ time: Double, in history: [Double], tolerance: Double) -> Bool {
        history.contains { abs($0 - time) < tolerance }
    }

    private func currentSnapshot() -> BasketballMetrics {
        let tempo = activeTime > 0 ? Double(realBouncesCount) / activeTime : 0.0
        let avgHeight = validHeightSamples > 0 ? totalBounceHeightCm / Double(validHeightSamples) : 0.0

        return BasketballMetrics(
            realBounces: realBouncesCount,
            falseBounces: falseBouncesCount,
            shots: shotsCount,
            tempo: tempo,
            avgBounceHeightCm: avgHeight
        )
    }

    /// Линейная интерполяция только коротких пропусков без экстраполяции краёв
    private func linearInterpolate(_ values: [CGFloat?], times: [Double], maxGap: Double) -> [CGFloat?] {
        let validIndices = values.indices.filter { values[$0] != nil }
        guard !validIndices.isEmpty else { return values }

        var result = values
        guard validIndices.count >= 2 else { return result }

        for k in 0..<(validIndices.count - 1) {
            let i0 = validIndices[k]
            let i1 = validIndices[k + 1]
            guard i1 - i0 > 1 else { continue }

            let dt = times[i1] - times[i0]
            guard dt > 0 && dt <= maxGap,
                  let v0 = values[i0],
                  let v1 = values[i1] else {
                continue
            }

            for i in (i0 + 1)..<i1 {
                let t = CGFloat((times[i] - times[i0]) / dt)
                result[i] = v0 + t * (v1 - v0)
            }
        }
        return result
    }

    private func findPeaks(
        in arr: [CGFloat?],
        times: [Double],
        maxCandidateTime: Double,
        minDistanceSec: Double,
        prominence: CGFloat,
        findMax: Bool
    ) -> [Int] {
        guard arr.count >= 3 else { return [] }

        let signed: [CGFloat?] = findMax ? arr : arr.map { $0.map { -$0 } }
        var candidates: [(index: Int, value: CGFloat)] = []

        for i in 1..<(signed.count - 1) {
            guard times[i] <= maxCandidateTime else { break }
            guard let curr = signed[i],
                  let prev = signed[i - 1],
                  let next = signed[i + 1] else {
                continue
            }

            if curr > prev && curr >= next {
                let tCenter = times[i]
                var leftMin: CGFloat?
                var rightMin: CGFloat?

                var l = i - 1
                while l >= 0 && (tCenter - times[l]) <= prominenceWindowSec {
                    if let v = signed[l] {
                        leftMin = leftMin.map { min($0, v) } ?? v
                    }
                    l -= 1
                }

                var r = i + 1
                while r < signed.count && (times[r] - tCenter) <= prominenceWindowSec {
                    if let v = signed[r] {
                        rightMin = rightMin.map { min($0, v) } ?? v
                    }
                    r += 1
                }

                guard let lMin = leftMin, let rMin = rightMin else { continue }
                let prom = curr - max(lMin, rMin)

                if prom >= prominence {
                    candidates.append((i, curr))
                }
            }
        }

        let sortedByHeight = candidates.sorted { $0.value > $1.value }
        var selected: [Int] = []

        for cand in sortedByHeight {
            let candTime = times[cand.index]
            if selected.allSatisfy({ abs(times[$0] - candTime) >= minDistanceSec }) {
                selected.append(cand.index)
            }
        }

        return selected.sorted()
    }
}