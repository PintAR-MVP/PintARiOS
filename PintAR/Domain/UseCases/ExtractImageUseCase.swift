//
//  ExtractImageUseCase.swift
//  PintAR
//
//  Created by Daniel Klinkert on 08.01.22.
//

import Foundation
import Vision
import UIKit

protocol ExtractImageUseCaseProtocol {

	func imageExtraction(_ observation: VNRectangleObservation, from buffer: CVImageBuffer) -> UIImage?
}

struct ExtractImageUseCase: ExtractImageUseCaseProtocol {

	func imageExtraction(_ observation: VNRectangleObservation, from buffer: CVImageBuffer) -> UIImage? {
		// The image captured from the ARFrame is rotate 90 degrees to the left
		// First we need to correct the image to extract the bounding box
		var ciImage = CIImage(cvImageBuffer: buffer).oriented(.right)

		let topLeft = observation.topLeft.scaled(to: ciImage.extent.size)
		let topRight = observation.topRight.scaled(to: ciImage.extent.size)
		let bottomLeft = observation.bottomLeft.scaled(to: ciImage.extent.size)
		let bottomRight = observation.bottomRight.scaled(to: ciImage.extent.size)

		// pass filters to extract/rectify the image
		ciImage = ciImage.applyingFilter("CIPerspectiveCorrection", parameters: [
			"inputTopLeft": CIVector(cgPoint: topLeft),
			"inputTopRight": CIVector(cgPoint: topRight),
			"inputBottomLeft": CIVector(cgPoint: bottomLeft),
			"inputBottomRight": CIVector(cgPoint: bottomRight)
		])

		let context = CIContext()
		guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
			return nil
		}

		let output = UIImage(cgImage: cgImage)
		return output
	}
}
