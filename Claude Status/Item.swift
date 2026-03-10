//
//  Item.swift
//  Claude Status
//
//  Created by Gavin M Roy on 3/10/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
