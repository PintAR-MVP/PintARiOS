//
//  File.swift
//  PintAR
//
//  Created by Tim Schröder on 13.02.22.
//

import Foundation
import UIKit

class DetectedAngle: Identifiable {

    let id: UUID
    var visAngle = Int()

    init(id: UUID, visAngle: Int) {
        self.id = id
        self.visAngle = visAngle
    }
}
