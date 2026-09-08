import SwiftUI

struct OnboardingView: View {
    private enum Page: Int, CaseIterable {
        case introduction
        case features
        case models
    }

    private enum NavigationDirection {
        case forward
        case backward
    }

    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var page: Page = .introduction
    @State private var navigationDirection: NavigationDirection = .forward
    @State private var isTransitioning = false
    private let galleryWidth: CGFloat = 580

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                AuroraDesign.aurora(colorScheme: colorScheme)
                    .opacity(0.09)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    pageIndicator

                    GeometryReader { geometry in
                        ScrollViewReader { proxy in
                            ScrollView {
                                VStack(spacing: 0) {
                                    Color.clear
                                        .frame(height: 1)
                                        .id("onboarding.page.top")
                                    pageContent
                                        .id(page)
                                        .transition(pageTransition)
                                        .padding(
                                            .bottom,
                                            page == .introduction
                                                ? AuroraDesign.Space.xl * 2
                                                : 0
                                        )
                                }
                                .padding(AuroraDesign.Space.xl)
                                .frame(maxWidth: galleryWidth)
                                .frame(
                                    maxWidth: .infinity,
                                    minHeight: geometry.size.height,
                                    alignment: page == .introduction
                                        ? .center
                                        : .top
                                )
                            }
                            .onChange(of: page) { _, _ in
                                proxy.scrollTo("onboarding.page.top", anchor: .top)
                            }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                navigationBar
            }
            .task { await model.ensureCatalogLoaded() }
        }
        .accessibilityIdentifier("onboarding.screen")
    }

    @ViewBuilder
    private var pageContent: some View {
        switch page {
        case .introduction:
            introductionPage
        case .features:
            featuresPage
        case .models:
            modelsPage
        }
    }

    private var introductionPage: some View {
        VStack(spacing: AuroraDesign.Space.xl) {
            AuroraAppIcon()

            VStack(spacing: AuroraDesign.Space.xs) {
                Text("Meet Aurora")
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text("Offline AI help for the outdoors.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var featuresPage: some View {
        VStack(spacing: AuroraDesign.Space.xl) {
            onboardingTitle(
                "Ready when the network isn’t",
                subtitle: nil
            )

            VStack(spacing: 0) {
                featureRow(
                    symbol: "wifi.slash",
                    title: "Works offline",
                    detail: "Once downloaded, Aurora runs without a connection."
                )
                Divider().padding(.leading, 58)
                featureRow(
                    symbol: "book.pages.fill",
                    title: "Source-backed",
                    detail: "When the manual informs an answer, Aurora shows where it came from."
                )
                Divider().padding(.leading, 58)
                featureRow(
                    symbol: "hand.raised.fill",
                    title: "Private by design",
                    detail: "Your questions and selected photos are processed locally."
                )
            }
            .onboardingGlassCard()
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .accessibilityIdentifier("onboarding.features")
    }

    private var modelsPage: some View {
        VStack(spacing: AuroraDesign.Space.xl) {
            onboardingTitle(
                "Choose what to take offline",
                subtitle: nil
            )

            VStack(spacing: 0) {
                modelSummary(
                    symbol: "text.bubble.fill",
                    title: "Aurora Lite",
                    detail: "Fast text guidance for iPhone and iPad.",
                    byteCount: estimatedBytes(for: .lite),
                    tier: .lite
                )
                Divider().padding(.leading, 58)
                modelSummary(
                    symbol: "eye.fill",
                    title: "Aurora Expert",
                    detail: model.expertDeviceIsEligible
                        ? "Text and photo guidance on supported devices."
                        : "Requires a supported high-memory device.",
                    byteCount: estimatedBytes(for: .expert),
                    tier: .expert
                )
            }
            .onboardingGlassCard()
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var pageIndicator: some View {
        HStack(spacing: AuroraDesign.Space.xs) {
            ForEach(Page.allCases, id: \.rawValue) { item in
                Capsule()
                    .fill(
                        item == page
                            ? AuroraDesign.ordinaryAccent(
                                light: AuroraDesign.river,
                                colorScheme: colorScheme
                            )
                            : .secondary.opacity(0.28)
                    )
                    .frame(width: item == page ? 24 : 8, height: 8)
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: page)
        .padding(.top, AuroraDesign.Space.lg)
        .padding(.bottom, AuroraDesign.Space.sm)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(page.rawValue + 1) of \(Page.allCases.count)")
        .accessibilityIdentifier("onboarding.pageIndicator")
    }

    @ViewBuilder
    private var navigationBar: some View {
        VStack(spacing: AuroraDesign.Space.sm) {
            if page == .introduction {
                Button {
                    model.acceptLegalTerms()
                    move(by: 1)
                } label: {
                    Text("Agree & Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.glassProminent)
                .accessibilityIdentifier("onboarding.accept")

                NavigationLink {
                    LegalPrivacyHubView()
                } label: {
                    Text("Review Terms, AI limitations, and Privacy before continuing.")
                        .font(.footnote.weight(.semibold))
                        .multilineTextAlignment(.center)
                }
                .accessibilityIdentifier("onboarding.legal")
            } else if page == .features {
                HStack(spacing: AuroraDesign.Space.md) {
                    Button { move(by: -1) } label: {
                        Text("Back")
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                        .buttonStyle(.glassProminent)
                        .frame(maxWidth: .infinity)

                    Button { move(by: 1) } label: {
                        Text("Continue")
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                        .buttonStyle(.glassProminent)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("onboarding.continue")
                }
            } else {
                Button("Set Up Later") {
                    model.completeOnboarding(openModels: false)
                }
                .buttonStyle(.glassProminent)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("onboarding.skipModels")
            }
        }
        .disabled(isTransitioning)
        .frame(maxWidth: galleryWidth)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, AuroraDesign.Space.lg)
        .padding(.top, AuroraDesign.Space.md)
    }

    private func onboardingTitle(_ title: String, subtitle: String?) -> some View {
        VStack(spacing: AuroraDesign.Space.xs) {
            Text(title)
                .font(.title.bold())
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func featureRow(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: AuroraDesign.Space.md) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(
                    AuroraDesign.aurora(colorScheme: colorScheme)
                )
                .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: AuroraDesign.Space.xs) {
                Text(title).font(.headline)
                Text(detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, AuroraDesign.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func modelSummary(
        symbol: String,
        title: String,
        detail: String,
        byteCount: Int64,
        tier: ModelTier
    ) -> some View {
        if horizontalSizeClass == .compact || dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: AuroraDesign.Space.md) {
                modelIdentity(
                    symbol: symbol,
                    title: title,
                    detail: detail,
                    byteCount: byteCount
                )
                modelDownloadButton(tier, fillsWidth: true)
            }
            .padding(.vertical, AuroraDesign.Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .center, spacing: AuroraDesign.Space.md) {
                modelIdentity(
                    symbol: symbol,
                    title: title,
                    detail: detail,
                    byteCount: byteCount
                )
                Spacer(minLength: AuroraDesign.Space.md)
                modelDownloadButton(tier, fillsWidth: false)
            }
            .padding(.vertical, AuroraDesign.Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func modelIdentity(
        symbol: String,
        title: String,
        detail: String,
        byteCount: Int64
    ) -> some View {
        HStack(alignment: .top, spacing: AuroraDesign.Space.md) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(
                    AuroraDesign.aurora(colorScheme: colorScheme)
                )
                .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: AuroraDesign.Space.xs) {
                Text(title).font(.headline)
                Text(detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func modelDownloadButton(
        _ tier: ModelTier,
        fillsWidth: Bool
    ) -> some View {
        Button {
            model.startModelSetup(tier)
            model.completeOnboarding(openModels: true)
        } label: {
            Label("Download", systemImage: "arrow.down")
                .frame(maxWidth: fillsWidth ? .infinity : nil)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.small)
        .disabled(
            model.modelEntry(for: tier) == nil
                || (tier == .expert && !model.expertDeviceIsEligible)
        )
        .accessibilityLabel("Download Aurora \(tier.displayName)")
        .accessibilityIdentifier("onboarding.download.\(tier.rawValue)")
    }

    private func estimatedBytes(for tier: ModelTier) -> Int64 {
        let catalogBytes = model.modelSetupByteCount(for: tier)
        if catalogBytes > 0 { return catalogBytes }
        switch tier {
        case .lite: return 849_224_149
        case .expert: return 1_632_306_641
        }
    }

    private func move(by offset: Int) {
        guard !isTransitioning,
              let next = Page(rawValue: page.rawValue + offset)
        else { return }

        navigationDirection = offset > 0 ? .forward : .backward
        isTransitioning = true
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.2)) { page = next }
        } else {
            withAnimation(.smooth(duration: 0.4)) { page = next }
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            isTransitioning = false
        }
    }

    private var pageTransition: AnyTransition {
        if reduceMotion { return .opacity }
        let insertion: Edge = navigationDirection == .forward ? .trailing : .leading
        let removal: Edge = navigationDirection == .forward ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: insertion).combined(with: .opacity),
            removal: .move(edge: removal).combined(with: .opacity)
        )
    }
}

private struct AuroraAppIcon: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Image("AuroraBrandIcon")
                .resizable()
                .scaledToFit()
                .accessibilityHidden(true)
        }
            .frame(width: iconSize, height: iconSize)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: iconSize * 0.225,
                    style: .continuous
                )
            )
            .shadow(
                color: AuroraDesign.ordinaryAccent(
                    light: AuroraDesign.river,
                    colorScheme: colorScheme
                ).opacity(0.22),
                radius: 22,
                y: 12
            )
    }

    private var iconSize: CGFloat { horizontalSizeClass == .regular ? 112 : 92 }
}

struct BundledLegalTextView: View {
    let title: String
    let resource: String
    var fileExtension = "md"

    private var text: String {
        guard let url = Bundle.main.url(forResource: resource, withExtension: fileExtension),
              let value = try? String(contentsOf: url, encoding: .utf8)
        else { return "This legal document is unavailable in this build." }
        return value
    }

    var body: some View {
        ScrollView {
            Text(LocalizedStringKey(text))
                .frame(maxWidth: AuroraDesign.readableWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(AuroraDesign.Space.lg)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension View {
    func onboardingGlassCard() -> some View {
        padding(AuroraDesign.Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(
                .regular,
                in: RoundedRectangle(
                    cornerRadius: AuroraDesign.Radius.prominent,
                    style: .continuous
                )
            )
    }
}
