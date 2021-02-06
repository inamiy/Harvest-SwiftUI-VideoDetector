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
func detectTextRects(
    cmSampleBuffer: CMSampleBuffer,
    deviceOrientation: UIDeviceOrientation
) -> AnyPublisher<[VNTextObservation], Swift.Error>
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

        let pixelBuffer = CMSampleBufferGetImageBuffer(cmSampleBuffer)!

        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: deviceOrientation.estimatedImageOrientation?.cgImagePropertyOrientation ?? .up
        )

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
func detectTextRecognition(
    cmSampleBuffer: CMSampleBuffer,
    deviceOrientation: UIDeviceOrientation
) -> AnyPublisher<[VNRecognizedTextObservation], Swift.Error>
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

        let pixelBuffer = CMSampleBufferGetImageBuffer(cmSampleBuffer)!

        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: deviceOrientation.estimatedImageOrientation?.cgImagePropertyOrientation ?? .up
        )

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
func detectFaces(cmSampleBuffer: CMSampleBuffer, deviceOrientation: UIDeviceOrientation) -> AnyPublisher<[VNFaceObservation], Swift.Error>
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

        let pixelBuffer = CMSampleBufferGetImageBuffer(cmSampleBuffer)!

        // For `detectFaces`, orientation = `.up` will work for both portrait & landscape.
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: deviceOrientation.estimatedImageOrientation?.cgImagePropertyOrientation ?? .up,
            options: [:]
        )

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
func recognizeTextsUsingTesseract(
    cmSampleBuffer: CMSampleBuffer,
    deviceOrientation: UIDeviceOrientation
) -> AnyPublisher<[TesseractResult], VideoDetector.Error>
{
    detectTextRects(cmSampleBuffer: cmSampleBuffer, deviceOrientation: deviceOrientation)
        .mapError(VideoDetector.Error.iOSVision)
        .map { Array($0.prefix(3)) }    // limit to 3 detections
        .flatMap { textObservations in
            _recognizeTextsUsingTesseract(
                cmSampleBuffer: cmSampleBuffer,
                textObservations: textObservations,
                deviceOrientation: deviceOrientation
            )
        }
        .receive(on: DispatchQueue.main)
        .eraseToAnyPublisher()
}

/// Runs a single Tesseract OCR.
private func runTesseract(
    cmSampleBuffer: CMSampleBuffer,
    deviceOrientation: UIDeviceOrientation
) -> AnyPublisher<(detectedText: String, image: UIImage), VideoDetector.Error>
{
    guard let image = cmSampleBuffer.uiImage(deviceOrientation: deviceOrientation) else { return .empty }

    // For debugging.
    #if DEBUG
    if !isTesseractEnabled {
        return Result.Publisher(.success(("noop", UIImage()))).eraseToAnyPublisher()
    }
    #endif

    let tesseract = Tesseract(languages: [.japanese])

    return tesseract.performOCRPublisher(on: image)
        .subscribe(on: Global.tesseractQueue)
        .mapError(VideoDetector.Error.tesseract)
        .map { ($0, image) }
        .eraseToAnyPublisher()
}

/// Uses Tesseract multiple times after text-rectangles are detected.
private func _recognizeTextsUsingTesseract(
    cmSampleBuffer: CMSampleBuffer,
    textObservations: [VNTextObservation],
    deviceOrientation: UIDeviceOrientation
) -> AnyPublisher<[TesseractResult], VideoDetector.Error>
{
    if textObservations.isEmpty {
        return Result.Publisher(.success([]))
            .eraseToAnyPublisher()
    }

    let runners = textObservations
        .map { textObservation -> AnyPublisher<TesseractResult, VideoDetector.Error> in
            /// - Note: In current orientation's coordinate, bottom-left origin.
            let boundingBox = textObservation.boundingBox

            /// - Note: In camera's coordinate, top-left origin.
            let boundingBoxInCamera = convertBoundingBox(boundingBox, deviceOrientation: deviceOrientation)

            guard let croppedBuffer = cmSampleBuffer.cropped(boundingBox: boundingBoxInCamera) else {
                return Fail(outputType: TesseractResult.self, failure: .detectionFailed)
                    .eraseToAnyPublisher()
            }

            return runTesseract(cmSampleBuffer: croppedBuffer, deviceOrientation: deviceOrientation)
                .map { (boundingBox, $0, $1) }
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
private let isTesseractEnabled = true
#endif

// MARK: - Vision boundingBox conversion

/// - Parameters:
///   - boundingBox: `CGRect` that has scale values from 0 to 1 in current device orientation's coordinate with bottom-left origin.
///   - deviceOrientation: Current device orientation.
/// - Returns: A new bounding box that has top-left origin in camera's coordinate, e.g. for passing to `AVCaptureVideoPreviewLayer.layerRectConverted`.
func convertBoundingBox(_ boundingBox: CGRect, deviceOrientation: UIDeviceOrientation) -> CGRect
{
    var boundingBox = boundingBox

    // Flip y-axis as `boundingBox.origin` starts from bottom-left.
    boundingBox.origin.y = 1 - boundingBox.origin.y - boundingBox.height

    switch deviceOrientation {
    case .portrait:
        // 90 deg clockwise
        boundingBox = boundingBox
            .applying(CGAffineTransform(translationX: -0.5, y: -0.5))
            .applying(CGAffineTransform(rotationAngle: -.pi / 2))
            .applying(CGAffineTransform(translationX: 0.5, y: 0.5))
    case .portraitUpsideDown:
        // 90 deg counter-clockwise
        boundingBox = boundingBox
            .applying(CGAffineTransform(translationX: -0.5, y: -0.5))
            .applying(CGAffineTransform(rotationAngle: .pi / 2))
            .applying(CGAffineTransform(translationX: 0.5, y: 0.5))
    case .landscapeLeft:
        break
    case .landscapeRight:
        // 180 deg
        boundingBox = boundingBox
            .applying(CGAffineTransform(translationX: -0.5, y: -0.5))
            .applying(CGAffineTransform(rotationAngle: .pi))
            .applying(CGAffineTransform(translationX: 0.5, y: 0.5))
    case .unknown,
         .faceUp,
         .faceDown:
        break
    @unknown default:
        break
    }

    return boundingBox
}
