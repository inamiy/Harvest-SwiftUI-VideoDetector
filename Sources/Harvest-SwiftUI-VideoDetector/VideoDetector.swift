import UIKit
import AVFoundation
import Combine
import FunOptics
import Harvest
import HarvestOptics
import Harvest_SwiftUI_VideoCapture

/// VideoDetector namespace.
public enum VideoDetector {}

extension VideoDetector
{
    public enum Input
    {
        case _didDetectRects([CGRect])
        case _didDetectTexts([CGRect], [String], [UIImage])
        case _error(Error)
        case videoCapture(VideoCapture.Input)
    }

    public struct State
    {
        public var detectMode: DetectMode
        public var detectedRects: [CGRect]
        public var detectedTextImages: [UIImage]
        public var detectedTexts: [String]
        public var videoCapture: VideoCapture.State

        public init(
            detectMode: DetectMode = .textRect,
            detectedRects: [CGRect] = [],
            detectedTextImages: [UIImage] = [],
            detectedTexts: [String] = [],
            videoCapture: VideoCapture.State = .init(cameraPosition: .back)
        )
        {
            self.detectMode = detectMode
            self.detectedRects = detectedRects
            self.detectedTextImages = detectedTextImages
            self.detectedTexts = detectedTexts
            self.videoCapture = videoCapture
        }

        public enum DetectMode
        {
            case face
            case textRect
            case textRecognitionIOSVision
            case textRecognitionTesseract // Uses Japanese dictionary
        }
    }

    public static func effectMapping<S: Scheduler>() -> EffectMapping<S>
    {
        return .reduce(.all, [
            self._effectMapping(),

            VideoCapture.effectMapping()
                .contramapWorld { $0.videoCapture }
                .transform(input: .fromEnum(\.videoCapture))
                .transform(state: .init(lens: .init(\.videoCapture)))
        ])
    }

    private static func _effectMapping<S: Scheduler>() -> EffectMapping<S>
    {
        .makeInout { input, state in
            switch input {
            case let .videoCapture(._didOutput(cmSampleBuffer)):
                switch state.detectMode {
                case .face:
                    let publisher = detectFaces(
                        cmSampleBuffer: cmSampleBuffer,
                        deviceOrientation: state.videoCapture.deviceOrientation
                    )
                    .map { Input._didDetectRects($0.map { $0.boundingBox }) }
                    .catch { _ in Just(Input._error(.detectionFailed)) }

                    return Effect(publisher)

                case .textRect:
                    let publisher = detectTextRects(
                        cmSampleBuffer: cmSampleBuffer,
                        deviceOrientation: state.videoCapture.deviceOrientation
                    )
                    .map { Input._didDetectRects($0.map { $0.boundingBox }) }
                    .catch { _ in Just(Input._error(.detectionFailed)) }

                    return Effect(publisher)

                case .textRecognitionIOSVision:
                    let publisher = detectTextRecognition(
                        cmSampleBuffer: cmSampleBuffer,
                        deviceOrientation: state.videoCapture.deviceOrientation
                    )
                    .map {
                        Input._didDetectTexts(
                            $0.map { $0.boundingBox },
                            $0.flatMap { $0.topCandidates(3) }
                                .map { $0.string },
                            []
                        )
                    }
                    .catch { _ in Just(Input._error(.detectionFailed)) }

                    return Effect(publisher)

                case .textRecognitionTesseract:
                    let publisher = recognizeTextsUsingTesseract(
                        cmSampleBuffer: cmSampleBuffer,
                        deviceOrientation: state.videoCapture.deviceOrientation
                    )
                    .map { Input._didDetectTexts($0.map { $0.0 }, $0.map { $0.1 }, $0.compactMap { $0.2 }) }
                    .catch { _ in Just(Input._error(.detectionFailed)) }

                    return Effect(publisher)
                }

            case let ._didDetectRects(rects):
                state.detectedRects = rects
                    .map { convertBoundingBox($0, deviceOrientation: state.videoCapture.deviceOrientation) }
                state.detectedTexts = []
                state.detectedTextImages = []
                return .empty

            case let ._didDetectTexts(rects, texts, croppedImages):
                #if DEBUG
                if !rects.isEmpty {
                    print("===> _didDetectTexts = \(texts)")
                }
                #endif
                state.detectedRects = rects
                    .map { convertBoundingBox($0, deviceOrientation: state.videoCapture.deviceOrientation) }
                if !croppedImages.isEmpty {
                    state.detectedTextImages = croppedImages
                }
                state.detectedTexts = texts
                return .empty

            default:
                return nil
            }
        }
    }

    public typealias EffectMapping<S: Scheduler> = Harvester<Input, State>.EffectMapping<World<S>, EffectQueue, EffectID>

    public typealias Effect<S: Scheduler> = Harvest.Effect<World<S>, Input, EffectQueue, EffectID>

    public typealias EffectQueue = BasicEffectQueue

    public typealias EffectID = VideoCapture.EffectID

    public struct World<S: Scheduler>
    {
        var videoCapture: VideoCapture.World<S>

        public init(videoCapture: VideoCapture.World<S>)
        {
            self.videoCapture = videoCapture
        }
    }
}

// MARK: - Enum Properties

extension VideoDetector.Input
{
    var videoCapture: VideoCapture.Input?
    {
        get {
            guard case let .videoCapture(value) = self else { return nil }
            return value
        }
        set {
            guard case .videoCapture = self, let newValue = newValue else { return }
            self = .videoCapture(newValue)
        }
    }
}
