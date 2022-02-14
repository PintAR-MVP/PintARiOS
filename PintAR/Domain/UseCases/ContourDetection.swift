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

struct ContourDetection {

	private let context = CIContext()

	func preprocess(buffer: UIImage) -> CGImage? {
		let ciImage = CIImage(image: buffer)

		let noiseReductionFilter = CIFilter.gaussianBlur()
		noiseReductionFilter.radius = 10
		noiseReductionFilter.inputImage = ciImage

		let blackWhiteFilter = BlackWhiteFilter()
		blackWhiteFilter.inputImage = ciImage

		guard let outputImage = blackWhiteFilter.outputImage else {
			return nil
		}

 		if let transformedImage = self.context.createCGImage(outputImage, from: outputImage.extent) {
			return transformedImage
		}

		return nil
	}

	func recognizeShape(in image: CGImage) -> [CGPath] {
		let contourRecognition = VNDetectContoursRequest()
		contourRecognition.revision = VNDetectRectanglesRequestRevision1
		contourRecognition.contrastAdjustment = 3
		contourRecognition.detectsDarkOnLight = false

		let imageHandler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
		try? imageHandler.perform([contourRecognition])

		guard
			let results = contourRecognition.results,
			results.isEmpty == false else {
				return []
		}

		let recognizedShapes = results.compactMap { observation -> CGPath in
			return observation.normalizedPath
		}

		return recognizedShapes
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
