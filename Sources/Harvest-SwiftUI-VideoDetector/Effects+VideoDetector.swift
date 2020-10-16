import UIKit
import AVFoundation
import Vision
import Combine
import SwiftyTesseract
import FunOptics
import Harvest
import HarvestOptics
import Harvest_SwiftUI_VideoCapture

private enum Global
{
    private static let queuePrefix = "com.inamiy.Harvest-SwiftUI-VideoDetector"
    static let textDetectionQueue = DispatchQueue(label: "\(queuePrefix).textDetectionQueue", qos: .userInteractive)
    static let tesseractQueue = DispatchQueue(label: "\(queuePrefix).tesseractQueue", qos: .userInteractive)
}

// MARK: - iOS Vision

/// Uses `VNDetectTextRectanglesRequest`.
func detectTextRects(cmSampleBuffer: CMSampleBuffer) -> AnyPublisher<[VNTextObservation], Swift.Error>
{
    Deferred { () -> AnyPublisher<[VNTextObservation], Swift.Error> in
        let passthrough = PassthroughSubject<[VNTextObservation], Swift.Error>()

        let request = VNDetectTextRectanglesRequest { request, error in
            if let error = error {
                passthrough.send(completion: .failure(error))
                return
            }

            if let results = request.results as? [VNTextObservation] {
                passthrough.send(results)
                passthrough.send(completion: .finished)
            }
        }
        request.reportCharacterBoxes = false

        let pixelBuffer: CVPixelBuffer = CMSampleBufferGetImageBuffer(cmSampleBuffer)!
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer)

        // NOTE: Run async to return `passthrough` first.
        Global.textDetectionQueue.async {
            do {
                try handler.perform([request]) // synchronous
            }
            catch {
                passthrough.send(completion: .failure(error))
            }
        }

        return passthrough.eraseToAnyPublisher()
    }
    .receive(on: DispatchQueue.main)
    .eraseToAnyPublisher()
}

/// Uses `VNRecognizeTextRequest`.
func detectTextRecognition(cmSampleBuffer: CMSampleBuffer) -> AnyPublisher<[VNRecognizedTextObservation], Swift.Error>
{
    Deferred { () -> AnyPublisher<[VNRecognizedTextObservation], Swift.Error> in
        let passthrough = PassthroughSubject<[VNRecognizedTextObservation], Swift.Error>()

        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                passthrough.send(completion: .failure(error))
                return
            }

            if let results = request.results as? [VNRecognizedTextObservation] {
                passthrough.send(results)
                passthrough.send(completion: .finished)
            }
        }
        request.recognitionLevel = .fast

        let pixelBuffer: CVPixelBuffer = CMSampleBufferGetImageBuffer(cmSampleBuffer)!
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer)

        // NOTE: Run async to return `passthrough` first.
        Global.textDetectionQueue.async {
            do {
                try handler.perform([request]) // synchronous
            }
            catch {
                passthrough.send(completion: .failure(error))
            }
        }

        return passthrough.eraseToAnyPublisher()
    }
    .receive(on: DispatchQueue.main)
    .eraseToAnyPublisher()
}

/// Uses `VNDetectFaceRectanglesRequest`.
func detectFaces(cmSampleBuffer: CMSampleBuffer) -> AnyPublisher<[VNFaceObservation], Swift.Error>
{
    Deferred { () -> AnyPublisher<[VNFaceObservation], Swift.Error> in
        let passthrough = PassthroughSubject<[VNFaceObservation], Swift.Error>()

        let request = VNDetectFaceRectanglesRequest { request, error in
            if let error = error {
                passthrough.send(completion: .failure(error))
                return
            }

            if let results = request.results as? [VNFaceObservation] {
                passthrough.send(results)
                passthrough.send(completion: .finished)
            }
        }

        let pixelBuffer: CVPixelBuffer = CMSampleBufferGetImageBuffer(cmSampleBuffer)!

        // For `detectFaces`, orientation = `.up` will work for both portrait & landscape.
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        // NOTE: Run async to return `passthrough` first.
        Global.textDetectionQueue.async {
            do {
                try handler.perform([request]) // synchronous
            }
            catch {
                passthrough.send(completion: .failure(error))
            }
        }

        return passthrough.eraseToAnyPublisher()
    }
    .receive(on: DispatchQueue.main)
    .eraseToAnyPublisher()
}

// MARK: - Tesseract

/// Uses SwiftyTesseract.
/// - Flow: `detectTextRects` (iOS Vision) -> Tesseract
func recognizeTextsUsingTesseract(cmSampleBuffer: CMSampleBuffer)
-> AnyPublisher<[TesseractResult], VideoDetector.Error>
{
    detectTextRects(cmSampleBuffer: cmSampleBuffer)
        .mapError(VideoDetector.Error.iOSVision)
        .map { Array($0.prefix(3)) }    // limit to 3 detections
        .flatMap { textObservations in
            _recognizeTextsUsingTesseract(
                cmSampleBuffer: cmSampleBuffer,
                textObservations: textObservations
            )
        }
        .eraseToAnyPublisher()
}

/// Runs a single Tesseract OCR.
private func runTesseract(cmSampleBuffer: CMSampleBuffer) -> AnyPublisher<String, VideoDetector.Error>
{
    guard let image = cmSampleBuffer.uiImage else { return .empty }

    // For debugging.
    #if DEBUG
    if tesseractFlag == .none {
        return Result.Publisher(.success("noop")).eraseToAnyPublisher()
    }
    #endif

    let tesseract = Tesseract(languages: [.japanese])
    return tesseract.performOCRPublisher(on: image)
        .subscribe(on: Global.tesseractQueue)
        .mapError(VideoDetector.Error.tesseract)
        .eraseToAnyPublisher()
}

/// Uses Tesseract multiple times after text-rectangles are detected.
private func _recognizeTextsUsingTesseract(cmSampleBuffer: CMSampleBuffer, textObservations: [VNTextObservation])
-> AnyPublisher<[TesseractResult], VideoDetector.Error>
{
    if textObservations.isEmpty {
        return Result.Publisher(.success([]))
            .eraseToAnyPublisher()
    }

    let runners = textObservations
        .map { textObservation -> AnyPublisher<TesseractResult, VideoDetector.Error> in
            guard let croppedBuffer = cmSampleBuffer.cropped(rect0To1: textObservation.boundingBox) else {
                return Fail(outputType: TesseractResult.self, failure: .detectionFailed)
                    .eraseToAnyPublisher()
            }

            return runTesseract(cmSampleBuffer: croppedBuffer)
                // NOTE: Pass unchanged `boundingBox` which will be handled by `VideoPreviewView`.
                .map { (textObservation.boundingBox, $0, croppedBuffer.uiImage) }
                .eraseToAnyPublisher()
        }

    return Publishers.Sequence(sequence: runners)
        .flatMap { $0 }
        .collect()
        .eraseToAnyPublisher()
}

// MARK: - VideoDetector.Error

extension VideoDetector
{
    public enum Error: Swift.Error
    {
        case detectionFailed
        case iOSVision(Swift.Error)
        case tesseract(Tesseract.Error)
        case videoCapture(VideoCapture.Error)
    }
}

// MARK: - Internal Types

typealias TesseractResult = (CGRect, String, UIImage?)

#if DEBUG
private enum TesseractRecognitionMode
{
    case none
    case recognize
}

private let tesseractFlag = TesseractRecognitionMode.recognize
#endif
