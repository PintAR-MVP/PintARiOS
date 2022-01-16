//
//  Product.swift
//  PintAR
//
//  Created by Niklas Amslgruber on 13.01.22.
//

import Foundation

struct Product: Codable {
    var id: String
    var name: String
    var score: Double
}

struct Products: Codable {
    var matches: [Product]
}
