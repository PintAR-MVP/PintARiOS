//
//  CameraViewModel.swift
//  PintAR
//
//  Created by Daniel Klinkert on 23.11.21.
//

import Foundation
import Vision
import Combine

class CameraViewModel {

	@Published private(set) var accurateObjects = [DetectedObject]()

	private let recognizeObjectQueue = DispatchQueue(label: "RecognizeObject", qos: .userInitiated)
	private var cancellableSet: Set<AnyCancellable> = []
	private let detectObjectUseCase: DetectObjectUseCaseProtocol
	private let extractImageUseCase: ExtractImageUseCaseProtocol = ExtractImageUseCase()
	private let detectColorUseCase: ColorDetectionProtocol = ColorDetection()
	private let textRecognition: TextRecognitionProtocol = TextRecognition(fastRecognition: false)
	private let shapeRecognition: ContourDetection = ContourDetection()

	/// Represents the image captured by the camera where the object will be recognised
	private var recognisedObjectContainerImage: CVImageBuffer?
	private(set) var detectedObjects = [DetectedObject]()
	var stop: Bool = false

	init(detectObjectUseCase: DetectObjectUseCaseProtocol) {
		self.detectObjectUseCase = detectObjectUseCase
	}

	func configureVision() {
		self.detectObjectUseCase.setupObjectDetection()

		self.setupSubscribers()
	}

	private func setupSubscribers() {
		guard let results = (detectObjectUseCase as? DetectObjectUseCase)?.results else {
			return
		}

		for key in results.keys {
			let value = results[key]
			switch key {
			case .rectangles(model: _):
				RectangleDetection.convert(value: value)?
					.sink(receiveValue: { (detectedObjects) in
						guard self.stop == false else {
							// self.performDetectionsOnRecognisedBoundingBoxes()
							return
						}

						self.detectedObjects = detectedObjects
						self.performDetectionsOnRecognisedBoundingBoxes()
					})
					.store(in: &cancellableSet)
			}
		}
	}

	func recognizeObject(image: CVImageBuffer) {
		self.recognisedObjectContainerImage = image
		self.recognizeObjectQueue.async {
			self.detectObjectUseCase.recognizeObject(in: image)
		}
	}

	func performDetectionsOnRecognisedBoundingBoxes() {
		guard
			let currentImage = self.recognisedObjectContainerImage,
			self.detectedObjects.isEmpty == false else {
				self.accurateObjects.removeAll()
				self.stop = false
				return
		}

		var rectangleObservations = [DetectedObject: VNRectangleObservation]()
		for object in self.detectedObjects {
			let rectangle = VNRectangleObservation(boundingBox: object.boundingBox)
			rectangleObservations[object] = rectangle
		}

		for rectangleObservation in rectangleObservations {
			guard let extractedImage = self.extractImageUseCase.imageExtraction(rectangleObservation.value, from: currentImage) else {
				// remove the detected objects where we cant extract the image
				if let index = self.detectedObjects.firstIndex(of: rectangleObservation.key) {
					self.detectedObjects.remove(at: index)
				}

				continue
			}

			let detectedObject = rectangleObservation.key
			detectedObject.image = extractedImage
		}

		for result in self.detectedObjects {
			guard let detectedObjectImage = result.image else {
				continue
			}

			if let detectedColor = self.detectColorUseCase.getAverageColor(image: detectedObjectImage) {
				result.color = detectedColor
			}

			if let preProcessImage = self.shapeRecognition.preprocess(buffer: detectedObjectImage) {
				result.shape = self.shapeRecognition.recognizeShape(in: preProcessImage)
			}

			result.text = self.textRecognition.recognizeText(in: detectedObjectImage)
		}

        // Stop all previous requests
        accurateObjects.forEach({ $0.cancelRequest() })

		self.accurateObjects = self.detectedObjects.filter { $0.image != nil && $0.text != nil }

		if self.accurateObjects.isEmpty {
			self.detectedObjects.removeAll()
			self.accurateObjects.removeAll()
			self.stop = false
		}

        // Start queries
        accurateObjects.forEach({ $0.queryBackend() })
        print("\(accurateObjects.count) Queries started")

		print(self.accurateObjects.count)
	}
}
