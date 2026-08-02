import SwiftUI

struct GuideLibraryView: View {
    @EnvironmentObject private var model: AppModel

    private var searchResults: [KnowledgeArticle] {
        model.filteredArticles
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                manualHeader

                if model.libraryQuery.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty {
                    Text("Chapters")
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)

                    ForEach(GuideChapter.allCases) { chapter in
                        let articles = model.articles.filter(chapter.includes)
                        if !articles.isEmpty {
                            NavigationLink {
                                GuideChapterView(
                                    chapter: chapter,
                                    articles: articles
                                )
                            } label: {
                                ChapterRow(
                                    chapter: chapter,
                                    articleCount: articles.count
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    searchSection
                }
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Field Manual")
        .searchable(
            text: $model.libraryQuery,
            prompt: "Search chapters and guidance"
        )
        .overlay {
            if model.articles.isEmpty {
                ContentUnavailableView(
                    "Manual unavailable",
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text(
                        "Reinstall the starter manual before travelling."
                    )
                )
            }
        }
    }

    private var manualHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Image(systemName: "book.closed.fill")
                    .font(.title)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Spacer()
                Label("Available offline", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }

            Text("TrailGuard Survival Manual")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text(
                "Practical, reviewed guidance for the decisions that matter first. The chatbot retrieves from this same manual."
            )
            .font(.body)
            .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Label(
                    "\(GuideChapter.availableCount(in: model.articles)) chapters",
                    systemImage: "books.vertical"
                )
                Label(
                    "\(model.articles.count) topics",
                    systemImage: "text.book.closed"
                )
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var searchSection: some View {
        Text("Search results")
            .font(.title2.bold())
            .accessibilityAddTraits(.isHeader)

        if searchResults.isEmpty {
            ContentUnavailableView.search(text: model.libraryQuery)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        } else {
            ForEach(searchResults) { article in
                NavigationLink {
                    ArticleView(article: article)
                } label: {
                    ArticleRow(article: article)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private enum GuideChapter: Int, CaseIterable, Identifiable {
    case water = 1
    case fireWarmth
    case shelterWeather
    case food
    case navigation
    case signaling
    case firstAid
    case vehicle

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .water: return "Water"
        case .fireWarmth: return "Fire & Warmth"
        case .shelterWeather: return "Shelter & Weather"
        case .food: return "Food & Wildlife"
        case .navigation: return "Navigation"
        case .signaling: return "Signaling & Rescue"
        case .firstAid: return "First Aid"
        case .vehicle: return "Vehicle Survival"
        }
    }

    var subtitle: String {
        switch self {
        case .water:
            return "Choose, treat, and protect a safer supply."
        case .fireWarmth:
            return "Control fire and prevent dangerous heat loss."
        case .shelterWeather:
            return "Reduce exposure without adding new hazards."
        case .food:
            return "Protect carried food and avoid unsafe foraging."
        case .navigation:
            return "Stop, orient, and avoid expanding the search area."
        case .signaling:
            return "Call early and make your position easier to find."
        case .firstAid:
            return "Layperson actions while qualified help is arranged."
        case .vehicle:
            return "Protect people first during roadside incidents."
        }
    }

    var symbol: String {
        switch self {
        case .water: return "drop.fill"
        case .fireWarmth: return "flame.fill"
        case .shelterWeather: return "tent.fill"
        case .food: return "takeoutbag.and.cup.and.straw.fill"
        case .navigation: return "safari.fill"
        case .signaling: return "antenna.radiowaves.left.and.right"
        case .firstAid: return "cross.case.fill"
        case .vehicle: return "car.fill"
        }
    }

    func includes(_ article: KnowledgeArticle) -> Bool {
        switch self {
        case .water:
            return article.id == "wilderness-water-001"
        case .fireWarmth:
            return article.id == "wilderness-fire-001"
                || article.id == "wilderness-cold-001"
        case .shelterWeather:
            return [
                "wilderness-shelter-001",
                "wilderness-lightning-001",
                "wilderness-heat-001",
            ].contains(article.id)
        case .food:
            return article.id == "wilderness-food-storage-001"
        case .navigation:
            return article.id == "wilderness-lost-001"
        case .signaling:
            return article.id == "navigation-signaling-001"
        case .firstAid:
            return article.id.hasPrefix("firstaid-")
        case .vehicle:
            return article.domain == .vehicle
        }
    }

    static func availableCount(in articles: [KnowledgeArticle]) -> Int {
        allCases.filter { chapter in
            articles.contains(where: chapter.includes)
        }.count
    }
}

private struct ChapterRow: View {
    let chapter: GuideChapter
    let articleCount: Int

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.tint.opacity(0.12))
                Image(systemName: chapter.symbol)
                    .font(.title2)
                    .foregroundStyle(.tint)
            }
            .frame(width: 52, height: 52)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("CHAPTER \(chapter.rawValue)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(chapter.title)
                    .font(.headline)
                Text(chapter.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 6) {
                Text("\(articleCount)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Chapter \(chapter.rawValue), \(chapter.title), \(articleCount) topics"
        )
    }
}

private struct GuideChapterView: View {
    let chapter: GuideChapter
    let articles: [KnowledgeArticle]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: chapter.symbol)
                        .font(.largeTitle)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text("Chapter \(chapter.rawValue)")
                        .font(.caption.weight(.bold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                    Text(chapter.title)
                        .font(.largeTitle.bold())
                    Text(chapter.subtitle)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)

                ForEach(articles) { article in
                    NavigationLink {
                        ArticleView(article: article)
                    } label: {
                        ArticleRow(article: article)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(chapter.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ArticleRow: View {
    let article: KnowledgeArticle

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(article.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(article.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                Label(
                    article.source.organization,
                    systemImage: "checkmark.seal"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}

private struct ArticleView: View {
    let article: KnowledgeArticle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(article.domain.displayName.uppercased())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tint)
                    Text(article.title)
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text(article.summary)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                if !article.warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Read this first", systemImage: "exclamationmark.triangle.fill")
                            .font(.headline)
                            .foregroundStyle(.orange)
                        ForEach(article.warnings, id: \.self) { warning in
                            Text("• \(warning)")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(16)
                    .background(
                        Color.orange.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 18)
                    )
                }

                if !article.steps.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Reviewed procedure")
                            .font(.title2.bold())
                            .accessibilityAddTraits(.isHeader)
                        ForEach(
                            Array(article.steps.enumerated()),
                            id: \.offset
                        ) { index, step in
                            HStack(alignment: .top, spacing: 14) {
                                Text("\(index + 1)")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                                    .frame(width: 28, height: 28)
                                    .background(.tint, in: Circle())
                                    .accessibilityHidden(true)
                                Text(step)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Step \(index + 1). \(step)")
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Label("Source record", systemImage: "doc.text.magnifyingglass")
                        .font(.headline)
                    Text(article.source.title)
                        .font(.subheadline.weight(.semibold))
                    Text(article.source.organization)
                        .font(.subheadline)
                    Text(article.source.revision)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let url = article.source.url,
                       let host = URL(string: url)?.host {
                        Text(host)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Text(
                        "TrailGuard stores an offline reviewed synthesis. Check current local rules and professional guidance when a connection is available."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 18))
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
    }
}
