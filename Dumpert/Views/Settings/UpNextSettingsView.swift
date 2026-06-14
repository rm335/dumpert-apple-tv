import SwiftUI

struct UpNextSettingsView: View {
    @Environment(VideoRepository.self) private var repository
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var settings = repository.settings

        List {
            Section {
                Toggle(isOn: $settings.upNextOverlayEnabled) {
                    Label {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Overlay tonen", comment: "Up next setting: show overlay toggle")
                            Text("Toon een aftelling met de volgende video", comment: "Up next setting: show overlay description")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.leading, 12)
                    } icon: {
                        Image(systemName: settings.upNextOverlayEnabled ? "rectangle.inset.filled" : "rectangle")
                            .foregroundStyle(settings.upNextOverlayEnabled ? .dumpiGreen : .secondary)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
            } footer: {
                if !settings.upNextOverlayEnabled {
                    Text("De volgende video start direct zonder aftelling.", comment: "Up next setting: overlay disabled explanation")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if settings.upNextOverlayEnabled {
                Section {
                    NavigationLink {
                        SettingsPickerDestination(
                            title: "Aftelling",
                            selection: $settings.upNextCountdownSeconds,
                            options: [
                                ("3 seconden", 3),
                                ("5 seconden", 5),
                                ("10 seconden", 10),
                            ]
                        )
                    } label: {
                        HStack {
                            Label {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Aftelling", comment: "Up next setting: countdown label")
                                    Text("Aantal seconden voordat de volgende video start", comment: "Up next setting: countdown description")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.leading, 12)
                            } icon: {
                                Image(systemName: "timer")
                            }
                            Spacer()
                            Text("\(settings.upNextCountdownSeconds) seconden", comment: "Up next setting: countdown seconds value")
                                .foregroundStyle(.secondary)
                                .font(.callout)
                        }
                    }

                    NavigationLink {
                        SettingsPickerDestination(
                            title: "Minimale videolengte",
                            selection: $settings.upNextMinimumVideoSeconds,
                            options: [
                                ("Geen minimum", 0),
                                ("30 seconden", 30),
                                ("1 minuut", 60),
                                ("2 minuten", 120),
                                ("5 minuten", 300),
                            ]
                        )
                    } label: {
                        HStack {
                            Label {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Minimale videolengte", comment: "Up next setting: minimum video length label")
                                    Text("Toon de overlay alleen bij langere video's", comment: "Up next setting: minimum video length description")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.leading, 12)
                            } icon: {
                                Image(systemName: "film")
                            }
                            Spacer()
                            Text(minimumVideoLengthLabel(settings.upNextMinimumVideoSeconds))
                                .foregroundStyle(.secondary)
                                .font(.callout)
                        }
                    }
                }
            }
        }
        .navigationTitle(Text("Volgende video", comment: "Up next settings screen title"))
        .animation(reduceMotion ? nil : .smooth, value: settings.upNextOverlayEnabled)
    }

    private func minimumVideoLengthLabel(_ seconds: Int) -> LocalizedStringKey {
        switch seconds {
        case 0: "Geen minimum"
        case 30: "30 seconden"
        case 60: "1 minuut"
        case 120: "2 minuten"
        case 300: "5 minuten"
        default: "\(seconds)s"
        }
    }
}
