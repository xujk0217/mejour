import SwiftUI

struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL
    let content: (Image) -> Content
    let placeholder: () -> Placeholder

    @State private var uiImage: UIImage? = nil

    init(url: URL,
         @ViewBuilder content: @escaping (Image) -> Content,
         @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let ui = uiImage {
                content(Image(uiImage: ui))
            } else {
                placeholder()
                    .task {
                        await load()
                    }
            }
        }
    }

    private func load() async {
        // check cache first
        if let cached = ImageCache.shared.image(forKey: url.absoluteString) {
            await MainActor.run { uiImage = cached }
            return
        }

        // download
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let img = UIImage(data: data) {
                ImageCache.shared.setImage(img, forKey: url.absoluteString)
                await MainActor.run { uiImage = img }
            }
        } catch {
            // ignore failure; placeholder remains
        }
    }
}
