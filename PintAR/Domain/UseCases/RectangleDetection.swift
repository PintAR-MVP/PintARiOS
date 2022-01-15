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
		case yoloV5

		var name: String {
			switch self {
			case .yoloV5:
				return "YOLOv5-train"
			}
		}

		var modelURL: URL {
			let url: URL?
			switch self {
			case .yoloV5:
				url = Bundle.main.url(forResource: self.name, withExtension: "mlmodelc")
			}

			return url ?? URL(fileURLWithPath: "")
		}
	}

	var result = CurrentValueSubject<[DetectedObject], Never>([DetectedObject]())

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

				var output = [DetectedObject]()
				for observation in results where observation is VNDetectedObjectObservation {
					guard let objectObservation = observation as? VNDetectedObjectObservation, observation.confidence > 0.7 else {
						continue
					}

					let currentDetectedObject = DetectedObject(id: observation.uuid, boundingBox: objectObservation.boundingBox)
					output.append(currentDetectedObject)
				}

				self.result.value = output
			}

			return objectRecognition
		} catch {
			throw error
		}
	}

	static func convert(value: Any?) -> CurrentValueSubject<[DetectedObject], Never>? {
		return value as? CurrentValueSubject<[DetectedObject], Never>
	}
}
