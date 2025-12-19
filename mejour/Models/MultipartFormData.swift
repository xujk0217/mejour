//
//  MultipartFormData.swift
//  mejour
//
//  Created by 許君愷 on 2025/12/19.
//


import Foundation

struct MultipartFormData {
    private let boundary: String
    private var body = Data()

    init(boundary: String = "Boundary-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    mutating func addText(name: String, value: String) {
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        body.appendString("\(value)\r\n")
    }

    mutating func addFile(name: String, filename: String, mimeType: String, fileData: Data) {
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        body.appendString("Content-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        body.appendString("\r\n")
    }

    mutating func finalize() -> (data: Data, contentType: String) {
        body.appendString("--\(boundary)--\r\n")
        return (body, "multipart/form-data; boundary=\(boundary)")
    }
}

private extension Data {
    mutating func appendString(_ s: String) {
        if let d = s.data(using: .utf8) { append(d) }
    }
}
