//
//  FaceMask.swift
//  RayTracingExample
//
//  Created by David Crooks on 09/09/2020.
//  Copyright © 2020 David Crooks. All rights reserved.
//

import Foundation


struct FaceMask: OptionSet {
    let rawValue: Int
  
    static let negative_X = FaceMask(rawValue: 1 << 0)
    static let positive_X = FaceMask(rawValue: 1 << 1)
    static let negative_Y = FaceMask(rawValue: 1 << 2)
    static let positive_Y = FaceMask(rawValue: 1 << 3)
    static let negative_Z = FaceMask(rawValue: 1 << 4)
    static let positive_Z = FaceMask(rawValue: 1 << 5)
    
    static let all:FaceMask = [ negative_X,
                                positive_X,
                                negative_Y,
                                positive_Y,
                                negative_Z,
                                positive_Z ]
    
}
