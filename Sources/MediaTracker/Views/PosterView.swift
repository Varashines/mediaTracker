import SwiftUI

struct PosterView: View {
    let item: MediaItem
    let themeColor: Color
    var posterOptions: [String] = []
    var isCustomPoster: Bool = false
    var onSelectPoster: ((String) -> Void)? = nil
    var onResetPoster: (() -> Void)? = nil

    private let posterFrame = CGSize(width: 260, height: 390)
    @Environment(\.colorScheme) private var colorScheme
    @State private var glowPulse = false
    @State private var isHovering = false
    @State private var showPicker = false

    var body: some View {
        if let urlString = item.effectivePosterURL, let url = URL(string: urlString) {
            ZStack {
                RadialGradient(
                    colors: [
                        themeColor.opacity(colorScheme == .dark ? 0.65 : 0.65),
                        themeColor.opacity(colorScheme == .dark ? 0.25 : 0.25),
                        .clear
                    ],
                    center: .center,
                    startRadius: 10,
                    endRadius: 250
                )
                .frame(width: posterFrame.width * 1.38, height: posterFrame.height * 1.26)
                .allowsHitTesting(false)

                CachedImage(url: url, targetSize: .thumbMedium, priority: .normal, themeColor: themeColor) { _ in
                } placeholder: {
                        Rectangle().fill(Color.secondary.opacity(0.1)).shimmering()
                            .overlay {
                                Image(systemName: item.type == .movie ? "film" : "tv")
                                    .foregroundStyle(AppTheme.Colors.accent)
                                    .font(.system(size: 24, weight: .medium))
                            }
                }
                .aspectRatio(contentMode: .fill)
                .frame(width: posterFrame.width, height: posterFrame.height)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
                .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 8)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
                .overlay(alignment: .topLeading) {
                    SmartBadgeView(item: item)
                        .padding(14)
                }
                .overlay(alignment: .topTrailing) {
                    if posterOptions.count > 1 {
                        Button {
                            showPicker.toggle()
                        } label: {
                            Image(systemName: showPicker ? "square.stack.3d.down.right.fill" : "square.stack.3d.down.right")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(showPicker ? Color.primary : .primary)
                                .padding(7)
                                .background {
                                    if showPicker {
                                        Circle().fill(Color.primary.opacity(0.12))
                                    } else {
                                        Circle().fill(.ultraThinMaterial)
                                    }
                                }
                                .shadow(color: .black.opacity(showPicker ? 0.25 : 0.15), radius: showPicker ? 4 : 3, x: 0, y: showPicker ? 3 : 2)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .help("Change poster")
                        .opacity((isHovering || showPicker) ? 1 : 0)
                        .scaleEffect((isHovering || showPicker) ? 1 : 0.85)
                        .animation(.easeInOut(duration: 0.2), value: isHovering || showPicker)
                        .padding(10)
                        .popover(isPresented: $showPicker) {
                            PosterPickerGrid(
                                options: posterOptions,
                                currentURL: item.effectivePosterURL,
                                isCustom: isCustomPoster,
                                onSelect: { url in
                                    onSelectPoster?(url)
                                    showPicker = false
                                },
                                onReset: {
                                    onResetPoster?()
                                    showPicker = false
                                }
                            )
                        }
                    }
                }
            }
            .if(!AppThemeCoordinator.isReducingVisualEffects) { $0.compositingGroup() }
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    glowPulse = true
                } else {
                    if !AppThemeCoordinator.isReducingVisualEffects {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            glowPulse = false
                        }
                    } else {
                        glowPulse = false
                    }
                }
            }
            .onAppear { glowPulse = false }
        }
    }
}

private struct PosterPickerGrid: View {
    let options: [String]
    let currentURL: String?
    let isCustom: Bool
    let onSelect: (String) -> Void
    let onReset: () -> Void

    private let thumbnailSize = CGSize(width: 100, height: 150)
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.down.right")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text("Select Poster")
                    .font(.system(size: 12, weight: .semibold))
                Text("·")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Text("\(options.count)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            .padding(.top, 16)
            .padding(.bottom, 10)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(options, id: \.self) { urlString in
                        PosterThumbnail(
                            urlString: urlString,
                            isSelected: urlString == currentURL,
                            size: thumbnailSize,
                            onSelect: { onSelect(urlString) }
                        )
                    }
                }
                .padding(.horizontal, 14)
            }
            .frame(maxHeight: min(CGFloat((options.count + 2) / 3) * (thumbnailSize.height + 10) + 4, 360))

            if isCustom {
                Divider()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)

                Button {
                    onReset()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 10))
                        Text("Reset to default")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.04))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
        }
        .frame(width: 340)
    }
}

private struct PosterThumbnail: View {
    let urlString: String
    let isSelected: Bool
    let size: CGSize
    let onSelect: () -> Void
    @State private var isHovered = false
    @State private var selectionPulse = false

    var body: some View {
        if let url = URL(string: urlString) {
            CachedImage(url: url, targetSize: .thumbTiny, priority: .low) { _ in
            } placeholder: {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.06))
                    .shimmering()
            }
            .aspectRatio(contentMode: .fill)
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(isHovered ? 0.18 : 0), radius: isHovered ? 8 : 0, y: isHovered ? 4 : 0)
            .overlay(alignment: .bottomTrailing) {
                if isSelected {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 20, height: 20)
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.primary)
                    }
                    .padding(6)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.primary.opacity(0.25) : (isHovered ? Color.secondary.opacity(0.2) : .clear), lineWidth: isSelected ? 1.5 : 1)
            )
            .if(!AppThemeCoordinator.isReducingVisualEffects) {
                $0.scaleEffect(isHovered ? 1.03 : 1.0)
                    .scaleEffect(selectionPulse ? 0.92 : 1.0)
                    .animation(AppTheme.Animation.springSnappy, value: isHovered)
            }
            .onHover { hovering in
                isHovered = hovering
            }
            .onTapGesture {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) {
                    selectionPulse = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) {
                        selectionPulse = false
                    }
                }
                onSelect()
            }
        }
    }
}
