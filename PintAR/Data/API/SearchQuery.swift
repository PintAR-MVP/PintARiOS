//
//  SearchQuery.swift
//  PintAR
//
//  Created by Niklas Amslgruber on 13.01.22.
//

import Foundation
import CoreGraphics
import UIKit

struct SearchQuery: Encodable {

	private let text: String
	private let colorHex: String?
	private var shape = [[CGFloat]]()
	private let category: String?
	private let minimumScore: Int?
	private let limit: Int?

	private enum NestedCodingKeys: String, CodingKey {
		case text
		case color
		case shape
		case category
	}

	private enum CodingKeys: String, CodingKey {
		case textFilter
		case colorFilter
		case shapeFilter
		case categoryFilter
		case minimumScore
		case limit
	}

	/// Search query to find all products that match the specified filters
	/// - Parameters:
	///   - text: Recognized text
	///   - colorHex: Average color
	///   - shape: Product shape
	///   - category: Product category
	///   - minimumScore: Minimum score to be included in matches (default: 10)
	///   - limit: Maximum number of returned matches (default: 10)
	init(text: String, color: UIColor? = nil, shape: [CGPath]? = nil, category: String? = nil, minimumScore: Int? = nil, limit: Int? = nil) {
		self.text = text
        self.colorHex = Self.toHex(color: color)
		self.category = category
		self.minimumScore = minimumScore
		self.limit = limit

		for path in (shape?.map { $0.points } ?? []) {
			for point in path {
				self.shape.append([point.x, point.y])
			}
		}
	}

    private static func toHex(color: UIColor?) -> String? {
        guard let color = color, let components = color.cgColor.components, components.count >= 3 else {
            return nil
        }

        let r = Float(components[0])
        let g = Float(components[1])
        let b = Float(components[2])

        return String(format: "%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255))
    }

	func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)

		var textContainer = container.nestedContainer(keyedBy: NestedCodingKeys.self, forKey: .textFilter)
		try textContainer.encodeIfPresent(text, forKey: NestedCodingKeys.text)

		if colorHex != nil {
			var colorContainer = container.nestedContainer(keyedBy: NestedCodingKeys.self, forKey: .colorFilter)
			try colorContainer.encodeIfPresent(colorHex, forKey: NestedCodingKeys.color)
		}

		if shape.isEmpty == false {
			var shapeContainer = container.nestedContainer(keyedBy: NestedCodingKeys.self, forKey: .shapeFilter)
			try shapeContainer.encodeIfPresent(shape, forKey: NestedCodingKeys.shape)
		}

		if category != nil, self.category?.isEmpty == false {
			var categoryContainer = container.nestedContainer(keyedBy: NestedCodingKeys.self, forKey: .categoryFilter)
			try categoryContainer.encodeIfPresent(category, forKey: NestedCodingKeys.category)
		}

		try container.encodeIfPresent(minimumScore, forKey: CodingKeys.minimumScore)
		try container.encodeIfPresent(limit, forKey: CodingKeys.limit)
	}
}

// https://stackoverflow.com/questions/12992462/how-to-get-the-cgpoints-of-a-cgpath/12992504#12992504
extension CGPath {

    var points: [CGPoint] {

        var arrPoints: [CGPoint] = []
        self.applyWithBlock { element in

            switch element.pointee.type {
            case .moveToPoint, .addLineToPoint:
                arrPoints.append(element.pointee.points.pointee)

            case .addQuadCurveToPoint:
                arrPoints.append(element.pointee.points.pointee)
                arrPoints.append(element.pointee.points.advanced(by: 1).pointee)

            case .addCurveToPoint:
                arrPoints.append(element.pointee.points.pointee)
                arrPoints.append(element.pointee.points.advanced(by: 1).pointee)
                arrPoints.append(element.pointee.points.advanced(by: 2).pointee)

            default:
                break
            }
        }

        return arrPoints
    }
}
