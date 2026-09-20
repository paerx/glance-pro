// Compile with EnrollmentPose, EnrollmentCapturePolicy, EnrollmentSampleProcessor
// and FaceEmbedder.swift. Vision/model results are deterministic test doubles;
// no camera, photo files, enrollment store or real biometric data is accessed.
import Foundation
import CoreGraphics

nonisolated enum AlignmentTier { case fivePoint, twoPoint }
nonisolated struct DetectedFace {
    var normalizedBoundingBox = CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4)
    var quality: Float? = 0.9
    var yaw: Float?
    var pitch: Float?
    var tier = AlignmentTier.fivePoint
    var embedding: [Float] = [1, 0]
}
nonisolated enum FaceDetector {
    static var fixtures: [Int: [DetectedFace]] = [:]
    static func detectFaces(in image: CGImage) throws -> [DetectedFace] { fixtures[image.width] ?? [] }
}
nonisolated struct FaceRecognitionResult {
    let embedding: [Float]
    let quality: Float?
    let alignmentTier: AlignmentTier
}
nonisolated final class FaceRecognitionPipeline: Sendable {
    func recognize(_ face: DetectedFace, in image: CGImage) throws -> FaceRecognitionResult {
        FaceRecognitionResult(embedding: face.embedding, quality: face.quality, alignmentTier: face.tier)
    }
}
actor ProgressLog {
    var values: [Double] = []
    func append(_ value: Double) { values.append(value) }
}

@main struct EnrollmentSelfTest {
    static var checks = 0
    static func check(_ value: @autoclosure () -> Bool, _ label: String) {
        precondition(value(), label); checks += 1
    }
    static let angles: [(Float, Float)] = [(0, 0), (0.35, 0), (0.35, -0.28), (0, -0.28),
                                          (-0.35, -0.28), (-0.35, 0), (-0.35, 0.28), (0, 0.28), (0.35, 0.28)]
    static func batch() -> [EnrollmentPose: [EnrollmentCandidate]] {
        FaceDetector.fixtures = [:]
        var output: [EnrollmentPose: [EnrollmentCandidate]] = [:]
        for pose in EnrollmentPose.allCases {
            let (yaw, pitch) = angles[pose.rawValue]
            let count = pose == .center ? 1 : 4
            for index in 0..<count {
                let width = 10 + pose.rawValue * 4 + index
                let data = Data(repeating: 0, count: width * 4)
                let image = CGImage(width: width, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
                                    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                    provider: CGDataProvider(data: data as CFData)!, decode: nil, shouldInterpolate: false,
                                    intent: .defaultIntent)!
                let face = DetectedFace(quality: [0.3, 0.9, 0.4, 0.7][index], yaw: yaw, pitch: pitch)
                FaceDetector.fixtures[width] = [face]
                output[pose, default: []].append(EnrollmentCandidate(image: image, pose: pose,
                    capturedAt: Date(timeIntervalSince1970: Double(width)), boundingBox: face.normalizedBoundingBox))
            }
        }
        return output
    }
    static func main() async throws {
        for pose in EnrollmentPose.allCases {
            let (yaw, pitch) = angles[pose.rawValue]
            check(EnrollmentCapturePolicy.pose(yaw: yaw, pitch: pitch) == pose, "pose \(pose)")
        }
        check(EnrollmentCapturePolicy.pose(yaw: .nan, pitch: 0) == nil, "invalid orientation rejected")
        check(EnrollmentCapturePolicy.pose(yaw: 1.1, pitch: 0) == nil, "extreme angle rejected")
        check(EnrollmentCapturePolicy.pose(yaw: 0.18, pitch: 0) == nil, "boundary dead zone")
        let box = CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4)
        check(EnrollmentCapturePolicy.isContinuous(box.offsetBy(dx: 0.02, dy: 0), with: box), "natural movement")
        check(!EnrollmentCapturePolicy.isContinuous(box.offsetBy(dx: 0.4, dy: 0), with: box), "face jump rejected")
        let pipeline = FaceRecognitionPipeline()
        let progress = ProgressLog()
        let good = batch()
        let prepared = try await EnrollmentSampleProcessor.process(good, pipeline: pipeline) { await progress.append($0) }
        check(prepared.samples.count == 17 && prepared.missingPoses.isEmpty, "one front + two samples for each of eight directions")
        for pose in EnrollmentPose.allCases where pose != .center {
            let quality = prepared.samples.filter { $0.pose == pose }.map { $0.quality! }
            check(quality == [0.9, 0.7], "best quality samples selected")
        }
        let steps = await progress.values
        check(steps.last == 1 && zip(steps, steps.dropFirst()).allSatisfy { $0 <= $1 }, "monotonic processing progress")

        var missing = batch()
        missing[.left] = []
        let partial = try await EnrollmentSampleProcessor.process(missing, pipeline: pipeline) { _ in }
        check(partial.missingPoses == [.left] && partial.samples.count == 15, "only missing direction requested")

        let blurry = batch()
        for sample in blurry[.right]! { FaceDetector.fixtures[sample.image.width]![0].quality = 0.1 }
        let rejected = try await EnrollmentSampleProcessor.process(blurry, pipeline: pipeline) { _ in }
        check(rejected.missingPoses == [.right], "blurry direction rejected")

        let switched = batch()
        for sample in switched[.top]! { FaceDetector.fixtures[sample.image.width]![0].embedding = [0, 1] }
        let mixed = try await EnrollmentSampleProcessor.process(switched, pipeline: pipeline) { _ in }
        check(mixed.missingPoses == [.top], "different identity not mixed into template")

        let unaligned = batch()
        for sample in unaligned[.bottom]! { FaceDetector.fixtures[sample.image.width]![0].tier = .twoPoint }
        let fallback = try await EnrollmentSampleProcessor.process(unaligned, pipeline: pipeline) { _ in }
        check(fallback.missingPoses == [.bottom], "five-point alignment still required")

        let noAnchor = batch()
        FaceDetector.fixtures[noAnchor[.center]!.first!.image.width] = []
        let restart = try await EnrollmentSampleProcessor.process(noAnchor, pipeline: pipeline) { _ in }
        check(restart.samples.isEmpty && restart.missingPoses == [.center], "invalid anchor requests only supplemental center frames")

        let cancellationBatch = batch()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await EnrollmentSampleProcessor.process(cancellationBatch, pipeline: pipeline) { _ in }
        }
        do { _ = try await task.value; preconditionFailure("Cancellation ignored") }
        catch is CancellationError { checks += 1 }
        print("PASS: \(checks) capture/processing checks; no real camera or face data accessed")
    }
}
