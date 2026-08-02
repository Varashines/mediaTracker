import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct CustomShareMenuView: View {
    let image: NSImage
    let title: String
    let onDismiss: () -> Void

    var themeColor: Color = AppTheme.Colors.accent
    var secondaryColor: Color? = nil
    var mutedColor: Color? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var showCopiedToast = false

    var body: some View {
        VStack(spacing: 20) {
            headerRow

            // Card Mini Preview
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 260)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppTheme.Colors.strokeDefault(for: colorScheme), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.4), radius: 16, y: 8)

            // Primary Quick Actions Grid
            HStack(spacing: 12) {
                quickActionButton(
                    title: showCopiedToast ? "Copied!" : "Copy Image",
                    icon: showCopiedToast ? "checkmark" : "doc.on.doc",
                    accent: showCopiedToast ? .green : themeColor
                ) {
                    copyToClipboard()
                }

                quickActionButton(
                    title: "Save PNG...",
                    icon: "square.and.arrow.down",
                    accent: secondaryColor ?? .blue
                ) {
                    saveImageToFile()
                }
            }

            Divider()
                .background(AppTheme.Colors.strokeDefault(for: colorScheme))

            // System Sharing Services
            VStack(alignment: .leading, spacing: 10) {
                Text("SHARE VIA")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .kerning(1.5)
                    .foregroundStyle(themeColor.opacity(0.7))

                let services = availableSharingServices
                if services.isEmpty {
                    Text("No sharing services available")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(services, id: \.title) { service in
                                Button {
                                    service.perform(withItems: [image])
                                    onDismiss()
                                } label: {
                                    VStack(spacing: 6) {
                                        ZStack {
                                            Circle()
                                                .fill(Color.primary.opacity(0.08))
                                                .frame(width: 44, height: 44)

                                            Image(nsImage: service.image)
                                                .resizable()
                                                .aspectRatio(contentMode: .fit)
                                                .frame(width: 24, height: 24)
                                        }

                                        Text(service.title)
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(.primary.opacity(0.85))
                                            .lineLimit(1)
                                    }
                                    .frame(width: 60)
                                }
                                .buttonStyle(.plain)
                                .contentShape(Rectangle())
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .padding(22)
        .frame(width: 360)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(AppTheme.Colors.background(for: colorScheme))
                if let muted = mutedColor {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(muted.opacity(colorScheme == .dark ? 0.20 : 0.10))
                }
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [themeColor.opacity(0.4), (secondaryColor ?? themeColor).opacity(0.2), AppTheme.Colors.strokeDefault(for: colorScheme)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: .black.opacity(0.5), radius: 30, y: 15)
        )
    }

    private var availableSharingServices: [NSSharingService] {
        let sel = NSSelectorFromString("sharingServicesForItems:")
        if (NSSharingService.self as AnyObject).responds(to: sel),
           let unmanaged = (NSSharingService.self as AnyObject).perform(sel, with: [image]),
           let services = unmanaged.takeUnretainedValue() as? [NSSharingService] {
            return services.filter { $0.canPerform(withItems: [image]) }
        }
        return []
    }

    private var headerRow: some View {
        HStack {
            HStack(spacing: 8) {
                if let secondary = secondaryColor {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [themeColor, secondary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 18, height: 18)
                }
                Text("SHARE CARD")
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .kerning(1.8)
                    .foregroundStyle(themeColor)
            }

            Spacer()

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary, .quaternary)
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
        }
    }

    private func quickActionButton(title: String, icon: String, accent: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Capsule().fill(accent))
            .shadow(color: accent.opacity(0.3), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        withAnimation(AppTheme.Animation.springSnappy) {
            showCopiedToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(AppTheme.Animation.springSnappy) {
                showCopiedToast = false
            }
        }
    }

    private func saveImageToFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.png]
        let sanitized = title.components(separatedBy: .alphanumerics.inverted).joined(separator: "_")
        panel.nameFieldStringValue = "\(sanitized)_Card.png"
        
        if panel.runModal() == .OK, let url = panel.url, let tiffData = image.tiffRepresentation, let imageRep = NSBitmapImageRep(data: tiffData), let pngData = imageRep.representation(using: .png, properties: [:]) {
            try? pngData.write(to: url)
            onDismiss()
        }
    }
}
