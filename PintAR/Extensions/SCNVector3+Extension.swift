//
//  SCNVector3+Extension.swift
//  PintAR
//
//  Created by Tim Schröder on 03.02.22.
//

import Foundation
import SceneKit

extension SCNVector3 {

	func length() -> Float {
		return sqrtf(x * x + y * y + z * z)
	}

	func distance(vector: SCNVector3) -> Float {
		return (self - vector).length()
	}

	static func - (left: SCNVector3, right: SCNVector3) -> SCNVector3 {
		return SCNVector3Make(left.x - right.x, left.y - right.y, left.z - right.z)
	}
}
