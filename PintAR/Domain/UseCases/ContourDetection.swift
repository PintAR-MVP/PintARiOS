//
//  ContourDetection.swift
//  PintAR
//
//  Created by Niklas Amslgruber on 01.12.21.
//

import Vision
import Combine
import CoreImage.CIFilterBuiltins
import UIKit

class ContourDetection: DetectionTask {

    var result = CurrentValueSubject<[CGPath], Never>([])
    static let context = CIContext()
	private let contextt = CIContext()

    func setup() -> VNRequest? {
        let contourRecognition = VNDetectContoursRequest { request, _ in
            guard let observations = request.results as? [VNContoursObservation] else {
                return
            }

            let recognizedShapes = observations.compactMap { observation -> CGPath in
                return observation.normalizedPath
            }
            self.result.value = recognizedShapes
        }
        contourRecognition.revision = VNDetectRectanglesRequestRevision1
        contourRecognition.contrastAdjustment = 3
        contourRecognition.detectsDarkOnLight = false

        return contourRecognition
    }

    static func convert(value: Any?) -> CurrentValueSubject<[CGPath], Never>? {
        return value as? CurrentValueSubject<[CGPath], Never>
    }

    static func preprocess(buffer: CVPixelBuffer) -> CGImage? {
        let ciImage = CIImage(cvPixelBuffer: buffer)

        let noiseReductionFilter = CIFilter.gaussianBlur()
        noiseReductionFilter.radius = 10
        noiseReductionFilter.inputImage = ciImage

        let blackWhiteFilter = BlackWhiteFilter()
        blackWhiteFilter.inputImage = noiseReductionFilter.outputImage

        guard let outputImage = blackWhiteFilter.outputImage else {
            return nil
        }

        if let transformedImage = context.createCGImage(outputImage, from: outputImage.extent) {
            return transformedImage
        }

        return nil
    }
}

private class BlackWhiteFilter: CIFilter {

    var inputImage: CIImage?

    override var outputImage: CIImage? {
        if let inputImage = self.inputImage {
            let args = [inputImage as AnyObject]

            let callback: CIKernelROICallback = { (_, rect) in
                return rect.insetBy(dx: -1, dy: -1)
            }

            return createCustomKernel()?.apply(extent: inputImage.extent, roiCallback: callback, arguments: args)
        } else {
            return nil
        }
    }

    func createCustomKernel() -> CIKernel? {
        // source: https://github.com/anupamchugh/iOS14-Resources/blob/master/iOS14VisionContourDetection/iOS14VisionContourDetection/ContentView.swift
        return CIColorKernel(source:
            """
            kernel vec4 replaceWithBlackOrWhite(__sample s) {
                if (s.r > 0.15 && s.g > 0.15 && s.b > 0.15) {
                    return vec4(0.0,0.0,0.0,1.0);
                } else {
                    return vec4(1.0,1.0,1.0,1.0);
                }
            }
            """
        )
    }
}
