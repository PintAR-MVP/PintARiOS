//
//  CameraViewModel.swift
//  PintAR
//
//  Created by Daniel Klinkert on 23.11.21.
//

import Foundation
import Vision

struct CameraViewModel {

	private let detectObjectUseCase: DetectObjectUseCaseProtocol

	init(detectObjectUseCase: DetectObjectUseCaseProtocol) {
		self.detectObjectUseCase = detectObjectUseCase
	}

	func configureVision() throws {
		try self.detectObjectUseCase.setupObjectDetection()
	}

	func recogniseObject(image: CVImageBuffer, completionHandler: @escaping (Result<[VNObservation], Error>) -> Void) {
		self.detectObjectUseCase.recogniseObject(in: image, completion: completionHandler)
	}
}
