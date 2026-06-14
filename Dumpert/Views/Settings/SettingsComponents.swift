import SwiftUI

extension SettingsView {
    func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .padding(.vertical, 24)
    }

    func settingsLabel(_ title: LocalizedStringKey, icon: String, description: LocalizedStringKey) -> some View {
        HStack(alignment: .center, spacing: 28) {
            Image(systemName: icon)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                Text(description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    func destructiveLabel(_ title: LocalizedStringKey, icon: String, description: LocalizedStringKey) -> some View {
        HStack(alignment: .center, spacing: 28) {
            Image(systemName: icon)
                .foregroundStyle(Color.dumpiError.opacity(0.8))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .foregroundStyle(Color.dumpiError)
                Text(description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityHint(Text("Vraagt om bevestiging voordat actie wordt uitgevoerd", comment: "Accessibility hint for destructive Settings actions that show a confirmation dialog"))
    }

    func settingsToggle(_ title: LocalizedStringKey, icon: String, description: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(alignment: .center, spacing: 28) {
                Image(systemName: isOn.wrappedValue ? "\(icon).fill" : icon)
                    .foregroundStyle(isOn.wrappedValue ? .dumpiGreen : .secondary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                    Text(description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    func settingsNavigationPicker<V: Hashable>(
        _ title: LocalizedStringKey,
        icon: String,
        description: LocalizedStringKey,
        selection: Binding<V>,
        options: [(LocalizedStringKey, V)]
    ) -> some View {
        let currentLabel = options.first(where: { $0.1 == selection.wrappedValue })?.0 ?? ""
        return NavigationLink {
            SettingsPickerDestination(
                title: title,
                selection: selection,
                options: options
            )
        } label: {
            HStack {
                settingsLabel(title, icon: icon, description: description)
                Spacer()
                Text(currentLabel)
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
        .accessibilityValue(Text(currentLabel))
    }

    func infoRow(_ title: LocalizedStringKey, icon: String, value: LocalizedStringKey) -> some View {
        HStack(spacing: 28) {
            Image(systemName: icon)
                .frame(width: 28)
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .font(.callout)
        }
    }

    func tilePreview(columnCount: Int, tileSize: TileSize) -> some View {
        HStack(spacing: 12) {
            ForEach(0..<columnCount, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 8)
                    .fill(.secondary.opacity(0.15))
                    .aspectRatio(16 / 9, contentMode: .fit)
            }
        }
        .frame(maxHeight: 100)
        .padding(.vertical, 12)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: tileSize)
        .listRowBackground(Color.clear)
        .accessibilityLabel(Text("Voorbeeld: \(columnCount) kolommen", comment: "Accessibility: tile preview with column count"))
    }

    static let appVersion: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }()
}
