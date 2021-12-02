//
//  DetectionTask.swift
//  PintAR
//
//  Created by Niklas Amslgruber on 28.11.21.
//

import Foundation
import Vision
import Combine

protocol DetectObjectUseCaseProtocol {

	func setupObjectDetection()

	func recognizeObject(in image: CVPixelBuffer)
}

protocol DetectionTask {

    /// The type of the results of the detection task
    associatedtype ResultType

    var result: CurrentValueSubject<ResultType, Never> { get set }

    /// Setup the detection task
    func setup() throws -> VNRequest

    /// Converter method for type casting the results without the need to know the actual type of the publisher
    static func convert(value: Any?) -> CurrentValueSubject<ResultType, Never>?
}
