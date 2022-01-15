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
		case contour
	}

	private let detectionTypes: [DetectionType]
	private var requests = [VNRequest]()
	private var preProcessedRequests = [VNRequest]()
	private var requestCompletionHandler: VNImageRequestHandler?
	private var preProcessedRequestCompletionHandler: VNImageRequestHandler?
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
					results[detectionType] = detectionTask.result
					return try detectionTask.setup()
				case .contour:
					return nil // Should be included in the preProcessedRequests
				}
			} catch {
				print("Setting up detection task \(detectionType) failed with \(error)")
				return nil
			}
		})

		// Setup contour detection in a separate VNRequestArray
		let detectionTask = ContourDetection()
		results[.contour] = detectionTask.result
		if let request = detectionTask.setup() {
			preProcessedRequests = [request]
		}
	}

	func recognizeObject(in image: CVPixelBuffer) {
		self.requestCompletionHandler = VNImageRequestHandler(cvPixelBuffer: image, orientation: .up, options: [:])

		if detectionTypes.contains(.contour), let cgImage = ContourDetection.preprocess(buffer: image) {
			self.preProcessedRequestCompletionHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
			try? self.preProcessedRequestCompletionHandler?.perform(self.preProcessedRequests)
		}

		try? self.requestCompletionHandler?.perform(self.requests)
	}
}
