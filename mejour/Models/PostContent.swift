import Foundation

/// 用於在貼文 body 中存儲和解析拍攝時間 / 標籤
/// 格式: [PHOTO_TIME:2024-01-15T10:30:00Z][TAGS:餐廳 · 讀書]\n內容文本
struct PostContent {
    let photoTakenTime: Date?
    let tags: [String]
    let text: String
    
    // 分隔符
    static let timeMarkerPrefix = "[PHOTO_TIME:"
    static let timeMarkerSuffix = "]"
    static let tagMarkerPrefix = "[TAGS:"
    
    /// 從 body 字串解析出拍攝時間和實際內容
    static func parse(_ body: String) -> PostContent {
        var remaining = body
        var time: Date?
        var tags: [String] = []

        // 解析拍攝時間
        if let startRange = remaining.range(of: timeMarkerPrefix) {
            if let endRange = remaining.range(of: timeMarkerSuffix, range: startRange.upperBound..<remaining.endIndex) {
                let timeString = String(remaining[startRange.upperBound..<endRange.lowerBound])
                time = ISO8601DateFormatter().date(from: timeString)
                remaining = String(remaining[endRange.upperBound...])
            }
        }

        // 解析標籤（僅檢查開頭）
        let trimmed = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
        if let tagStart = trimmed.range(of: tagMarkerPrefix),
           tagStart.lowerBound == trimmed.startIndex,
           let tagEnd = trimmed.range(of: timeMarkerSuffix, range: tagStart.upperBound..<trimmed.endIndex) {
            let tagString = String(trimmed[tagStart.upperBound..<tagEnd.lowerBound])
            tags = tagString
                .split(separator: "·")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            remaining = String(trimmed[tagEnd.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            remaining = trimmed
        }

        return PostContent(photoTakenTime: time, tags: tags, text: remaining)
    }
    
    /// 將拍攝時間和內容組合成 body 字串
    static func encode(photoTakenTime: Date?, tags: [String]?, text: String) -> String {
        var body = text

        if let tags, !tags.isEmpty {
            let tagString = tags.joined(separator: " · ")
            body = "\(tagMarkerPrefix)\(tagString)\(timeMarkerSuffix)\n\(body)"
        }

        if let time = photoTakenTime {
            let iso8601String = ISO8601DateFormatter().string(from: time)
            return "\(timeMarkerPrefix)\(iso8601String)\(timeMarkerSuffix)\(body)"
        }
        return body
    }
}
