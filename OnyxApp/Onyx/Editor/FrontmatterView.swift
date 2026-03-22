import SwiftUI

struct FrontmatterView: View {
    @Binding var metadata: DocumentMetadata
    @State private var isCollapsed = false
    @State private var newPropertyKey = ""
    @State private var isAddingProperty = false

    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let reservedKeys: Set<String> = ["id", "created", "updated", "tags"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button {
                withAnimation(OnyxTheme.Animation.quick) {
                    isCollapsed.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Properties")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(OnyxTheme.Colors.textTertiary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(OnyxTheme.Colors.textTertiary)
                        .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !isCollapsed {
                Divider()
                    .background(Color.white.opacity(0.08))

                // System properties
                PropertyRow(icon: "calendar", key: "updated", value: formatDate(metadata.updated), isReadOnly: true)

                // Tags
                TagsRow(tags: $metadata.tags)

                // Custom properties
                ForEach(metadata.customProperties.keys.sorted(), id: \.self) { key in
                    CustomPropertyRow(
                        key: key,
                        value: Binding(
                            get: { metadata.customProperties[key] ?? "" },
                            set: { metadata.customProperties[key] = $0 }
                        ),
                        onDelete: {
                            metadata.customProperties.removeValue(forKey: key)
                        }
                    )
                }

                // Add property
                if isAddingProperty {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 12))
                            .foregroundStyle(OnyxTheme.Colors.textTertiary)
                            .frame(width: 16)
                        TextField("Property name", text: $newPropertyKey)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .foregroundStyle(OnyxTheme.Colors.textPrimary)
                            .onSubmit { commitNewProperty() }
                            .onExitCommand { isAddingProperty = false; newPropertyKey = "" }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 5)
                } else {
                    Button {
                        isAddingProperty = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .medium))
                            Text("Add property")
                                .font(.system(size: 13))
                        }
                        .foregroundStyle(OnyxTheme.Colors.textTertiary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 5)
                    }
                    .buttonStyle(.plain)
                }

                Divider()
                    .background(Color.white.opacity(0.08))
            }
        }
        .padding(.horizontal, 64)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func commitNewProperty() {
        let key = newPropertyKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty,
              !Self.reservedKeys.contains(key),
              metadata.customProperties[key] == nil else {
            isAddingProperty = false
            newPropertyKey = ""
            return
        }
        metadata.customProperties[key] = ""
        newPropertyKey = ""
        isAddingProperty = false
    }
}

// MARK: - Property Row

private struct PropertyRow: View {
    let icon: String
    let key: String
    let value: String
    var isReadOnly: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(OnyxTheme.Colors.textTertiary)
                .frame(width: 16)

            Text(key)
                .font(.system(size: 13))
                .foregroundStyle(OnyxTheme.Colors.textTertiary)
                .frame(width: 80, alignment: .leading)

            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(isReadOnly ? OnyxTheme.Colors.textTertiary : OnyxTheme.Colors.textPrimary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 5)
    }
}

// MARK: - Custom Property Row

private struct CustomPropertyRow: View {
    let key: String
    @Binding var value: String
    let onDelete: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.alignleft")
                .font(.system(size: 12))
                .foregroundStyle(OnyxTheme.Colors.textTertiary)
                .frame(width: 16)

            Text(key)
                .font(.system(size: 13))
                .foregroundStyle(OnyxTheme.Colors.textTertiary)
                .frame(width: 80, alignment: .leading)

            TextField("Empty", text: $value)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(OnyxTheme.Colors.textPrimary)

            Spacer()

            if isHovered {
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(OnyxTheme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 5)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Tags Row

private struct TagsRow: View {
    @Binding var tags: [String]
    @State private var newTag = ""
    @State private var isAddingTag = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "tag")
                .font(.system(size: 12))
                .foregroundStyle(OnyxTheme.Colors.textTertiary)
                .frame(width: 16)

            Text("tags")
                .font(.system(size: 13))
                .foregroundStyle(OnyxTheme.Colors.textTertiary)
                .frame(width: 80, alignment: .leading)

            FlowLayout(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    TagChip(tag: tag) {
                        tags.removeAll { $0 == tag }
                    }
                }

                if isAddingTag {
                    TextField("tag", text: $newTag)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(OnyxTheme.Colors.textPrimary)
                        .frame(width: 80)
                        .onSubmit { commitTag() }
                        .onExitCommand { isAddingTag = false; newTag = "" }
                } else {
                    Button {
                        isAddingTag = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(OnyxTheme.Colors.textTertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: OnyxTheme.Radius.sm)
                                    .fill(Color.white.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 5)
    }

    private func commitTag() {
        let tag = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tag.isEmpty && !tags.contains(tag) {
            tags.append(tag)
        }
        newTag = ""
        isAddingTag = false
    }
}

// MARK: - Tag Chip

private struct TagChip: View {
    let tag: String
    let onRemove: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 4) {
            Text(tag)
                .font(.system(size: 12))
                .foregroundStyle(OnyxTheme.Colors.accent)

            if isHovered {
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(OnyxTheme.Colors.accent)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: OnyxTheme.Radius.sm)
                .fill(OnyxTheme.Colors.accentSubtle)
        )
        .onHover { isHovered = $0 }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        for (index, offset) in result.offsets.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + offset.x, y: bounds.minY + offset.y), proposal: .unspecified)
        }
    }

    private struct LayoutResult {
        var offsets: [CGPoint]
        var size: CGSize
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> LayoutResult {
        let maxWidth = proposal.width ?? .infinity
        var offsets: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            offsets.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            totalWidth = max(totalWidth, currentX - spacing)
        }

        return LayoutResult(
            offsets: offsets,
            size: CGSize(width: totalWidth, height: currentY + lineHeight)
        )
    }
}
