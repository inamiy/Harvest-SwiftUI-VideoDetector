import AVFoundation
import Combine
import FunOptics
import Harvest
import HarvestOptics

/// VideoCapture namespace.
public enum VideoCapture {}

extension VideoCapture
{
    public enum Input
    {
        case makeSession
        case _didMakeSession(SessionID)
        case startSession
        case _didOutput(CMSampleBuffer)
        case changeCameraPosition
        case stopSession
        case _didStopSession
        case _error(Error)
        case removeSession
    }

    public struct State
    {
        var cameraPosition: AVCaptureDevice.Position
        public var sessionState: SessionState

        public init(
            cameraPosition: AVCaptureDevice.Position = .front,
            sessionState: SessionState = .noSession
        )
        {
            self.cameraPosition = cameraPosition
            self.sessionState = sessionState
        }

        public enum SessionState: CustomStringConvertible
        {
            case noSession
            case idle(SessionID)
            case running(SessionID)

            public var sessionID: SessionID?
            {
                switch self {
                case .noSession:
                    return nil
                case let .idle(sessionID),
                     let .running(sessionID):
                    return sessionID
                }
            }

            public var description: String
            {
                switch self {
                case .noSession:
                    return "noSession"
                case .idle:
                    return "idle"
                case .running:
                    return "running"
                }
            }
        }
    }

    public static func effectMapping<S: Scheduler>() -> EffectMapping<S>
    {
        .reduce(.all, [
            self._effectMapping(),
        ])
    }

    private static func _effectMapping<S: Scheduler>() -> EffectMapping<S>
    {
        .makeInout { input, state in
            switch input {
            case .makeSession:
                let publisher = makeSession(cameraPosition: state.cameraPosition)
                    .map(Input._didMakeSession)
                    .catch { Just(Input._error($0)) }
                return Effect(publisher)

            case let ._didMakeSession(sessionID):
                state.sessionState = .idle(sessionID)
                return Effect(Just(.startSession))

            case .startSession:
                guard case let .idle(sessionID) = state.sessionState else {
                    return .empty
                }

                state.sessionState = .running(sessionID)

                let publisher = startSession(sessionID: sessionID)
                    .map(Input._didOutput)
                    .catch { Just(Input._error($0))}
                return Effect(publisher)

            case ._didOutput:
                // Ignored: Composing reducer should handle this.
                return .empty

            case .changeCameraPosition:
                guard let sessionID = state.sessionState.sessionID else {
                    return .empty
                }
                state.cameraPosition.toggle()

                let publisher = setupCaptureSessionInput(
                    sessionID: sessionID,
                    cameraPosition: state.cameraPosition
                )
                .compactMap { _ in nil }
                .catch { Just(Input._error($0))}

                return Effect(publisher)

            case .stopSession:
                guard case let .running(sessionID) = state.sessionState else {
                    return .empty
                }

                let publisher = stopSession(sessionID: sessionID)
                    .map { _ in Input._didStopSession }
                    .catch { Just(Input._error($0))}
                return Effect(publisher)

            case ._didStopSession:
                guard case let .running(sessionID) = state.sessionState else {
                    return .empty
                }
                state.sessionState = .idle(sessionID)
                return .empty

            case let ._error(error):
                let publisher = log("\(error)")
                    .flatMap { Empty<Input, Never>(completeImmediately: true) }
                return Effect(publisher)

            case .removeSession:
                if case .noSession = state.sessionState {
                    return .empty
                }
                state.sessionState = .noSession

                let publisher = removeSession()
                    .flatMap { Empty<Input, Never>(completeImmediately: true) }
                return Effect(publisher)
            }
        }
    }

    public typealias EffectMapping<S: Scheduler> = Harvester<Input, State>.EffectMapping<World<S>, EffectQueue, EffectID>

    public typealias Effect<S: Scheduler> = Harvest.Effect<World<S>, Input, EffectQueue, EffectID>

    public typealias EffectQueue = BasicEffectQueue

    public typealias EffectID = Never

    public struct World<S: Scheduler>
    {
        public init() {}
    }
}

// MARK: - Enum Properties

extension VideoCapture.State.SessionState
{
    public var isRunning: Bool
    {
        guard case .running = self else { return false }
        return true
    }
}
