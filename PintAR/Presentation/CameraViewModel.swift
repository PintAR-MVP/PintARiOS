//
//  CameraViewModel.swift
//  PintAR
//
//  Created by Daniel Klinkert on 23.11.21.
//

import Foundation
import Vision

struct CameraViewModel {

	let detectObjectUseCase: DetectObjectUseCaseProtocol

	init(detectObjectUseCase: DetectObjectUseCaseProtocol) {
		self.detectObjectUseCase = detectObjectUseCase
	}

	func configureVision() throws {
		try self.detectObjectUseCase.setupObjectDetection()
	}

	func recognizeObject(image: CVImageBuffer, completionHandler: @escaping (Result<[VNObservation], Error>) -> Void) {
		self.detectObjectUseCase.recognizeObject(in: image, completion: completionHandler)
	}
}
