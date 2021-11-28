//
//  RectangleDetection.swift
//  PintAR
//
//  Created by Niklas Amslgruber on 28.11.21.
//

import Vision

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
	
	private var visionModel: VNCoreMLModel?
	private let model: Model
	
	init(model: Model) {
		self.model = model
	}
	
	func setup() throws -> VNRequest {
		do {
			let visionModel = try VNCoreMLModel(for: MLModel(contentsOf: model.modelURL))
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
}
