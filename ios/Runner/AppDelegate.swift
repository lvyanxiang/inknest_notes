import Flutter
import UIKit
import Vision

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var textRecognitionChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: "inknest_notes/text_recognition",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    textRecognitionChannel = channel
    channel.setMethodCallHandler { call, result in
      guard call.method == "recognizeText" else {
        result(FlutterMethodNotImplemented)
        return
      }
      Self.recognizeText(call: call, result: result)
    }
  }

  private static func recognizeText(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard
      let arguments = call.arguments as? [String: Any],
      let typedData = arguments["pngBytes"] as? FlutterStandardTypedData,
      let image = UIImage(data: typedData.data),
      let cgImage = image.cgImage
    else {
      result(
        FlutterError(
          code: "invalid_recognition_image",
          message: "Unable to decode the recognition image.",
          details: nil
        )
      )
      return
    }

    let preferredLanguages = arguments["recognitionLanguages"] as? [String] ?? []
    let usesLanguageCorrection = arguments["usesLanguageCorrection"] as? Bool ?? true

    DispatchQueue.global(qos: .userInitiated).async {
      do {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        let supportedLanguages = try VNRecognizeTextRequest.supportedRecognitionLanguages(
          for: request.recognitionLevel,
          revision: request.revision
        )
        let supportedPreferredLanguages = preferredLanguages.filter {
          supportedLanguages.contains($0)
        }
        if !supportedPreferredLanguages.isEmpty {
          request.recognitionLanguages = supportedPreferredLanguages
        }
        request.usesLanguageCorrection = usesLanguageCorrection

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
        try handler.perform([request])
        let observations = (request.results ?? []).sorted { first, second in
          let verticalDifference = abs(first.boundingBox.midY - second.boundingBox.midY)
          if verticalDifference > 0.02 {
            return first.boundingBox.midY > second.boundingBox.midY
          }
          return first.boundingBox.minX < second.boundingBox.minX
        }
        let recognizedRegions = observations.compactMap { observation in
          observation.topCandidates(1).first.map { (observation, $0) }
        }
        let candidates = recognizedRegions.map(\.1)
        let text = candidates.map(\.string).joined(separator: "\n")
        let confidence = candidates.isEmpty
          ? 0
          : candidates.reduce(0) { $0 + Double($1.confidence) } / Double(candidates.count)
        let regions: [[String: Any]] = recognizedRegions.map { observation, candidate in
          let bounds = observation.boundingBox
          return [
            "text": candidate.string,
            "confidence": Double(candidate.confidence),
            "left": bounds.minX,
            "top": 1 - bounds.maxY,
            "width": bounds.width,
            "height": bounds.height,
          ]
        }

        DispatchQueue.main.async {
          result([
            "text": text,
            "confidence": confidence,
            "regions": regions,
            "engineIdentifier": "apple-vision-text-v\(request.revision)",
          ])
        }
      } catch {
        DispatchQueue.main.async {
          result(
            FlutterError(
              code: "recognition_failed",
              message: error.localizedDescription,
              details: nil
            )
          )
        }
      }
    }
  }
}
