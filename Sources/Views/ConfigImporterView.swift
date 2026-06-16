import SwiftUI

/// View for importing channel configurations from CC Switch / Claude Desktop
struct ConfigImporterView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var channelStore: ChannelStore

    @State private var isScanning = false
    @State private var discoveredChannels: [ImportedChannel] = []
    @State private var importAlertMessage: String?
    @State private var showingImportSuccess = false
    @State private var importCount = 0

    @MainActor
    init(services: AppServices? = nil) {
        let services = services ?? .shared
        _channelStore = ObservedObject(wrappedValue: services.channelStore)
    }

    var body: some View {
        VStack(spacing: DesignToken.Spacing.lg) {
            // Header
            headerSection

            Divider()

            // Content
            if isScanning {
                scanningView
            } else if discoveredChannels.isEmpty {
                emptyView
            } else {
                channelListView
            }

            // Action buttons
            actionButtons
        }
        .padding(DesignToken.Layout.cardPadding)
        .frame(width: 500, height: 450)
        .task {
            // Auto-scan on first appear so the user sees results
            // immediately instead of being dropped into the "no
            // results" empty state. The user can still hit "Scan"
            // to refresh.
            if discoveredChannels.isEmpty && !isScanning {
                await scanConfigs()
            }
        }
        .alert(L10n.ConfigImporter.importComplete, isPresented: $showingImportSuccess) {
            Button(L10n.ConfigImporter.ok, role: .cancel) { dismiss() }
        } message: {
            Text(importAlertMessage ?? "")
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: DesignToken.Spacing.xs) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 32))
                .foregroundColor(DesignToken.Colors.accent)

            Text(L10n.ConfigImporter.title)
                .font(DesignToken.Font.h2())

            Text(L10n.ConfigImporter.subtitle)
                .font(DesignToken.Font.caption())
                .foregroundColor(DesignToken.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Scanning View

    private var scanningView: some View {
        VStack(spacing: DesignToken.Spacing.lg) {
            ProgressView()
                .scaleEffect(1.5)
            Text(L10n.ConfigImporter.scanning)
                .font(DesignToken.Font.body())
                .foregroundColor(DesignToken.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty View

    private var emptyView: some View {
        VStack(spacing: DesignToken.Spacing.sm) {
            Image(systemName: "folder")
                .font(.system(size: DesignToken.Layout.largeIconSize))
                .foregroundColor(DesignToken.Colors.textTertiary)

            Text(L10n.ConfigImporter.noResults)
                .font(DesignToken.Font.h3())
                .foregroundColor(DesignToken.Colors.textSecondary)

            Text(L10n.ConfigImporter.noResultsDescription)
                .font(DesignToken.Font.caption())
                .foregroundColor(DesignToken.Colors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Channel List

    private var channelListView: some View {
        VStack(spacing: DesignToken.Spacing.sm) {
            // Results header
            HStack {
                Text(L10n.ConfigImporter.foundChannels(discoveredChannels.count))
                    .font(DesignToken.Font.h3())

                Spacer()

                HStack(spacing: DesignToken.Spacing.xs) {
                    Button {
                        let allSelected = discoveredChannels.allSatisfy(\.isSelected)
                        for i in discoveredChannels.indices {
                            discoveredChannels[i].isSelected = !allSelected
                        }
                    } label: {
                        Text(discoveredChannels.allSatisfy(\.isSelected)
                             ? L10n.ConfigImporter.deselectAll
                             : L10n.ConfigImporter.selectAll)
                            .font(DesignToken.Font.caption())
                            .foregroundColor(DesignToken.Colors.accent)
                    }
                    .accessibilityIdentifier("configImporter.selectAllButton")
                }
            }
            .padding(.horizontal, DesignToken.Spacing.xs)

            // Scrollable list
            ScrollView {
                LazyVStack(spacing: DesignToken.Spacing.xs) {
                    ForEach(Array(discoveredChannels.enumerated()), id: \.element.id) { index, channel in
                        discoveredChannelRow(channel: channel, index: index)
                    }
                }
            }
        }
    }

    private func discoveredChannelRow(channel: ImportedChannel, index: Int) -> some View {
        HStack(spacing: DesignToken.Spacing.sm) {
            // Selection checkbox
            Toggle("", isOn: Binding(
                get: { discoveredChannels[index].isSelected },
                set: { discoveredChannels[index].isSelected = $0 }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)
            .accessibilityIdentifier("configImporter.row.toggle")

            // Provider icon
            Image(systemName: ProviderIconMapper.symbol(for: channel.source == "claude" ? "anthropic" : channel.name.lowercased()))
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(DesignToken.Colors.accent)
                .frame(width: 24)

            // Channel info
            VStack(alignment: .leading, spacing: 2) {
                Text(channel.name)
                    .font(DesignToken.Font.caption())
                    .foregroundColor(DesignToken.Colors.textPrimary)
                    .lineLimit(1)

                Text(channel.baseURL)
                    .font(DesignToken.Font.system(size: 10))
                    .foregroundColor(DesignToken.Colors.textTertiary)
                    .lineLimit(1)
            }

            Spacer()

            // Source badge
            Text(channel.source)
                .font(DesignToken.Font.system(size: 10, weight: .medium))
                .foregroundColor(DesignToken.Colors.textSecondary)
                .padding(.horizontal, DesignToken.Spacing.xs)
                .padding(.vertical, 2)
                .background(DesignToken.Colors.bgSecondary)
                .cornerRadius(4)

            // API key status
            Image(systemName: channel.apiKey.isEmpty ? "exclamationmark.triangle.fill" : "key.fill")
                .font(.system(size: 12))
                .foregroundColor(channel.apiKey.isEmpty ? DesignToken.Colors.statusOffline : DesignToken.Colors.statusOnline)
        }
        .padding(.horizontal, DesignToken.Spacing.sm)
        .padding(.vertical, DesignToken.Spacing.xs)
        .background(DesignToken.Colors.bgSecondary)
        .cornerRadius(8)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: DesignToken.Spacing.sm) {
            // Scan button must always be visible. The previous design
            // hid it when discoveredChannels was empty, which trapped
            // the user in the "no results" state with no way to scan
            // in the first place.
            SecondaryButton(L10n.ConfigImporter.scan, icon: "arrow.clockwise", isDisabled: isScanning) {
                Task { await scanConfigs() }
            }
            .accessibilityIdentifier("configImporter.scanButton")

            Spacer()

            SecondaryButton(L10n.Onboarding.cancel) {
                dismiss()
            }
            .accessibilityIdentifier("configImporter.cancelButton")

            let hasSelection = discoveredChannels.contains { $0.isSelected }
            PrimaryButton(L10n.ConfigImporter.importSelected, icon: "square.and.arrow.down", isDisabled: isScanning || !hasSelection) {
                Task { await importSelected() }
            }
            .accessibilityIdentifier("configImporter.importButton")
        }
    }

    // MARK: - Actions

    @MainActor
    private func scanConfigs() async {
        isScanning = true

        // Simulate some async work
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s delay

        discoveredChannels = await ConfigImporter.scanAll()
        isScanning = false
    }

    @MainActor
    private func importSelected() async {
        let selected = discoveredChannels.filter(\.isSelected)
        guard !selected.isEmpty else { return }

        let count: Int
        do {
            count = try ConfigImporter.import(channels: selected)
        } catch {
            importAlertMessage = error.localizedDescription
            showingImportSuccess = true
            return
        }
        importCount = count
        importAlertMessage = L10n.ConfigImporter.importSuccess(count)
        showingImportSuccess = true
    }
}
