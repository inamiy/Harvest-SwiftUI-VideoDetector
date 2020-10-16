import SwiftUI
import Harvest
import HarvestStore
import Harvest_SwiftUI_VideoCapture
import Harvest_SwiftUI_VideoDetector

@main
struct DemoApp: App
{
    @StateObject
    var store = Store<VideoDetector.Input, VideoDetector.State>(
        state: VideoDetector.State(),
        mapping: VideoDetector.effectMapping(),
        world: makeRealWorld()
    )

    var body: some Scene
    {
        WindowGroup {
            ContentView(store: store.proxy)
        }
    }
}

private func makeRealWorld() -> VideoDetector.World<DispatchQueue>
{
    VideoDetector.World<DispatchQueue>(
        videoCapture: VideoCapture.World()
    )
}
