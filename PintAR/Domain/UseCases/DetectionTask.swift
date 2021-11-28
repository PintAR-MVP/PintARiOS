//
//  DetectionTask.swift
//  PintAR
//
//  Created by Niklas Amslgruber on 28.11.21.
//

import Foundation
import Vision

protocol DetectObjectUseCaseProtocol {

    func setupObjectDetection()

    func recognizeObject(in image: CVPixelBuffer, completion: @escaping (Result<[VNObservation], Error>) -> Void)
}

protocol DetectionTask {

    func setup() throws -> VNRequest
}
