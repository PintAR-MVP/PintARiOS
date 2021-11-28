//
//  DetectObjectUseCase.swift
//  PintAR
//
//  Created by Daniel Klinkert on 23.11.21.
//

import Foundation
import Vision
import Combine

class DetectObjectUseCase: DetectObjectUseCaseProtocol {

	enum DetectObjectError: Error {
		case missingConfiguration
	}

    enum DetectionType {

        case rectangles(model: RectangleDetection.Model)
        case text(fastRecognition: Bool)

        var task: DetectionTask {
            switch self {
            case .rectangles(let model):
                return RectangleDetection(model: model)
            case .text(let fastRecognition):
                return TextRecognition(fastRecognition: fastRecognition)
            }
        }
	}

    @Published var recognizedText: [String] = []

    private let detectionTypes: [DetectionType]
	private var requests = [VNRequest]()
	private var requestCompletionHandler: VNImageRequestHandler?
    private var cancellableSet: Set<AnyCancellable> = []

    init(detectionTypes: [DetectionType]) {
        self.detectionTypes = detectionTypes
	}

	func setupObjectDetection() {
        requests = detectionTypes.compactMap({ detectionType in
            do {
                switch detectionType {
                case .rectangles(let model):
                    let detectionTask = RectangleDetection(model: model)
                    return try detectionTask.setup()
                case .text(let fastRecognition):
                    let detectionTask =  TextRecognition(fastRecognition: fastRecognition)
                    detectionTask.$recognizedText
                        .assign(to: \.recognizedText, on: self)
                        .store(in: &cancellableSet)
                    return detectionTask.setup()
                }
            } catch {
                print("Setting up detection task \(detectionType) failed with \(error)")
                return nil
            }
        })
	}

	func recognizeObject(in image: CVPixelBuffer, completion: @escaping (Result<[VNObservation], Error>) -> Void) {
		self.requestCompletionHandler = VNImageRequestHandler(cvPixelBuffer: image, options: [:])

		try? self.requestCompletionHandler?.perform(self.requests)

		guard let results = self.requests.compactMap({ $0.results }).first else {
			return
		}
        completion(.success(results))
	}
}
