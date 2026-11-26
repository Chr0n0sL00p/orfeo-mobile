import UIKit
import AVFoundation
import MediaPlayer
import WebKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    var webView: WKWebView!

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // 1. Configure AVAudioSession for background music playback
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetooth, .allowBluetoothA2DP])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set AVAudioSession category: \(error)")
        }

        // 2. Setup MPRemoteCommandCenter (iOS Lockscreen / Control Center / Carplay)
        setupRemoteCommands()

        // 3. Initialize Main Window & Native WebView Shell
        window = UIWindow(frame: UIScreen.main.bounds)
        let viewController = MainViewController()
        window?.rootViewController = viewController
        window?.makeKeyAndVisible()

        return true
    }

    private func setupRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.notifyWeb("togglePlay()")
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.notifyWeb("togglePlay()")
            return .success
        }

        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.notifyWeb("nextTrack()")
            return .success
        }

        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.notifyWeb("prevTrack()")
            return .success
        }

        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let posEvent = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.notifyWeb("seekAudioExact(\(posEvent.positionTime))")
            return .success
        }
    }

    private func notifyWeb(_ js: String) {
        DispatchQueue.main.async {
            guard let vc = self.window?.rootViewController as? MainViewController else { return }
            vc.webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}

class MainViewController: UIViewController, WKScriptMessageHandler, WKNavigationDelegate {
    var webView: WKWebView!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        
        let contentController = WKUserContentController()
        contentController.add(self, name: "orfeoNative")
        config.userContentController = contentController

        webView = WKWebView(frame: view.bounds, configuration: config)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = self
        view.addSubview(webView)

        // Load bundled frontend assets
        if let htmlPath = Bundle.main.path(forResource: "index", ofType: "html", inDirectory: "frontend") {
            let fileUrl = URL(fileURLWithPath: htmlPath)
            webView.loadFileURL(fileUrl, allowingReadAccessTo: fileUrl.deletingLastPathComponent())
        } else {
            // Fallback load local index.html directly
            if let htmlPath = Bundle.main.path(forResource: "index", ofType: "html") {
                let fileUrl = URL(fileURLWithPath: htmlPath)
                webView.loadFileURL(fileUrl, allowingReadAccessTo: fileUrl.deletingLastPathComponent())
            }
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let action = body["action"] as? String else { return }

        switch action {
        case "haptic":
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()

        case "updateNowPlaying":
            var info = [String: Any]()
            if let title = body["title"] as? String { info[MPMediaItemPropertyTitle] = title }
            if let artist = body["artist"] as? String { info[MPMediaItemPropertyArtist] = artist }
            if let duration = body["duration"] as? Double { info[MPMediaItemPropertyPlaybackDuration] = duration }
            if let elapsed = body["elapsed"] as? Double { info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed }
            info[MPNowPlayingInfoPropertyPlaybackRate] = (body["isPlaying"] as? Bool ?? true) ? 1.0 : 0.0
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        default:
            break
        }
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
}
