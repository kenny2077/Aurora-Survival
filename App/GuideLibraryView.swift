import SwiftUI

struct GuideLibraryView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            ForEach(KnowledgeDomain.allCases, id: \.self) { domain in
                let articles = model.filteredArticles.filter { $0.domain == domain }
                if !articles.isEmpty {
                    Section(domain.displayName) {
                        ForEach(articles) { article in
                            NavigationLink {
                                ArticleView(article: article)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(article.title)
                                    Text(article.summary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Offline Guide")
        .searchable(text: $model.libraryQuery, prompt: "Search downloaded guidance")
        .overlay {
            if model.articles.isEmpty {
                ContentUnavailableView(
                    "Knowledge unavailable",
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text("Reinstall the starter knowledge pack before travelling.")
                )
            }
        }
    }
}

private struct ArticleView: View {
    let article: KnowledgeArticle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(article.summary)
                    .font(.headline)

                if !article.warnings.isEmpty {
                    GroupBox("Warnings") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(article.warnings, id: \.self) {
                                Label($0, systemImage: "exclamationmark.triangle.fill")
                            }
                        }
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if !article.steps.isEmpty {
                    Text("Steps").font(.title3.bold())
                    ForEach(Array(article.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background(Color.accentColor, in: Circle())
                            Text(step)
                        }
                    }
                }

                Divider()
                Text("Source")
                    .font(.caption.bold())
                Text("\(article.source.title) — \(article.source.organization)")
                    .font(.caption)
                Text("Pack revision \(article.source.revision)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle(article.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
