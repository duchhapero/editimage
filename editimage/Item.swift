//
//  Item.swift
//  editimage
//
//  Created by Hoàng Đức on 4/9/26.
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
