import SwiftUI

/// The provider switcher at the top of the popover: brand icon + name per tab, with a
/// thin brand-colored underline showing REMAINING quota (full bar = untouched quota).
/// The underline is hidden on the selected tab, whose content is shown below.
struct ProviderTabStrip: View {
    @EnvironmentObject var store: UsageStore

    var body: some View {
        HStack(spacing: 6) {
            ForEach(store.enabledProviders) { provider in
                tab(for: provider)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func tab(for provider: Provider) -> some View {
        let isSelected = store.selectedProvider == provider

        Button {
            store.selectedProvider = provider
        } label: {
            VStack(spacing: 4) {
                iconView(for: provider, selected: isSelected)
                Text(provider.displayName)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .white : .primary)
                underline(for: provider, hidden: isSelected)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help("\(provider.displayName) usage")
    }

    @ViewBuilder
    private func iconView(for provider: Provider, selected: Bool) -> some View {
        if let image = ProviderBrandIcon.image(for: provider) {
            Image(nsImage: image)
                .renderingMode(.template)
                .foregroundColor(selected ? .white : .primary)
        } else {
            Image(systemName: "app.dashed")
                .font(.system(size: 13))
                .foregroundColor(selected ? .white : .primary)
        }
    }

    @ViewBuilder
    private func underline(for provider: Provider, hidden: Bool) -> some View {
        let remaining = store.state(for: provider).snapshot?.primary?.remainingPercent

        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(NSColor.tertiaryLabelColor).opacity(0.25))
                if let remaining {
                    Capsule()
                        .fill(provider.brandColor)
                        .frame(width: geo.size.width * CGFloat(remaining / 100.0))
                }
            }
        }
        .frame(height: 3)
        .padding(.horizontal, 4)
        .opacity(hidden ? 0 : 1)
    }
}

#if DEBUG
#Preview("Tab Strip") {
    ProviderTabStrip()
        .environmentObject(UsageStore.preview)
        .frame(width: 300)
}
#endif
