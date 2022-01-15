//
//  TextRecognition.swift
//  PintAR
//
//  Created by Niklas Amslgruber on 28.11.21.
//

import Vision
import UIKit
import Combine

protocol TextRecognitionProtocol {

	/// Recognise text in the image
	/// - Parameter image: image where the text should be recognised
	/// - Returns: comma separated strings of representing the recognised text
	func recognizeText(in image: UIImage) -> String?
}

struct TextRecognition: TextRecognitionProtocol {

	private let fastRecognition: Bool
	private let languages: [String]

	init(fastRecognition: Bool, languages: [String] = ["de-DE"]) {
		self.fastRecognition = fastRecognition
		self.languages = languages
	}

	func recognizeText(in image: UIImage) -> String? {
		guard let currentImage = image.cgImage else {
			return nil
		}

		let textDetectionRequest = VNRecognizeTextRequest()
		textDetectionRequest.recognitionLevel = self.fastRecognition ? .fast : .accurate
		textDetectionRequest.recognitionLanguages = self.languages

		let handler = VNImageRequestHandler(cgImage: currentImage, options: [:])
		try? handler.perform([textDetectionRequest])
		guard let results = textDetectionRequest.results else {
			return nil
		}

		var resultString = ""
		for result in results {
			if let topCandidate = result.topCandidates(1).first?.string {
				resultString.append(topCandidate + ",")
			}
		}

		return resultString.isEmpty ? nil : resultString
	}
}
