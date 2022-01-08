//
//  ColorDetection.swift
//  PintAR
//
//  Created by Niklas Amslgruber on 05.01.22.
//

import Foundation
import UIKit

protocol ColorDetectionProtocol {

	func getAverageColor(image: UIImage) -> UIColor?
}

struct ColorDetection: ColorDetectionProtocol {

	typealias RGBA = (Double, Double, Double, Double)

	func getAverageColor(image: UIImage) -> UIColor? {
		guard let currentImage = CIImage(image: image) else {
			return nil
		}

		// Source: https://www.hackingwithswift.com/example-code/media/how-to-read-the-average-color-of-a-uiimage-using-ciareaaverage
		let extentVector = CIVector(x: currentImage.extent.origin.x, y: currentImage.extent.origin.y, z: currentImage.extent.size.width, w: currentImage.extent.size.height)

		guard let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: currentImage, kCIInputExtentKey: extentVector]) else { return nil }

		guard let outputImage = filter.outputImage else { return nil }

		var bitmap = [UInt8](repeating: 0, count: 4)
		let context = CIContext(options: [.workingColorSpace: kCFNull])
		context.render(outputImage, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)

		return UIColor(red: CGFloat(bitmap[0]) / 255, green: CGFloat(bitmap[1]) / 255, blue: CGFloat(bitmap[2]) / 255, alpha: CGFloat(bitmap[3]) / 255)
	}

	/// Measures the variance between two colors
	/// The smaller the result, the more similar the colors
	/// **Underlying formula:** (r1-r2)^2 + (g1-g2)^2 + (b1-b2)^2
	///
	/// **Note:** In my experiments a threshold of around 0.3 led to good results
	func getColorDistance(l: UIColor, r: UIColor) -> Double {
		let (red1, green1, blue1, _) = getRGBA(for: l)
		let (red2, green2, blue2, _) = getRGBA(for: r)

		return pow(red2 - red1, 2) + pow(green2 - green1, 2) + pow(blue2 - blue1, 2)
	}

	func getRGBA(for color: UIColor) -> RGBA {
		var red: CGFloat = 0
		var green: CGFloat = 0
		var blue: CGFloat = 0
		var alpha: CGFloat = 0
		color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
		return (red, green, blue, alpha)
	}
}
