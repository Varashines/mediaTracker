import SwiftUI

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
    @State private var observer: NSObjectProtocol?
    @State private var clearObserver: NSObjectProtocol?
 
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
            removeObservers()
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
                Task { @MainActor in
                    guard !Task.isCancelled else { return }
                    await self.attemptLoad()
                }
            }
        }
        .onChange(of: SleepManager.shared.isAsleep) { oldValue, isAsleep in
            if isAsleep {
                self.image = nil
            } else {
                setupBroadcastListener()
                Task { @MainActor in
                    guard !Task.isCancelled else { return }
                    await self.attemptLoad()
                }
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
                        .font(AppTheme.Font.title2)
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
        let cachedTargetSize = self.targetSize
        
        removeObservers()
        
        // Per-key notification — only fires when THIS specific image is updated.
        // The closure is @Sendable so we capture only Sendable values and dispatch
        // all MainActor work through Task.
        observer = NotificationCenter.default.addObserver(
            forName: .imageCacheUpdated,
            object: nil,
            queue: .main
        ) { notification in
            guard let updatedKey = notification.userInfo?["key"] as? String, updatedKey == key else { return }
            Task { @MainActor in
                if ImageCache.shared.checkMemoryCache(forKey: key, targetSize: cachedTargetSize) == nil {
                    self.image = nil
                }
                await self.attemptLoad()
            }
        }
        
        // Global cache clear — fires when any cache is wiped
        clearObserver = NotificationCenter.default.addObserver(
            forName: .imageCacheCleared,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                self.image = nil
                await self.attemptLoad()
            }
        }
    }
    
    private func removeObservers() {
        if let obs = observer {
            NotificationCenter.default.removeObserver(obs)
            observer = nil
        }
        if let obs = clearObserver {
            NotificationCenter.default.removeObserver(obs)
            clearObserver = nil
        }
    }

    private func attemptLoad() async {
        guard !Task.isCancelled else { return }
        guard let url = url else { return }
        let key = url.absoluteString
        
        if let container = ImageCache.shared.checkMemoryCache(forKey: key, targetSize: targetSize) {
            let isExact = ImageCache.shared.isExactMatch(image: container.image, forURL: key, size: targetSize)
            
            if isExact {
                withAnimation(AppTheme.Animation.easeInOut) {
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
            withAnimation(AppTheme.Animation.easeInOut) {
                self.image = container.image
            }
            onImageLoaded?(container.image)
        }
    }
}
