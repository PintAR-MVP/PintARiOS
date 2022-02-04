//
//  DetectedObject.swift
//  PintAR
//
//  Created by Daniel Klinkert on 08.01.22.
//

import Foundation
import CoreGraphics
import UIKit
import Combine

class DetectedObject: Identifiable {

	let id: UUID
	let boundingBox: CGRect
	var image: UIImage?
	var text: String?
	var color: UIColor?
    var shape: [CGPath]?
    private var cancellableSet: Set<AnyCancellable> = []

    // All matches returned by the backend
    @Published var allMatches: [Product] = []

    // Backend match with the highest score
    @Published var highestScoreProduct: Product?

	init(id: DetectedObject.ID, boundingBox: CGRect) {
		self.id = id
		self.boundingBox = boundingBox
	}

    func queryBackend() {
        guard let text = text else {
            return
        }

        cancellableSet = []

        let searchQuery = SearchQuery(text: text, color: color, shape: shape, category: "", minimumScore: nil, limit: nil)

        API.search(with: searchQuery)
            .sink(receiveCompletion: { result in
                switch result {
                case .finished:
                    print("Successfully requested search data")
                case .failure(let error):
                    print("Request failed with error \(error)")
                }
            }, receiveValue: { value in
                self.allMatches = value
                self.highestScoreProduct = value.max(by: { lh, rh in
                    lh.score < rh.score
                })
                print("Received \(value.count) results.")
            })
            .store(in: &cancellableSet)
    }

    func cancelRequest() {
        cancellableSet = []
    }
}

extension DetectedObject: Hashable {

	static func == (lhs: DetectedObject, rhs: DetectedObject) -> Bool {
		return lhs.boundingBox == rhs.boundingBox && lhs.id == rhs.id
	}

	func hash(into hasher: inout Hasher) {
		hasher.combine(self.id)
	}
}
