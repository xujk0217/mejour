import Foundation

/// 用於在貼文 body 中存儲和解析拍攝時間
/// 格式: [PHOTO_TIME:2024-01-15T10:30:00Z]內容文本
struct PostContent {
    let photoTakenTime: Date?
    let text: String
    
    // 分隔符
    static let timeMarkerPrefix = "[PHOTO_TIME:"
    static let timeMarkerSuffix = "]"
    
    /// 從 body 字串解析出拍攝時間和實際內容
    static func parse(_ body: String) -> PostContent {
        if let startRange = body.range(of: timeMarkerPrefix),
           let endRange = body.range(of: timeMarkerSuffix, range: startRange.upperBound..<body.endIndex) {
            let timeString = String(body[startRange.upperBound..<endRange.lowerBound])
            let photoTime = ISO8601DateFormatter().date(from: timeString)
            let text = String(body[endRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            return PostContent(photoTakenTime: photoTime, text: text)
        }
        // 沒有時間標記，整個 body 就是內容
        return PostContent(photoTakenTime: nil, text: body)
    }
    
    /// 將拍攝時間和內容組合成 body 字串
    static func encode(photoTakenTime: Date?, text: String) -> String {
        if let time = photoTakenTime {
            let iso8601String = ISO8601DateFormatter().string(from: time)
            return "\(timeMarkerPrefix)\(iso8601String)\(timeMarkerSuffix)\(text)"
        }
        return text
    }
}
