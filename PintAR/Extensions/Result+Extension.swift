//
//  Result+Extension.swift
//  PintAR
//
//  Created by Daniel Klinkert on 23.11.21.
//

import Foundation

extension Result where Success == Void {

	public static var success: Result {
		return .success(())
	}
}
