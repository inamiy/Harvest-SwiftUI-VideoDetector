import UIKit
import AVFoundation

func captureDevice(forPosition position: AVCaptureDevice.Position) -> AVCaptureDevice?
{
    let discoverySession = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.builtInWideAngleCamera],
        mediaType: .video,
        position: .unspecified
    )
    return discoverySession.devices.first { $0.position == position }
}

extension AVCaptureDevice.Position: CustomStringConvertible
{
    mutating func toggle()
    {
        switch self {
        case .front:
            self = .back
        default:
            self = .front
        }
    }

    public var description: String
    {
        switch self {
        case .front:
            return "front"
        case .back:
            return "back"
        case .unspecified:
            return "unspecified"
        @unknown default:
            return "unknown"
        }
    }
}

// MARK: - Orientation

// For AVCaptureVideoPreviewLayer.
extension AVCaptureVideoOrientation
{
    init?(deviceOrientation: UIDeviceOrientation)
    {
        switch deviceOrientation {
        case .portrait:
            self = .portrait
        case .portraitUpsideDown:
            self = .portraitUpsideDown
        case .landscapeLeft:
            self = .landscapeRight
        case .landscapeRight:
            self = .landscapeLeft
        case .faceUp,
             .faceDown,
             .unknown:
            return nil
        @unknown default:
            return nil
        }
    }

    init?(interfaceOrientation: UIInterfaceOrientation)
    {
        switch interfaceOrientation {
        case .portrait:
            self = .portrait
        case .portraitUpsideDown:
            self = .portraitUpsideDown
        case .landscapeLeft:
            self = .landscapeLeft
        case .landscapeRight:
            self = .landscapeRight
        case .unknown:
            return nil
        @unknown default:
            return nil
        }
    }
}

func interfaceOrientation(deviceOrientation: UIDeviceOrientation) -> UIInterfaceOrientation
{
    switch deviceOrientation {
    case .portrait:
        return .portrait
    case .portraitUpsideDown:
        return .portraitUpsideDown
    case .landscapeLeft:
        return .landscapeRight
    case .landscapeRight:
        return .landscapeLeft
    case .faceUp,
         .faceDown,
         .unknown:
        return .unknown
    @unknown default:
        return .unknown
    }
}
