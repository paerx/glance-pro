import Foundation
import CoreGraphics

nonisolated struct EnrollmentCandidate: @unchecked Sendable {
    // Immutable, downscaled camera image. Never persisted or sent off-device.
    let image: CGImage
    let pose: EnrollmentPose
    let capturedAt: Date
    let boundingBox: CGRect
}

nonisolated struct PreparedEnrollmentSample: Sendable {
    let embedding: [Float]
    let pose: EnrollmentPose
    let quality: Float?
    let capturedAt: Date
}

nonisolated struct EnrollmentProcessingResult: Sendable {
    let samples: [PreparedEnrollmentSample]
    let missingPoses: Set<EnrollmentPose>
}

nonisolated enum EnrollmentSampleProcessor {
    /// Runs alongside supplemental live capture, on a cancellable background task. Only accepted
    /// candidates incur landmarks, alignment and ArcFace inference.
    static func process(_ candidates: [EnrollmentPose: [EnrollmentCandidate]],
                        pipeline: FaceRecognitionPipeline,
                        progress: @Sendable (Double) async -> Void) async throws -> EnrollmentProcessingResult {
        var accepted: [PreparedEnrollmentSample] = []
        var reference: [Float]?
        var done = 0
        let count = max(1, candidates.values.reduce(0) { $0 + $1.count })
        for pose in EnrollmentPose.allCases {
            var ranked: [PreparedEnrollmentSample] = []
            for candidate in candidates[pose] ?? [] {
                try Task.checkCancellation()
                // Vision failures reject this frame, not the whole collected turn.
                let result: FaceRecognitionResult? = autoreleasepool {
                    guard let faces = try? FaceDetector.detectFaces(in: candidate.image), faces.count == 1,
                          let face = faces.first,
                          EnrollmentCapturePolicy.isContinuous(face.normalizedBoundingBox, with: candidate.boundingBox),
                          let yaw = face.yaw, let pitch = face.pitch,
                          EnrollmentCapturePolicy.pose(yaw: yaw, pitch: pitch) == pose,
                          face.quality.map({ $0 >= 0.2 }) ?? true else { return nil }
                    return try? pipeline.recognize(face, in: candidate.image)
                }
                if let result, result.alignmentTier == .fivePoint {
                    // Prevent another person entering midway from contaminating the
                    // identity. This is a capture-consistency check, not an unlock.
                    let samePerson = reference.map { FaceEmbedding.cosineSimilarity($0, result.embedding) >= 0.5 } ?? (pose == .center)
                    if samePerson {
                        ranked.append(PreparedEnrollmentSample(embedding: result.embedding, pose: pose,
                                                              quality: result.quality, capturedAt: candidate.capturedAt))
                    }
                }
                done += 1
                await progress(Double(done) / Double(count))
            }
            let best = ranked.sorted { ($0.quality ?? 0) > ($1.quality ?? 0) }
                .prefix(EnrollmentCapturePolicy.requiredSamples(for: pose))
            accepted.append(contentsOf: best)
            if pose == .center {
                reference = best.first?.embedding
                // Without a valid front-facing anchor, the remainder cannot safely
                // be attributed yet. Keep the turn and supplement only the center angle.
                if reference == nil {
                    return EnrollmentProcessingResult(samples: [], missingPoses: [.center])
                }
            }
        }
        try Task.checkCancellation()
        let missing = Set(EnrollmentPose.allCases.filter { pose in
            accepted.filter { $0.pose == pose }.count < EnrollmentCapturePolicy.requiredSamples(for: pose)
        })
        return EnrollmentProcessingResult(samples: accepted, missingPoses: missing)
    }
}
