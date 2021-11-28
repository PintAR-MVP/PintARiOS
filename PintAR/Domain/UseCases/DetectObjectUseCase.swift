//
//  DetectObjectUseCase.swift
//  PintAR
//
//  Created by Daniel Klinkert on 23.11.21.
//

import Foundation
import Vision

protocol DetectObjectUseCaseProtocol {

	func setupObjectDetection() throws

	func recognizeObject(in image: CVPixelBuffer, completion: @escaping (Result<[VNObservation], Error>) -> Void)
}

class DetectObjectUseCase: DetectObjectUseCaseProtocol {

	enum DetectObjectError: Error {
		case missingConfiguration
	}

	enum DetectionType {
		case rectangles(observations: Int)
        case text
		case loadMLModel(url: URL)
	}

    @Published var recognizedText: [String] = []

	let modelUrl: URL
	private var visionModel: VNCoreMLModel?
	private var requests = [VNRequest]()
	private var requestCompletionHandler: VNImageRequestHandler?

	init(modelUrl: URL) {
		self.modelUrl = modelUrl
	}

	func setupObjectDetection() throws {
		do {
			let mLModelRequests = try self.setupObjectDetectionWithMLModel()
            let textRecognitionRequest = try self.setupTextRecognition()
			self.requests = [mLModelRequests, textRecognitionRequest]
		} catch {
			print("Model loading went wrong: \(error)")
		}
	}

	func recognizeObject(in image: CVPixelBuffer, completion: @escaping (Result<[VNObservation], Error>) -> Void) {
		self.requestCompletionHandler = VNImageRequestHandler(cvPixelBuffer: image, options: [:])

		try? self.requestCompletionHandler?.perform(self.requests)

		guard let results = self.requests.compactMap({ $0.results }).first else {
			return
		}

		completion(.success(results))
	}

	private func setupObjectDetectionWithMLModel() throws -> VNRequest {
		do {
			let visionModel = try VNCoreMLModel(for: MLModel(contentsOf: self.modelUrl))
			self.visionModel = visionModel
			let objectRecognition = VNCoreMLRequest(model: visionModel) { request, _ in
				guard let results = request.results else {
					return
				}

				for observation in results where observation is VNRecognizedObjectObservation {
					guard let objectObservation = observation as? VNRecognizedObjectObservation else {
						continue
					}

					// Select only the label with the highest confidence.
					let objectClass = objectObservation.labels[0]
					print(objectClass.identifier)
				}
			}

			return objectRecognition
		} catch {
			throw error
		}
	}

    private func setupTextRecognition() throws -> VNRequest {
        let textDetectionRequest = VNRecognizeTextRequest { request, _ in

            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                return
            }
            let recognizedStrings = observations.compactMap { observation in
                return observation.topCandidates(1).first?.string
            }

            self.recognizedText = recognizedStrings
        }

        textDetectionRequest.recognitionLevel = .accurate
        textDetectionRequest.recognitionLanguages = ["de-DE"]
        return textDetectionRequest
    }
}
