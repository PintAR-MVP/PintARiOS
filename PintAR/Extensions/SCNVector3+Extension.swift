//
//  File.swift
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

    // Return the angle between this vector and the specified vector v
    func angle(v: SCNVector3) -> Double {
        // angle between 3d vectors P and Q is equal to the arc cos of their dot products over the product of
        // their magnitudes (lengths).
        //    theta = arccos( (P • Q) / (|P||Q|) )
        let dp = dot(v) // dot product
        let magProduct = length() * v.length() // product of lengths (magnitudes)
        return Double(acos(dp / magProduct)) * 180 / Double.pi // Return in Degrees
    }

    func dot(_ vec: SCNVector3) -> Float {
        return (self.x * vec.x) + (self.y * vec.y) + (self.z * vec.z)
    }
}
