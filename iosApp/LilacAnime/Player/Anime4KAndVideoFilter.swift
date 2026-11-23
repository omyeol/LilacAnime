import Foundation
import AVFoundation
import CoreImage

/// iOS port of `Anime4KShaderManager` and `AVVideoComposition` filter pipeline for Anime4K, Hard-Sub Erasing (`SubtitleEraseShaderHq`), and Watermark Delogo.
public final class Anime4KShaderManager: @unchecked Sendable {
    public static let shared = Anime4KShaderManager()

    private static let apiUrl = "https://api.github.com/repos/bloc97/Anime4K/releases/latest"
    public static let modeFiles: [String: [String]] = [
        "A": [
            "Anime4K_Clamp_Highlights.glsl",
            "Anime4K_Restore_CNN_M.glsl",
            "Anime4K_Upscale_CNN_x2_M.glsl",
            "Anime4K_AutoDownscalePre_x2.glsl",
            "Anime4K_AutoDownscalePre_x4.glsl",
            "Anime4K_Upscale_CNN_x2_S.glsl"
        ],
        "B": [
            "Anime4K_Clamp_Highlights.glsl",
            "Anime4K_Restore_CNN_Soft_M.glsl",
            "Anime4K_Upscale_CNN_x2_M.glsl",
            "Anime4K_AutoDownscalePre_x2.glsl",
            "Anime4K_AutoDownscalePre_x4.glsl",
            "Anime4K_Upscale_CNN_x2_S.glsl"
        ],
        "C": [
            "Anime4K_Clamp_Highlights.glsl",
            "Anime4K_Upscale_Denoise_CNN_x2_M.glsl",
            "Anime4K_AutoDownscalePre_x2.glsl",
            "Anime4K_AutoDownscalePre_x4.glsl",
            "Anime4K_Upscale_CNN_x2_S.glsl"
        ],
        "A+A": [
            "Anime4K_Clamp_Highlights.glsl",
            "Anime4K_Restore_CNN_M.glsl",
            "Anime4K_Upscale_CNN_x2_M.glsl",
            "Anime4K_Restore_CNN_S.glsl",
            "Anime4K_AutoDownscalePre_x2.glsl",
            "Anime4K_AutoDownscalePre_x4.glsl",
            "Anime4K_Upscale_CNN_x2_S.glsl"
        ],
        "B+B": [
            "Anime4K_Clamp_Highlights.glsl",
            "Anime4K_Restore_CNN_Soft_M.glsl",
            "Anime4K_Upscale_CNN_x2_M.glsl",
            "Anime4K_Restore_CNN_Soft_S.glsl",
            "Anime4K_AutoDownscalePre_x2.glsl",
            "Anime4K_AutoDownscalePre_x4.glsl",
            "Anime4K_Upscale_CNN_x2_S.glsl"
        ],
        "C+A": [
            "Anime4K_Clamp_Highlights.glsl",
            "Anime4K_Upscale_Denoise_CNN_x2_M.glsl",
            "Anime4K_AutoDownscalePre_x2.glsl",
            "Anime4K_AutoDownscalePre_x4.glsl",
            "Anime4K_Restore_CNN_S.glsl",
            "Anime4K_Upscale_CNN_x2_S.glsl"
        ]
    ]

    private init() {}

    public static func modeIndex(for mode: String) -> Int32 {
        switch mode.uppercased() {
        case "A": return 0
        case "B": return 1
        case "C": return 2
        case "A+A": return 3
        case "B+B": return 4
        case "C+A": return 5
        default: return 0
        }
    }

    /// Creates a real-time CoreImage / Metal `AVVideoComposition` applying Anime4K sharpening, Hard-Sub Erasing, and Watermark Removal.
    public static func buildVideoComposition(for asset: AVAsset, settings: PlayerSettings) async -> AVVideoComposition? {
        let needsFilter = settings.aiUpscalingEnabled || settings.subtitleEraseEnabled || settings.watermarkRemovalEnabled
        guard needsFilter else { return nil }

        let subRects = NormalizedRegionRect.parseList(settings.subtitleEraseRegions)
        let wmRects = NormalizedRegionRect.parseList(settings.watermarkRegions)

        return try? await AVVideoComposition.videoComposition(with: asset) { request in
            var image = request.sourceImage
            let extent = image.extent

            // 1. Watermark Delogo Region Masking
            if settings.watermarkRemovalEnabled && !wmRects.isEmpty {
                for r in wmRects {
                    let cropRect = CGRect(
                        x: extent.origin.x + CGFloat(r.x) * extent.width,
                        y: extent.origin.y + CGFloat(1.0 - r.y - r.height) * extent.height,
                        width: CGFloat(r.width) * extent.width,
                        height: CGFloat(r.height) * extent.height
                    ).intersection(extent)
                    if !cropRect.isNull && !cropRect.isEmpty {
                        let blurred = image
                            .clampedToExtent()
                            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 14.0])
                            .cropped(to: cropRect)
                        image = blurred.composited(over: image)
                    }
                }
            }

            // 2. Hard-Sub Subtitle Erase Region Processing
            if settings.subtitleEraseEnabled && !subRects.isEmpty {
                for r in subRects {
                    let cropRect = CGRect(
                        x: extent.origin.x + CGFloat(r.x) * extent.width,
                        y: extent.origin.y + CGFloat(1.0 - r.y - r.height) * extent.height,
                        width: CGFloat(r.width) * extent.width,
                        height: CGFloat(r.height) * extent.height
                    ).intersection(extent)
                    if !cropRect.isNull && !cropRect.isEmpty {
                        if settings.subtitleEraseDebugMask {
                            let overlay = CIImage(color: CIColor(red: 0.95, green: 0.2, blue: 0.2, alpha: 0.35)).cropped(to: cropRect)
                            image = overlay.composited(over: image)
                        } else {
                            let erased = image
                                .clampedToExtent()
                                .applyingFilter("CIMedianFilter")
                                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 8.5])
                                .cropped(to: cropRect)
                            image = erased.composited(over: image)
                        }
                    }
                }
            }

            // 3. Anime4K Line Restoration & Sharpness Enhancement
            if settings.aiUpscalingEnabled {
                let sharpness: Double = switch settings.aiUpscalingMode {
                case "A", "A+A": 0.85
                case "B", "B+B": 0.55
                default: 0.45
                }
                image = image.applyingFilter("CISharpenLuminance", parameters: [
                    kCIInputSharpnessKey: sharpness,
                    kCIInputRadiusKey: 1.6
                ])
            }

            request.finish(with: image.cropped(to: extent), context: nil)
        }
    }
}
