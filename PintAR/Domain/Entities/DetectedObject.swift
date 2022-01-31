//
//  DetectedObject.swift
//  PintAR
//
//  Created by Daniel Klinkert on 08.01.22.
//

import Foundation
import CoreGraphics
import UIKit

class DetectedObject: Identifiable {

	let id: UUID
	let boundingBox: CGRect
	var image: UIImage?
	var text: String?
	var color: UIColor?
	var shape = [CGPath]()

	init(id: DetectedObject.ID, boundingBox: CGRect) {
		self.id = id
		self.boundingBox = boundingBox
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
