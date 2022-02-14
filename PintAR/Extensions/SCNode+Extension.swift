//
//  SCNode+Extension.swift
//  PintAR
//
//  Created by Daniel Klinkert on 27.01.22.
//

import SceneKit

extension SCNNode {

	var height: Float {
		return (self.boundingBox.max.y - self.boundingBox.min.y) * self.scale.y
	}

	func pivotOnTopLeft() {
		let (min, max) = self.boundingBox
		self.pivot = SCNMatrix4MakeTranslation(min.x, max.y, 0)
	}

	func pivotOnTopCenter() {
		let (_, max) = self.boundingBox
		self.pivot = SCNMatrix4MakeTranslation(0, max.y, 0)
	}
}
