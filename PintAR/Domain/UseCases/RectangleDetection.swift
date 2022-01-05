//
//  RectangleDetection.swift
//  PintAR
//
//  Created by Niklas Amslgruber on 28.11.21.
//

import Vision
import Combine

class RectangleDetection: DetectionTask {

	enum Model {
		case yoloV3

		var name: String {
			switch self {
			case .yoloV3:
				return "YOLOv3Tiny"
			}
		}

		var modelURL: URL {
			let url: URL?
			switch self {
			case .yoloV3:
				url = Bundle.main.url(forResource: self.name, withExtension: "mlmodelc")
			}
			return url ?? URL(fileURLWithPath: "")
		}
	}

    var result = CurrentValueSubject<(String, CGRect), Never>(("", .zero))

	private var visionModel: VNCoreMLModel?
	private let model: Model

	init(model: Model) {
		self.model = model
	}

	func setup() throws -> VNRequest? {
		do {
			let visionModel = try VNCoreMLModel(for: MLModel(contentsOf: model.modelURL))
			self.visionModel = visionModel
			let objectRecognition = VNCoreMLRequest(model: visionModel) { request, _ in
				guard let results = request.results else {
					return
				}

                var output: (String, CGRect) = ("", .zero)

				for observation in results where observation is VNRecognizedObjectObservation {
					guard let objectObservation = observation as? VNRecognizedObjectObservation else {
						continue
					}

					// Select only the label with the highest confidence.
					let objectClass = objectObservation.labels[0]
//					print(objectClass.identifier)
                    output.0 = objectClass.identifier
				}

                for observation in results where observation is VNDetectedObjectObservation {
                    guard let objectObservation = observation as? VNDetectedObjectObservation else {
                        continue
                    }

                    output.1 = objectObservation.boundingBox
                }

                self.result.value = output
            }

			return objectRecognition
		} catch {
			throw error
		}
	}

    static func convert(value: Any?) -> CurrentValueSubject<(String, CGRect), Never>? {
        return value as? CurrentValueSubject<(String, CGRect), Never>
    }
}
