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

    @Published var recognizedText: [String] = []
    @Published var objectFrame: CGRect = .zero
    @Published var objectIdentifier: String = ""

    private var cancellableSet: Set<AnyCancellable> = []
    private let detectObjectUseCase: DetectObjectUseCaseProtocol

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
            case .text(fastRecognition: _):
                TextRecognition.convert(value: value)?
                    .assign(to: \.recognizedText, on: self)
                    .store(in: &cancellableSet)
            case .rectangles(model: _):
                RectangleDetection.convert(value: value)?
                    .sink(receiveValue: { (identifier, frame) in
                        self.objectIdentifier = identifier
                        self.objectFrame = frame
                    })
                    .store(in: &cancellableSet)
            }
        }
    }

	func recognizeObject(image: CVImageBuffer) {
        self.detectObjectUseCase.recognizeObject(in: image)
	}
}
