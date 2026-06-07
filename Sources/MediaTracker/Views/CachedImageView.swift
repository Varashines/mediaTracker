import SwiftUI
import Combine

struct CachedImage<Placeholder: View>: View {
    let url: URL?
    let targetSize: CGSize?
    let priority: ImagePriority
    var themeColor: Color? = nil
    var isFastScrolling: Bool = false
    var alwaysPreserveAlpha: Bool = false
    var accessibilityLabel: String? = nil
    var onImageLoaded: ((CGImage) -> Void)? = nil
    @ViewBuilder let placeholder: Placeholder
    
    @State private var image: CGImage?
    @State private var isLoading = false
    @State private var broadcastCancellable: AnyCancellable?
 
    init(url: URL?, targetSize: CGSize? = nil, priority: ImagePriority = .normal, themeColor: Color? = nil, isFastScrolling: Bool = false, alwaysPreserveAlpha: Bool = false, accessibilityLabel: String? = nil, onImageLoaded: ((CGImage) -> Void)? = nil, @ViewBuilder placeholder: () -> Placeholder) {
        self.url = url
        self.targetSize = targetSize
        self.priority = priority
        self.themeColor = themeColor
        self.isFastScrolling = isFastScrolling
        self.alwaysPreserveAlpha = alwaysPreserveAlpha
        self.accessibilityLabel = accessibilityLabel
        self.onImageLoaded = onImageLoaded
        self.placeholder = placeholder()
        
        if let url = url, let container = ImageCache.shared.checkMemoryCache(forKey: url.absoluteString, targetSize: targetSize) {
            let isExact = ImageCache.shared.isExactMatch(image: container.image, forURL: url.absoluteString, size: targetSize)
            if isExact {
                _image = State(initialValue: container.image)
            }
        }
    }
    
    var body: some View {
        Group {
            if isFastScrolling && image == nil {
                staticPlaceholder
            } else if let finalImage = image {
                Image(finalImage, scale: 1.0, label: Text(accessibilityLabel ?? "Poster"))
                    .resizable()
                    .transition(.opacity)
            } else {
                staticPlaceholder
            }
        }
        .animation(.default, value: image)
        .onAppear {
            setupBroadcastListener()
        }
        .onDisappear {
            if let url = url {
                ImageCache.shared.cancel(forKey: url.absoluteString, targetSize: targetSize)
            }
        }
        .task(id: url) {
            if !isFastScrolling {
                await attemptLoad()
            }
        }
        .onChange(of: isFastScrolling) { oldValue, newValue in
            if !newValue && image == nil {
                Task { await attemptLoad() }
            }
        }
        .onChange(of: SleepManager.shared.isAsleep) { oldValue, isAsleep in
            if isAsleep {
                self.image = nil
            } else {
                setupBroadcastListener()
                Task { await attemptLoad() }
            }
        }
    }

    @ViewBuilder
    private var staticPlaceholder: some View {
        if let color = themeColor {
            Rectangle()
                .fill(color.opacity(0.15))
                .overlay {
                    Image(systemName: "film")
                        .foregroundStyle(color.opacity(0.3))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                }
        } else {
            ZStack {
                Color.secondary.opacity(0.1)
                placeholder
            }
        }
    }

    private func setupBroadcastListener() {
        guard let url = url else { return }
        let key = url.absoluteString
        
        broadcastCancellable?.cancel()
        broadcastCancellable = ImageCache.shared.updates
            .filter { $0 == key || $0 == "CLEARED_ALL" }
            .receive(on: DispatchQueue.main)
            .sink { _ in
                if ImageCache.shared.checkMemoryCache(forKey: key, targetSize: targetSize) == nil {
                    self.image = nil
                }
                Task { await attemptLoad() }
            }
    }

    private func attemptLoad() async {
        guard let url = url else { return }
        let key = url.absoluteString
        
        if let container = ImageCache.shared.checkMemoryCache(forKey: key, targetSize: targetSize) {
            let isExact = ImageCache.shared.isExactMatch(image: container.image, forURL: key, size: targetSize)
            
            if isExact {
                withAnimation(.easeIn(duration: 0.2)) {
                    self.image = container.image
                }
                return
            }
        }
        
        await loadImage()
    }
    
    private func loadImage() async {
        guard let url = url, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        
        if let container = await ImageCache.shared.get(forKey: url.absoluteString, targetSize: targetSize, priority: priority, alwaysPreserveAlpha: alwaysPreserveAlpha) {
            if Task.isCancelled { return }
            withAnimation(.easeIn(duration: 0.25)) {
                self.image = container.image
            }
            onImageLoaded?(container.image)
        }
    }
}
