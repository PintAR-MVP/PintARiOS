//
//  CGPoint+Extension.swift
//  PintAR
//
//  Created by Daniel Klinkert on 23.11.21.
//

import UIKit

extension CGPoint {

	func scaled(to size: CGSize) -> CGPoint {
		return CGPoint(x: self.x * size.width, y: self.y * size.height)
	}
}
