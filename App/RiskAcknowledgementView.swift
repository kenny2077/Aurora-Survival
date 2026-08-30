import SwiftUI

struct RiskAcknowledgementView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AuroraDesign.Space.lg) {
                Image(systemName: "mountain.2.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)

                Text("Before you use Aurora")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)

                Text("Aurora runs offline and can still be wrong. Its models may hallucinate, omit hazards, or produce unsafe instructions—even when an answer is labeled verified.")
                    .font(.title3)

                VStack(alignment: .leading, spacing: AuroraDesign.Space.md) {
                    acknowledgementRow(
                        icon: "person.crop.circle.badge.exclamationmark",
                        text: "Aurora is not professional medical, rescue, legal, mechanical, or navigation advice."
                    )
                    acknowledgementRow(
                        icon: "sos.circle.fill",
                        text: "For an emergency, contact local emergency services when possible and prioritize immediate observable danger."
                    )
                    acknowledgementRow(
                        icon: "checkmark.shield.fill",
                        text: "Reviewed sources support only attributed claims. Warnings identify sentences that could not be fully verified."
                    )
                    acknowledgementRow(
                        icon: "book.pages.fill",
                        text: "Some offline reference material was produced with AI assistance and developer review and may still contain errors."
                    )
                    acknowledgementRow(
                        icon: "person.fill.checkmark",
                        text: "You are responsible for judging conditions and deciding whether any action is appropriate."
                    )
                }

                Button {
                    model.acceptLegalTerms()
                } label: {
                    Text("I understand and accept")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("agreement.accept")

                Button("Not now") {}
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .accessibilityHint("Aurora remains on this screen")
                    .accessibilityIdentifier("agreement.notNow")

                Text("Acknowledgment version \(AppModel.legalSchemaVersion). A future material change will require acceptance again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(AuroraDesign.Space.xl)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .accessibilityIdentifier("agreement.screen")
    }

    private func acknowledgementRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: AuroraDesign.Space.sm) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
