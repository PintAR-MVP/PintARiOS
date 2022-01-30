//
//  DetectObjectUseCase.swift
//  PintAR
//
//  Created by Daniel Klinkert on 23.11.21.
//

import Foundation
import Vision
import Combine
import CoreImage
import UIKit

class DetectObjectUseCase: DetectObjectUseCaseProtocol {

	enum DetectObjectError: Error {
		case missingConfiguration
	}

	enum DetectionType: Hashable {
		case rectangles(model: RectangleDetection.Model)
	}

	private let detectionTypes: [DetectionType]
	private var requests = [VNRequest]()
	private var requestCompletionHandler: VNImageRequestHandler?
	private var cancellableSet: Set<AnyCancellable> = []
	private let colorDetection = ColorDetection()

	var results: [DetectionType: Any] = [:]

	init(detectionTypes: [DetectionType]) {
		self.detectionTypes = detectionTypes
	}

	func setupObjectDetection() {
		requests = detectionTypes.compactMap({ detectionType in
			do {
				switch detectionType {
				case .rectangles(let model):
					let detectionTask = RectangleDetection(model: model)
					self.results[detectionType] = detectionTask.result
					return try detectionTask.setup()
				}
			} catch {
				print("Setting up detection task \(detectionType) failed with \(error)")
				return nil
			}
		})
	}

	func recognizeObject(in image: CVPixelBuffer) {
		let rotatedImage = CIImage(cvImageBuffer: image).oriented(.right)
		guard let correctImage = self.createPixelBufferFrom(image: rotatedImage) else {
			debugPrint("failed")
			return
		}

		self.requestCompletionHandler = VNImageRequestHandler(cvPixelBuffer: correctImage, orientation: .up, options: [:])

		try? self.requestCompletionHandler?.perform(self.requests)
	}

	let context = CIContext()

	// Function
	func createPixelBufferFrom(image: CIImage) -> CVPixelBuffer? {
		// based on https://stackoverflow.com/questions/54354138/how-can-you-make-a-cvpixelbuffer-directly-from-a-ciimage-instead-of-a-uiimage-in

		let attrs = [
		  kCVPixelBufferCGImageCompatibilityKey: false,
		  kCVPixelBufferCGBitmapContextCompatibilityKey: false,
		  kCVPixelBufferWidthKey: Int(image.extent.width),
		  kCVPixelBufferHeightKey: Int(image.extent.height)
		] as CFDictionary

		var pixelBuffer: CVPixelBuffer?
		let status = CVPixelBufferCreate(kCFAllocatorDefault, Int(image.extent.width), Int(image.extent.height), kCVPixelFormatType_32BGRA, attrs, &pixelBuffer)

		if status == kCVReturnInvalidPixelFormat {
		  print("status == kCVReturnInvalidPixelFormat")
		}
		if status == kCVReturnInvalidSize {
		  print("status == kCVReturnInvalidSize")
		}
		if status == kCVReturnPixelBufferNotMetalCompatible {
		  print("status == kCVReturnPixelBufferNotMetalCompatible")
		}
		if status == kCVReturnPixelBufferNotOpenGLCompatible {
		  print("status == kCVReturnPixelBufferNotOpenGLCompatible")
		}

		guard (status == kCVReturnSuccess) else {
		  return nil
		}

		// swiftlint:disable:next force_unwrapping
		context.render(image, to: pixelBuffer!)
		return pixelBuffer
	  }
}
