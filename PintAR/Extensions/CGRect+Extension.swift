//
//  CGRect+Extension.swift
//  PintAR
//
//  Created by Tim Schröder on 13.02.22.
//

import UIKit

extension CGRect {
    func rectIntersectionInPerc(r: CGRect) -> Double {
        if (self.intersects(r) == true) {
           //let interRect:CGRect = r1.rectByIntersecting(r2); //OLD
           let interRect: CGRect = self.intersection(r)

           return ((interRect.width * interRect.height) / (((self.width * self.height) + (r.width * r.height)) / 2.0))
        }
        return 0
    }
}
