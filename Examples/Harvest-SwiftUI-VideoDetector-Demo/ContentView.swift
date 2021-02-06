import SwiftUI
import HarvestStore
import Harvest_SwiftUI_VideoCapture
import Harvest_SwiftUI_VideoDetector
import ImagePlaceholder

struct ContentView: View
{
    private let store: Store<VideoDetector.Input, VideoDetector.State>.Proxy

    init(store: Store<VideoDetector.Input, VideoDetector.State>.Proxy)
    {
        self.store = store
    }

    var body: some View
    {
        Group {
            // Has session
            if let sessionID = self.captureState.sessionState.sessionID {
                ZStack(alignment: .bottom) {
                    Color.black.opacity(0.5).ignoresSafeArea()

                    VideoPreviewView(
                        sessionID: sessionID,
                        detectedRects: store.state.detectedRects
                    )
                    .map { $0.ignoresSafeArea() }

                    self.controlView()
                }
            }
            // No session
            else {
                ZStack(alignment: .center) {
                    self.noSessionView()
                }
            }
        }
        .onAppear {
            self.sendToCapture(.makeSession)
        }
    }

    func controlView() -> some View
    {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ForEach(store.state.detectedTextImages, id: \.self) {
                    Image(uiImage: $0)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 100, height: 100, alignment: .center)
                        .border(Color.yellow)
                }
            }

            Picker("Detector Mode", selection: store.$state.detectMode) {
                Text("Face").tag(VideoDetector.State.DetectMode.face)
                Text("Text Rect").tag(VideoDetector.State.DetectMode.textRect)
                Text("Vision").tag(VideoDetector.State.DetectMode.textRecognitionIOSVision)
                Text("Tesseract").tag(VideoDetector.State.DetectMode.textRecognitionTesseract)
            }
            .pickerStyle(SegmentedPickerStyle())

            switch store.state.detectMode {
            case .textRecognitionIOSVision,
                 .textRecognitionTesseract:
                Text("\(store.state.detectedTexts.count): \(store.state.detectedTexts.joined(separator: ", "))")
                    .lineLimit(3)
                    .font(.title3)
                    .padding()
            default:
                Text(self.captureState.sessionState.description + ", detect = \(store.state.detectedRects.count)")
                    .lineLimit(3)
                    .font(.title3)
                    .padding()
            }

            HStack {
                Button { self.sendToCapture(.removeSession) }
                    label: { Image(systemName: "bolt.slash") }
                    .font(.title)

                Spacer()

                if case .running = self.captureState.sessionState {
                    Button { self.sendToCapture(.stopSession) }
                        label: { Image(systemName: "stop.circle") }
                        .font(.title)
                }
                else {
                    Button { self.sendToCapture(.startSession) }
                        label: { Image(systemName: "play.circle") }
                        .font(.title)
                }

                Spacer()

                Button { self.sendToCapture(.changeCameraPosition) }
                    label: { Image(systemName: "camera.rotate") }
                    .font(.title)
            }
        }
        .padding()
        .background(
            Color(white: 1, opacity: 0.75)
                .edgesIgnoringSafeArea(.all)
        )
    }

    func noSessionView() -> some View
    {
        VStack(spacing: 10) {
            // Status
            Text(self.captureState.sessionState.description)
                .font(.title)

            Button { self.sendToCapture(.makeSession) }
                label: {
                    Image(systemName: "bolt")
                    Text("Make Session")
                }
            .font(.title)
        }
        .background(
            Color(white: 1, opacity: 0.75)
                .edgesIgnoringSafeArea(.all)
        )
    }

    // MARK: - Helpers

    var captureState: VideoCapture.State
    {
        self.store.state.videoCapture
    }

    func sendToCapture(_ input: VideoCapture.Input)
    {
        self.store.send(.videoCapture(input))
    }
}

// MARK: - Preview

struct ContentView_Previews: PreviewProvider
{
    static var previews: some View
    {
        let sessionID = SessionID.testID

        func makeView(sessionState: VideoCapture.State.SessionState) -> some View {
            ContentView(
                store: .init(
                    state: .constant(
                        VideoDetector.State(
                            detectMode: .face,
                            detectedRects: [.zero, .zero],
                            detectedTextImages: [
                                .placeholder(size: CGSize(width: 200, height: 100), theme: .gray),
                                .placeholder(size: CGSize(width: 150, height: 150), theme: .social),
                                .placeholder(size: CGSize(width: 100, height: 200), theme: .industrial)
                            ],
                            detectedTexts: [],
                            videoCapture: .init(sessionState: sessionState)
                        )
                    ),
                    send: { _ in }
                )
            )
        }

        return Group {
            let sessionState: VideoCapture.State.SessionState
                = .running(sessionID)
//                = .noSession

            makeView(sessionState: sessionState)
                .previewDevice("iPhone 11 Pro")

//            makeView(sessionState: .idle(sessionID))
//                .previewLayout(.fixed(width: 320, height: 480))
//
//            makeView(sessionState: .running(sessionID))
//                .previewLayout(.fixed(width: 480, height: 320))
//                .previewDisplayName("Landscape")
//
//            makeView(sessionState: .noSession)
//                .previewLayout(.fixed(width: 320, height: 480))
        }
    }
}
