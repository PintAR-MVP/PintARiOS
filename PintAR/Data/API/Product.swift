//
//  Product.swift
//  PintAR
//
//  Created by Niklas Amslgruber on 13.01.22.
//

import Foundation

struct Product: Codable {
	let id: String
	let name: String
	let score: Double
}

struct Products: Codable {
	var matches: [Product]
}
