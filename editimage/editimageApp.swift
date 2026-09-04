//
//  editimageApp.swift
//  editimage
//
//  Created by Hoàng Đức on 4/9/26.
//

import SwiftUI
import SwiftData

@main
struct editimageApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(for: Project.self)
    }
}
