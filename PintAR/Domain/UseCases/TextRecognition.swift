//
//  TextRecognition.swift
//  PintAR
//
//  Created by Niklas Amslgruber on 28.11.21.
//

import Vision

class TextRecognition: DetectionTask {

    @Published var recognizedText: [String] = []
    private let fastRecognition: Bool

    init(fastRecognition: Bool) {
        self.fastRecognition = fastRecognition
    }

    func setup() -> VNRequest {
        let textDetectionRequest = VNRecognizeTextRequest { request, _ in

            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                return
            }
            let recognizedStrings = observations.compactMap { observation in
                return observation.topCandidates(1).first?.string
            }

            self.recognizedText = recognizedStrings
        }

        textDetectionRequest.recognitionLevel = fastRecognition ? .fast : .accurate
        textDetectionRequest.recognitionLanguages = ["de-DE"]
        return textDetectionRequest
    }
}
