import Foundation
import os

enum Log {
    static let app = Logger(subsystem: "com.vox.app", category: "app")
    static let pipeline = Logger(subsystem: "com.vox.app", category: "pipeline")
    static let download = Logger(subsystem: "com.vox.app", category: "download")
    static let input = Logger(subsystem: "com.vox.app", category: "input")
}
