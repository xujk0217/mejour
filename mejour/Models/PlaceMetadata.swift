//
//  PlaceMetadata.swift
//  mejour
//
//  Created by 許君愷 on 2025/12/19.
//


import Foundation

struct PlaceMetadata: Codable {
    var type: PlaceType?
    var tags: [String]?
}

enum PlaceMetadataCodec {
    static func encode(type: PlaceType, tags: [String]) -> String {
        do {
            let data = try JSONEncoder().encode(PlaceMetadata(type: type, tags: tags))
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return "{}"
        }
    }

    static func decode(_ raw: String?) -> PlaceMetadata? {
        guard let raw, !raw.isEmpty, raw != "string" else { return nil }
        guard let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PlaceMetadata.self, from: data)
    }
}
