import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct CustomShareMenuView: View {
    let image: NSImage
    let title: String
    let onDismiss: () -> Void

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
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.4), radius: 16, y: 8)

            // Primary Quick Actions Grid
            HStack(spacing: 12) {
                quickActionButton(
                    title: showCopiedToast ? "Copied!" : "Copy Image",
                    icon: showCopiedToast ? "checkmark" : "doc.on.doc",
                    accent: showCopiedToast ? .green : AppTheme.Colors.accent
                ) {
                    copyToClipboard()
                }

                quickActionButton(
                    title: "Save PNG...",
                    icon: "square.and.arrow.down",
                    accent: .blue
                ) {
                    saveImageToFile()
                }
            }

            Divider()
                .background(Color.white.opacity(0.12))

            Divider()
                .background(Color.white.opacity(0.12))

            // System Sharing Services
            VStack(alignment: .leading, spacing: 10) {
                Text("SHARE VIA")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .kerning(1.5)
                    .foregroundStyle(.white.opacity(0.4))

                let services = availableSharingServices
                if services.isEmpty {
                    Text("No sharing services available")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
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
                                                .fill(Color.white.opacity(0.12))
                                                .frame(width: 44, height: 44)

                                            Image(nsImage: service.image)
                                                .resizable()
                                                .aspectRatio(contentMode: .fit)
                                                .frame(width: 24, height: 24)
                                        }

                                        Text(service.title)
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(.white.opacity(0.85))
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
                    .fill(Color(white: 0.08).opacity(0.96))
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.6), radius: 30, y: 15)
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
            Text("SHARE CARD")
                .font(.system(size: 12, weight: .black, design: .monospaced))
                .kerning(1.8)
                .foregroundStyle(.white.opacity(0.85))

            Spacer()

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.4), .white.opacity(0.12))
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
