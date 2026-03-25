import AVFoundation
import CoreMedia
import CoreVideo
#if os(macOS)
  import FlutterMacOS
#else
  import Flutter
#endif
#if canImport(UIKit)
  import UIKit
#endif
#if canImport(AppKit)
  import AppKit
#endif

private final class _OsVideoDeliveryPipelineError {
  var value: Error?
}

public class OsVideoDeliveryPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    #if os(macOS)
      let messenger = registrar.messenger
    #else
      let messenger = registrar.messenger()
    #endif
    let channel = FlutterMethodChannel(
      name: "com.media_rs/os_video_delivery",
      binaryMessenger: messenger)
    let instance = OsVideoDeliveryPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "probe":
      guard let args = call.arguments as? [String: Any],
        let path = args["path"] as? String
      else {
        result(FlutterError(code: "ARGS", message: "Missing path", details: nil))
        return
      }
      do {
        result(try probe(path: path))
      } catch {
        result(FlutterError(code: "PROBE", message: error.localizedDescription, details: nil))
      }

    case "estimateDelivery":
      guard let args = call.arguments as? [String: Any],
        let path = args["path"] as? String,
        let profiles = args["profiles"] as? [[String: Any]]
      else {
        result(FlutterError(code: "ARGS", message: "Missing arguments", details: nil))
        return
      }
      do {
        let info = try probeRaw(path: path)
        let rows = profiles.map { estimateRow(info: info, profile: $0) }
        result(rows)
      } catch {
        result(FlutterError(code: "ESTIMATE", message: error.localizedDescription, details: nil))
      }

    case "transcode":
      guard let args = call.arguments as? [String: Any],
        let inputPath = args["inputPath"] as? String,
        let outputPath = args["outputPath"] as? String,
        let profile = args["profile"] as? [String: Any]
      else {
        result(FlutterError(code: "ARGS", message: "Missing arguments", details: nil))
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          try self.transcode(inputPath: inputPath, outputPath: outputPath, profile: profile)
          DispatchQueue.main.async {
            result(outputPath)
          }
        } catch {
          DispatchQueue.main.async {
            result(
              FlutterError(code: "TRANSCODE", message: error.localizedDescription, details: nil))
          }
        }
      }

    case "videoThumbnail":
      guard let args = call.arguments as? [String: Any],
        let path = args["path"] as? String
      else {
        result(FlutterError(code: "ARGS", message: "Missing path", details: nil))
        return
      }
      let timeMs = args["timeMs"] as? Int ?? 0
      let maxW = args["maxWidth"] as? Int ?? 0
      let maxH = args["maxHeight"] as? Int ?? 0
      let format = args["format"] as? String ?? "jpeg"
      do {
        let data = try videoThumbnail(
          path: path, timeMs: timeMs, maxW: maxW, maxH: maxH, format: format)
        result(data)
      } catch {
        result(FlutterError(code: "THUMB", message: error.localizedDescription, details: nil))
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private struct ProbeInfo {
    let durationMs: Int64
    let width: Int
    let height: Int
    let rotation: Int
    let bitrateBps: Int?
  }

  private func probe(path: String) throws -> [String: Any?] {
    let p = try probeRaw(path: path)
    return [
      "durationMs": Int(p.durationMs),
      "displayWidth": p.width,
      "displayHeight": p.height,
      "rotationDegrees": p.rotation,
      "bitrateBps": p.bitrateBps as Any?,
    ]
  }

  private func probeRaw(path: String) throws -> ProbeInfo {
    let url = URL(fileURLWithPath: path)
    let asset = AVURLAsset(url: url)
    guard let track = asset.tracks(withMediaType: .video).first else {
      throw NSError(
        domain: "os_video_delivery", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "No video track"])
    }
    let dur = CMTimeGetSeconds(asset.duration)
    let durationMs = Int64((dur.isFinite ? dur : 0) * 1000)
    let natural = track.naturalSize
    let t = track.preferredTransform
    let angle = atan2(t.b, t.a)
    var deg = Int(round(angle * 180 / .pi))
    deg = ((deg % 360) + 360) % 360
    let w0 = Int(natural.width)
    let h0 = Int(natural.height)
    let dispW = (deg == 90 || deg == 270) ? h0 : w0
    let dispH = (deg == 90 || deg == 270) ? w0 : h0
    let rate = track.estimatedDataRate
    let bitrate: Int? = rate > 0 ? Int(rate) : nil
    return ProbeInfo(
      durationMs: durationMs, width: dispW, height: dispH, rotation: deg, bitrateBps: bitrate)
  }

  private func estimateRow(info: ProbeInfo, profile: [String: Any]) -> [String: Any] {
    let id = profile["id"] as! String
    let maxLong = (profile["maxLongEdgePx"] as! NSNumber).intValue
    let vKbps = (profile["videoBitrateKbps"] as! NSNumber).intValue
    let aKbps = (profile["audioBitrateKbps"] as! NSNumber).intValue
    let muxOverhead = (profile["muxOverheadBytes"] as? NSNumber)?.int64Value ?? 65536
    let speedFactor = (profile["encodeRealtimeSpeedFactor"] as? NSNumber)?.doubleValue ?? 2.5

    let (ow, oh) = fitLongEdge(sw: info.width, sh: info.height, maxLong: maxLong)
    var vCap = vKbps
    if let bps = info.bitrateBps {
      let srcKbps = max(1, bps / 1000)
      if srcKbps > aKbps && vCap + aKbps > srcKbps {
        vCap = max(1, srcKbps - aKbps)
      }
    }
    let totalKbps = Int64(vCap + aKbps)
    let rawEst = (totalKbps * 1000 * info.durationMs) / 8000 + muxOverhead
    let estSize = (rawEst * 92) / 100
    let estTime = max(1, Int64(Double(info.durationMs) / speedFactor))

    return [
      "profileId": id,
      "width": ow,
      "height": oh,
      "estimatedSizeBytes": estSize,
      "videoBitrateKbps": vCap,
      "audioBitrateKbps": aKbps,
      "estimatedEncodeTimeMs": min(estTime, Int64(Int.max)),
    ]
  }

  private func fitLongEdge(sw: Int, sh: Int, maxLong: Int) -> (Int, Int) {
    if sw <= 0 || sh <= 0 { return (0, 0) }
    let longE = max(sw, sh)
    if longE <= maxLong {
      return (sw & ~1, sh & ~1)
    }
    let scale = Double(maxLong) / Double(longE)
    let w = max(2, Int((Double(sw) * scale).rounded()) & ~1)
    let h = max(2, Int((Double(sh) * scale).rounded()) & ~1)
    return (w, h)
  }

  /// Re-encode with explicit display size (after preferredTransform).
  /// Uses `AVAssetExportSession` + `videoComposition` (full timeline, correct HDR/orientation).
  /// Reader/writer re-encode was producing black, truncated output on some HDR/phone clips.
  /// Effective video bitrate follows the export preset ladder, not exact `videoBitrateKbps`.
  private func transcode(inputPath: String, outputPath: String, profile: [String: Any]) throws {
    let maxLong = (profile["maxLongEdgePx"] as! NSNumber).intValue
    let videoKbps = (profile["videoBitrateKbps"] as! NSNumber).intValue
    let audioKbps = (profile["audioBitrateKbps"] as! NSNumber).intValue

    let urlIn = URL(fileURLWithPath: inputPath)
    let urlOut = URL(fileURLWithPath: outputPath)
    if FileManager.default.fileExists(atPath: outputPath) {
      try FileManager.default.removeItem(at: urlOut)
    }

    let asset = AVURLAsset(url: urlIn)
    guard let videoTrack = asset.tracks(withMediaType: .video).first else {
      throw NSError(
        domain: "os_video_delivery", code: 2,
        userInfo: [NSLocalizedDescriptionKey: "No video track"])
    }

    let naturalSize = videoTrack.naturalSize
    let pref = videoTrack.preferredTransform
    let displayRect = CGRect(origin: .zero, size: naturalSize).applying(pref)
    let srcW = max(1, Int(abs(displayRect.width.rounded())))
    let srcH = max(1, Int(abs(displayRect.height.rounded())))
    let (outW, outH) = fitLongEdge(sw: srcW, sh: srcH, maxLong: maxLong)
    guard outW >= 2, outH >= 2 else {
      throw NSError(
        domain: "os_video_delivery", code: 11,
        userInfo: [NSLocalizedDescriptionKey: "Invalid output size"])
    }

    let composition = AVMutableComposition()
    guard
      let compVideo = composition.addMutableTrack(
        withMediaType: .video,
        preferredTrackID: kCMPersistentTrackID_Invalid)
    else {
      throw NSError(
        domain: "os_video_delivery", code: 12,
        userInfo: [NSLocalizedDescriptionKey: "Cannot add video track"])
    }

    let fullRange = CMTimeRange(start: .zero, duration: asset.duration)
    try compVideo.insertTimeRange(fullRange, of: videoTrack, at: .zero)

    if let audioTrack = asset.tracks(withMediaType: .audio).first,
      let ca = composition.addMutableTrack(
        withMediaType: .audio,
        preferredTrackID: kCMPersistentTrackID_Invalid)
    {
      try ca.insertTimeRange(fullRange, of: audioTrack, at: .zero)
    }

    let instruction = AVMutableVideoCompositionInstruction()
    instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)

    let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideo)
    let sx = CGFloat(outW) / CGFloat(srcW)
    let sy = CGFloat(outH) / CGFloat(srcH)
    let scale = min(sx, sy)
    let scaledW = CGFloat(srcW) * scale
    let scaledH = CGFloat(srcH) * scale
    let tx = (CGFloat(outW) - scaledW) / 2.0
    let ty = (CGFloat(outH) - scaledH) / 2.0
    let scaleT = CGAffineTransform(scaleX: scale, y: scale)
    let translateT = CGAffineTransform(translationX: tx, y: ty)
    let combined = pref.concatenating(scaleT).concatenating(translateT)
    layerInstruction.setTransform(combined, at: .zero)
    instruction.layerInstructions = [layerInstruction]

    let videoComposition = AVMutableVideoComposition()
    videoComposition.renderSize = CGSize(width: outW, height: outH)
    let fps = videoTrack.nominalFrameRate
    let tb: Int32 =
      fps.isFinite && fps >= 1
      ? min(60, max(15, Int32(fps.rounded()))) : 30
    videoComposition.frameDuration = CMTime(value: 1, timescale: tb)
    videoComposition.instructions = [instruction]

    let presetName: String
    if maxLong <= 640 {
      presetName = AVAssetExportPreset640x480
    } else if maxLong <= 960 {
      presetName = AVAssetExportPreset960x540
    } else if maxLong <= 1280 {
      presetName = AVAssetExportPreset1280x720
    } else {
      presetName = AVAssetExportPreset1920x1080
    }

    guard let exporter = AVAssetExportSession(asset: composition, presetName: presetName) else {
      throw NSError(
        domain: "os_video_delivery", code: 20,
        userInfo: [
          NSLocalizedDescriptionKey: "Cannot create AVAssetExportSession",
          "requestedVideoKbps": NSNumber(value: videoKbps),
          "requestedAudioKbps": NSNumber(value: audioKbps),
        ])
    }
    exporter.videoComposition = videoComposition
    exporter.outputURL = urlOut
    exporter.outputFileType = .mp4
    exporter.shouldOptimizeForNetworkUse = true

    let sem = DispatchSemaphore(value: 0)
    var exportErr: Error?
    exporter.exportAsynchronously {
      if exporter.status != .completed {
        exportErr =
          exporter.error
          ?? NSError(
            domain: "os_video_delivery", code: 21,
            userInfo: [
              NSLocalizedDescriptionKey: "Export failed (status=\(exporter.status.rawValue))",
              "requestedVideoKbps": NSNumber(value: videoKbps),
            ])
      }
      sem.signal()
    }
    sem.wait()
    if let e = exportErr { throw e }
  }

  private func videoThumbnail(
    path: String, timeMs: Int, maxW: Int, maxH: Int, format: String
  ) throws -> FlutterStandardTypedData {
    let url = URL(fileURLWithPath: path)
    let asset = AVURLAsset(url: url)
    let gen = AVAssetImageGenerator(asset: asset)
    gen.appliesPreferredTrackTransform = true
    let tw = maxW > 0 ? CGFloat(maxW) : 512
    let th = maxH > 0 ? CGFloat(maxH) : 512
    gen.maximumSize = CGSize(width: tw, height: th)
    let t = CMTime(value: CMTimeValue(timeMs), timescale: 1000)
    var actual = CMTime.zero
    let cg = try gen.copyCGImage(at: t, actualTime: &actual)
    let d = try encodeCgImage(cg, format: format)
    return FlutterStandardTypedData(bytes: d)
  }

  private func encodeCgImage(_ cg: CGImage, format: String) throws -> Data {
    #if os(iOS)
      let ui = UIImage(cgImage: cg)
      if format == "png" {
        guard let data = ui.pngData() else {
          throw NSError(
            domain: "os_video_delivery", code: 4,
            userInfo: [NSLocalizedDescriptionKey: "Encode PNG failed"])
        }
        return data
      }
      guard let data = ui.jpegData(compressionQuality: 0.9) else {
        throw NSError(
          domain: "os_video_delivery", code: 4,
          userInfo: [NSLocalizedDescriptionKey: "Encode JPEG failed"])
      }
      return data
    #elseif os(macOS)
      let w = cg.width
      let h = cg.height
      let img = NSImage(
        cgImage: cg, size: NSSize(width: w, height: h))
      guard let tiff = img.tiffRepresentation,
        let rep = NSBitmapImageRep(data: tiff)
      else {
        throw NSError(
          domain: "os_video_delivery", code: 4,
          userInfo: [NSLocalizedDescriptionKey: "Bitmap rep failed"])
      }
      if format == "png" {
        guard let data = rep.representation(using: .png, properties: [:]) else {
          throw NSError(
            domain: "os_video_delivery", code: 4,
            userInfo: [NSLocalizedDescriptionKey: "Encode PNG failed"])
        }
        return data
      }
      guard
        let data = rep.representation(
          using: .jpeg,
          properties: [.compressionFactor: 0.9])
      else {
        throw NSError(
          domain: "os_video_delivery", code: 4,
          userInfo: [NSLocalizedDescriptionKey: "Encode JPEG failed"])
      }
      return data
    #else
      throw NSError(
        domain: "os_video_delivery", code: 4,
        userInfo: [NSLocalizedDescriptionKey: "Unsupported platform"])
    #endif
  }
}
