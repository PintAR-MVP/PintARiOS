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
		self.requestCompletionHandler = VNImageRequestHandler(cvPixelBuffer: image, orientation: .up, options: [:])

		try? self.requestCompletionHandler?.perform(self.requests)
	}
}
