import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Launched by another app rather than from the home screen. On a
    // scene-based launch this is empty and the URL arrives with the scene
    // instead, which is why both paths are wired up.
    if let url = launchOptions?[.url] as? URL {
      IncomingDocuments.shared.receive(urls: [url])
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// A document opened while the app was already running, on a build that is
  /// not scene-based. With scenes, `IncomingDocuments` hears about it as a
  /// registered scene delegate instead, so this never double-delivers.
  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    IncomingDocuments.shared.receive(urls: [url])
    return super.application(app, open: url, options: options)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    IncomingDocuments.shared.attach(to: engineBridge)
  }
}

/// Receives PDFs other apps open or share into The PDF Project.
///
/// iOS hands over a URL that is on loan: a document picked outside the app's
/// own container is security-scoped, readable only between
/// `startAccessingSecurityScopedResource` and its matching stop. The viewer
/// opens documents long after that window has closed, so every incoming
/// document is copied into the app's cache first and Dart is only ever told
/// about a file it can still read.
final class IncomingDocuments: NSObject, FlutterStreamHandler, FlutterSceneLifeCycleDelegate {
  static let shared = IncomingDocuments()

  private static let methodChannelName = "com.softmindai.the_pdf_project/incoming_documents"
  private static let eventChannelName =
    "com.softmindai.the_pdf_project/incoming_documents/events"
  private static let incomingFolder = "incoming"
  private static let defaultName = "document.pdf"

  /// Documents that arrived before Dart was listening — the launch document,
  /// and anything that lands while the engine is still starting up.
  private var waiting: [[String: String]] = []
  private var events: FlutterEventSink?

  private override init() {
    super.init()
  }

  /// Opens the channels and asks to be told about scene URLs.
  ///
  /// Registering as a scene delegate rather than subclassing `SceneDelegate`
  /// keeps Flutter's own forwarding intact — plugins and this app hear about
  /// the same scene events, in the order Flutter intends.
  func attach(to engineBridge: FlutterImplicitEngineBridge) {
    let messenger = engineBridge.applicationRegistrar.messenger()

    FlutterMethodChannel(name: Self.methodChannelName, binaryMessenger: messenger)
      .setMethodCallHandler { [weak self] call, result in
        guard let self else { return result(nil) }
        switch call.method {
        // Taken, not read: the launch document opens once, and a later
        // restart must not reopen it over whatever the reader moved on to.
        case "takeInitialDocuments":
          result(self.waiting)
          self.waiting.removeAll()
        default:
          result(FlutterMethodNotImplemented)
        }
      }

    FlutterEventChannel(name: Self.eventChannelName, binaryMessenger: messenger)
      .setStreamHandler(self)

    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "IncomingDocuments") {
      registrar.addSceneDelegate(self)
    }
  }

  /// Copies the documents somewhere readable and passes them on.
  ///
  /// A batch shared in one go stays one arrival, so the viewer can tell
  /// "three documents were shared" from "three documents were opened".
  func receive(urls: [URL]) {
    let documents = urls.compactMap(copyIntoCache)
    guard !documents.isEmpty else { return }

    if let events {
      events(documents)
    } else {
      // Nobody listening yet: hold them for the next takeInitialDocuments
      // rather than losing them.
      waiting.append(contentsOf: documents)
    }
  }

  // MARK: - FlutterSceneLifeCycleDelegate

  /// The app was launched by another app opening a document.
  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions?
  ) -> Bool {
    guard let urls = connectionOptions?.urlContexts.map(\.url), !urls.isEmpty else { return false }
    receive(urls: urls)
    return true
  }

  /// A second document while the app is already on screen.
  func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) -> Bool {
    let urls = URLContexts.map(\.url)
    guard !urls.isEmpty else { return false }
    receive(urls: urls)
    return true
  }

  // MARK: - FlutterStreamHandler

  func onListen(
    withArguments arguments: Any?,
    eventSink: @escaping FlutterEventSink
  ) -> FlutterError? {
    events = eventSink
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    events = nil
    return nil
  }

  // MARK: - Copying

  /// Copies an incoming document into the app's cache and describes it.
  ///
  /// Returns nil when the document cannot be read, so one unreadable
  /// document does not cost the reader the others shared with it.
  private func copyIntoCache(_ url: URL) -> [String: String]? {
    // Only a URL from outside the app's container is scoped; asking anyway is
    // harmless, and the stop has to match the start that actually succeeded.
    let scoped = url.startAccessingSecurityScopedResource()
    defer {
      if scoped { url.stopAccessingSecurityScopedResource() }
    }

    do {
      let files = FileManager.default
      let folder = files.temporaryDirectory
        .appendingPathComponent(Self.incomingFolder, isDirectory: true)
      try files.createDirectory(at: folder, withIntermediateDirectories: true)

      let name = displayName(of: url)
      // Prefixed with the arrival time so opening two documents of the same
      // name in one session does not have one overwrite the other.
      let stamp = Int(Date().timeIntervalSince1970 * 1000)
      let target = folder.appendingPathComponent("\(stamp)-\(name)")
      if files.fileExists(atPath: target.path) {
        try files.removeItem(at: target)
      }
      try files.copyItem(at: url, to: target)

      return ["path": target.path, "name": name]
    } catch {
      NSLog("Could not read an incoming document: \(error)")
      return nil
    }
  }

  /// The name the sender shows for the document, so the app bar reads the
  /// same as the app the reader came from.
  private func displayName(of url: URL) -> String {
    let readable = url.lastPathComponent
      .replacingOccurrences(of: "[^A-Za-z0-9._ -]", with: "_", options: .regularExpression)
      .trimmingCharacters(in: .whitespaces)
    let name = readable.isEmpty ? Self.defaultName : readable
    return name.lowercased().hasSuffix(".pdf") ? name : "\(name).pdf"
  }
}
