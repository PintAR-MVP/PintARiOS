//
//  UIImage+Extension.swift
//  PintAR
//
//  Created by Daniel Klinkert on 27.01.22.
//

import UIKit

extension UIImage {

	/// Transform an UIImage to a CVPixelBuffer
	/// - Parameter image: image extracted from the ARKitScene
	/// - Returns: CVPixelBuffer
	func transformImageToBuffer() -> CVPixelBuffer? {
		let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue, kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary
		var pixelBuffer: CVPixelBuffer?
		let status = CVPixelBufferCreate(kCFAllocatorDefault, Int(self.size.width), Int(self.size.height), kCVPixelFormatType_32ARGB, attrs, &pixelBuffer)
		guard status == kCVReturnSuccess else {
			return nil
		}

		// swiftlint:disable:next force_unwrapping
		CVPixelBufferLockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
		// swiftlint:disable:next force_unwrapping
		let pixelData = CVPixelBufferGetBaseAddress(pixelBuffer!)

		let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
		// swiftlint:disable:next force_unwrapping
		let context = CGContext(data: pixelData, width: Int(self.size.width), height: Int(self.size.height), bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer!), space: rgbColorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)

		context?.translateBy(x: 0, y: self.size.height)
		context?.scaleBy(x: 1.0, y: -1.0)

		// swiftlint:disable:next force_unwrapping
		UIGraphicsPushContext(context!)
		self.draw(in: CGRect(x: 0, y: 0, width: self.size.width, height: self.size.height))
		UIGraphicsPopContext()
		// swiftlint:disable:next force_unwrapping
		CVPixelBufferUnlockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))

		return pixelBuffer
	}
}
