import UIKit
import AVFoundation
import MediaPlayer
import WebKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    var mainVC: MainViewController?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // 1. Audio Session for Continuous Background Playback & Interruption Handling
        // NOTE: AVAudioSessionCategoryPlayback natively routes to Bluetooth and AirPlay.
        // DO NOT pass allowBluetooth or allowBluetoothA2DP here as it raises an uncatchable Objective-C NSInvalidArgumentException!
        setupAudioSession()

        // 2. Lockscreen & Control Center Remote Controls
        setupRemoteCommands()

        // 3. Initialize Main View Controller
        window = UIWindow(frame: UIScreen.main.bounds)
        let vc = MainViewController()
        self.mainVC = vc
        window?.rootViewController = vc
        window?.makeKeyAndVisible()

        // 4. Background Silent OTA Check against Odiseo (No cables required!)
        OrfeoOTAUpdater.shared.checkForUpdates(mainVC: vc)

        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {}
        notifyWeb("onNativeAppDidBecomeActive()")
    }

    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[Orfeo] AudioSession setup error: \(error)")
        }

        // Observar interrupciones de audio (audios de WhatsApp, videos de YouTube/Instagram, llamadas)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )

        // Observar desconexión de auriculares / AirPods
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    @objc private func handleAudioInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let interruptionType = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch interruptionType {
        case .began:
            print("[Orfeo] Interrupción de audio iniciada (audio o video externo en reproducción)")
            notifyWeb("onNativeAudioInterruption(true)")

        case .ended:
            print("[Orfeo] Interrupción de audio finalizada")
            var shouldResume = true
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                shouldResume = options.contains(.shouldResume)
            }

            // Reactivar inmediatamente la sesión de audio del sistema
            do {
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                print("[Orfeo] Error reactivando AVAudioSession tras interrupción: \(error)")
            }

            // Notificar al reproductor web para que reanude automáticamente
            notifyWeb("onNativeAudioInterruption(false, \(shouldResume))")

        @unknown default:
            break
        }
    }

    @objc private func handleAudioRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        if reason == .oldDeviceUnavailable {
            print("[Orfeo] Dispositivo de salida desconectado (auriculares/AirPods). Pausando.")
            notifyWeb("onNativeAudioInterruption(true)")
        }
    }

    private func setupRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { [weak self] _ in
            do {
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                print("[Orfeo] AudioSession reactivation error on playCommand: \(error)")
            }
            self?.notifyWeb("togglePlay(true)")
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.notifyWeb("togglePlay(false)")
            return .success
        }

        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            do {
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {}
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
        DispatchQueue.main.async { [weak self] in
            self?.mainVC?.webView?.evaluateJavaScript(js) { _, error in
                if let error = error {
                    print("[Orfeo Native] JS Error on '\(js)': \(error.localizedDescription)")
                }
            }
        }
    }
}

// MARK: - Main UI & WKWebView Shell
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

        loadActiveBundle()
    }

    func loadActiveBundle() {
        // Priority 1: Updated bundle in Documents (downloaded via OTA)
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let otaIndex = docs.appendingPathComponent("OrfeoLive/index.html")

        if FileManager.default.fileExists(atPath: otaIndex.path) {
            print("[Orfeo OTA] Cargando versión actualizada desde Documents/OrfeoLive")
            webView.loadFileURL(otaIndex, allowingReadAccessTo: docs)
            return
        }

        // Priority 2: Root bundle index.html
        if let htmlPath = Bundle.main.path(forResource: "index", ofType: "html") {
            let fileUrl = URL(fileURLWithPath: htmlPath)
            webView.loadFileURL(fileUrl, allowingReadAccessTo: fileUrl.deletingLastPathComponent())
            return
        }

        // Priority 3: frontend/index.html inside bundle
        if let htmlPath = Bundle.main.path(forResource: "index", ofType: "html", inDirectory: "frontend") {
            let fileUrl = URL(fileURLWithPath: htmlPath)
            webView.loadFileURL(fileUrl, allowingReadAccessTo: fileUrl.deletingLastPathComponent())
            return
        }

        // Priority 4: Live Tailscale Stream from Odiseo (Fallback)
        if let liveUrl = URL(string: "http://100.117.169.38:4550/static/mobile/index.html") {
            print("[Orfeo] Cargando fallback en vivo desde Odiseo...")
            webView.load(URLRequest(url: liveUrl))
        }
    }

    func reloadWithUpdatedBundle() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let otaIndex = docs.appendingPathComponent("OrfeoLive/index.html")
            if FileManager.default.fileExists(atPath: otaIndex.path) {
                UIView.transition(with: self.webView, duration: 0.35, options: .transitionCrossDissolve, animations: {
                    self.webView.loadFileURL(otaIndex, allowingReadAccessTo: docs)
                }, completion: nil)
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

// MARK: - Silent Wireless OTA Updater from Odiseo
class OrfeoOTAUpdater {
    static let shared = OrfeoOTAUpdater()

    private let primaryVersionUrl = "http://100.117.169.38:4550/static/mobile/version.json"
    private let fallbackVersionUrl = "http://192.168.100.90:4550/static/mobile/version.json"
    private let otaBuildKey = "orfeo_installed_ota_build"

    func checkForUpdates(mainVC: MainViewController?) {
        guard let url = URL(string: primaryVersionUrl) else { return }

        var req = URLRequest(url: url)
        req.timeoutInterval = 3.0
        req.cachePolicy = .reloadIgnoringLocalCacheData

        URLSession.shared.dataTask(with: req) { [weak self] data, resp, err in
            guard let self = self, let data = data, err == nil else { return }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let remoteBuild = json["build"] as? Int,
                   let bundleRelative = json["bundle_url"] as? String {
                    
                    let localBuild = UserDefaults.standard.integer(forKey: self.otaBuildKey)
                    print("[Orfeo OTA] Build local: \(localBuild), Build en Odiseo: \(remoteBuild)")

                    if remoteBuild > localBuild {
                        print("[Orfeo OTA] Descargando actualización silenciosa #\(remoteBuild)...")
                        self.downloadBundle(relativeUrl: bundleRelative, newBuild: remoteBuild, mainVC: mainVC)
                    }
                }
            } catch {
                print("[Orfeo OTA] JSON error: \(error)")
            }
        }.resume()
    }

    private func downloadBundle(relativeUrl: String, newBuild: Int, mainVC: MainViewController?) {
        let bundleFullUrl = "http://100.117.169.38:4550\(relativeUrl)"
        guard let url = URL(string: bundleFullUrl) else { return }

        var req = URLRequest(url: url)
        req.timeoutInterval = 5.0
        req.cachePolicy = .reloadIgnoringLocalCacheData

        URLSession.shared.dataTask(with: req) { [weak self] data, _, err in
            guard let self = self, let data = data, err == nil else { return }

            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let liveDir = docs.appendingPathComponent("OrfeoLive")
            let destFile = liveDir.appendingPathComponent("index.html")

            do {
                try FileManager.default.createDirectory(at: liveDir, withIntermediateDirectories: true)
                try data.write(to: destFile, options: .atomic)

                UserDefaults.standard.set(newBuild, forKey: self.otaBuildKey)
                print("[Orfeo OTA] ¡Actualización #\(newBuild) guardada con éxito en Documents/OrfeoLive!")

                // Seamlessly reload to apply new UI & Nest Mini fixes
                mainVC?.reloadWithUpdatedBundle()
            } catch {
                print("[Orfeo OTA] File write error: \(error)")
            }
        }.resume()
    }
}
