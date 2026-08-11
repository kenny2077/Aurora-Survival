import SwiftUI

struct GuideLibraryView: View {
    @EnvironmentObject private var model: AppModel

    private var isSearching: Bool {
        !model.libraryQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                if isSearching {
                    searchResults
                } else {
                    manualHeader
                    if model.survivalKnowledge == nil {
                        fallbackNotice
                    }
                    chapterLibrary
                }
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Field Manual")
        .searchable(text: $model.libraryQuery, prompt: "What do you need to do?")
        .navigationDestination(for: ManualRoute.self) { route in
            switch route {
            case .chapter(let id):
                if let chapter = model.manualChapter(id: id) {
                    ManualChapterView(chapter: chapter)
                } else {
                    ManualUnavailableView(message: "This chapter could not be loaded.")
                }
            case .lesson(let id):
                if let lesson = model.manualLesson(id: id) {
                    ManualLessonView(lesson: lesson)
                } else {
                    ManualUnavailableView(message: "This lesson could not be loaded.")
                }
            case .reference(let reference):
                DetailedManualSectionView(reference: reference)
            }
        }
        .overlay {
            if model.manualCourseChapters.isEmpty {
                ContentUnavailableView(
                    "Manual unavailable",
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text("Reinstall the bundled manual before travelling.")
                )
            }
        }
        .accessibilityIdentifier("manual.home")
    }

    private var manualHeader: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                Image(systemName: "mountain.2.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityHidden(true)
                Spacer()
                Label("Works offline", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.16), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Wilderness Survival")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)
                Text("Choose the problem. Follow the actions. Stay alive until help arrives.")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [.manualForest, .manualForest.opacity(0.72), .manualWater.opacity(0.64)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28)
        )
        .accessibilityElement(children: .contain)
    }

    private var fallbackNotice: some View {
        Label(
            "Emergency basics are available. Deep reference search needs the full manual database.",
            systemImage: "exclamationmark.triangle.fill"
        )
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.orange)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityIdentifier("manual.fallback.notice")
    }

    private var chapterLibrary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Chapters")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            ForEach(model.manualCourseChapters) { chapter in
                NavigationLink(value: ManualRoute.chapter(chapter.id)) {
                    ManualChapterCard(chapter: chapter)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        let lessons = model.manualLessonSearchResults
        let references = model.manualSearchResults

        if lessons.isEmpty && references.isEmpty {
            ContentUnavailableView.search(text: model.libraryQuery)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 56)
                .accessibilityIdentifier("manual.search.no-results")
        } else {
            if !lessons.isEmpty {
                SearchGroupHeading(title: "Core lessons", count: lessons.count)
                ForEach(lessons) { lesson in
                    NavigationLink(value: ManualRoute.lesson(lesson.id)) {
                        ManualLessonRow(lesson: lesson)
                    }
                    .buttonStyle(.plain)
                }
            }

            if !references.isEmpty {
                SearchGroupHeading(title: "Deep reference", count: references.count)
                    .padding(.top, lessons.isEmpty ? 0 : 8)
                ForEach(references) { section in
                    NavigationLink(value: ManualRoute.reference(section.manualReference)) {
                        ReferenceSectionRow(section: section)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct ManualChapterView: View {
    @EnvironmentObject private var model: AppModel
    let chapter: ManualCourseChapter

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                ManualChapterHero(chapter: chapter)

                VStack(alignment: .leading, spacing: 12) {
                    Text("60-second lessons")
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                    ForEach(model.manualLessons(for: chapter)) { lesson in
                        NavigationLink(value: ManualRoute.lesson(lesson.id)) {
                            ManualLessonRow(lesson: lesson)
                        }
                        .buttonStyle(.plain)
                    }
                }

                let sections = model.manualSections(for: chapter)
                if !sections.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Deep reference")
                            .font(.title2.bold())
                            .accessibilityAddTraits(.isHeader)
                        ForEach(sections) { section in
                            NavigationLink(value: ManualRoute.reference(section.manualReference)) {
                                ReferenceSectionRow(section: section)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(chapter.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("manual.chapter.\(chapter.id)")
    }
}

private struct ManualLessonView: View {
    @EnvironmentObject private var model: AppModel
    let lesson: ManualLesson

    private var deepReference: SurvivalManualSection? {
        guard let chapter = model.manualChapter(id: lesson.chapterID) else { return nil }
        return model.manualSections(for: chapter).first { $0.lessonID == lesson.id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("60-SECOND ACTION CARD", systemImage: "timer")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tint)
                    Text(lesson.title)
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text(lesson.goal)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ActionStepsCard(actions: lesson.actions)
                WarningCard(warnings: lesson.warnings)

                if let deepReference {
                    NavigationLink(value: ManualRoute.reference(deepReference.manualReference)) {
                        Label("Open deeper reference", systemImage: "doc.text.magnifyingglass")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
                    }
                    .buttonStyle(.plain)
                }

                if !lesson.sources.isEmpty {
                    SourceList(sources: lesson.sources, reviewedAt: lesson.reviewedAt)
                }
            }
            .padding()
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(lesson.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("manual.lesson.\(lesson.id)")
    }
}

private struct DetailedManualSectionView: View {
    @EnvironmentObject private var model: AppModel
    let reference: ManualReference

    var body: some View {
        ScrollView {
            Group {
                switch model.manualPassage(for: reference) {
                case .available(let passage):
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("CHAPTER \(passage.chapterNumber) · \(passage.chapterTitle.uppercased())")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.tint)
                            Text(passage.lessonTitle)
                                .font(.largeTitle.bold())
                                .accessibilityAddTraits(.isHeader)
                            Label("Reviewed \(passage.reviewedAt)", systemImage: "checkmark.seal.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 9) {
                            Text("Quick answer")
                                .font(.headline)
                            Text(passage.answerText)
                                .font(.title3.weight(.medium))
                        }
                        .padding(18)
                        .background(.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 20))

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Reference")
                                .font(.title2.bold())
                            Text(passage.referenceText)
                                .font(.body)
                                .lineSpacing(5)
                                .textSelection(.enabled)
                        }

                        SourceList(sources: passage.sources, reviewedAt: passage.reviewedAt)
                    }
                case .retired(let replacement, let note):
                    VStack(spacing: 18) {
                        ContentUnavailableView(
                            "Passage retired",
                            systemImage: "arrow.triangle.2.circlepath",
                            description: Text(note)
                        )
                        NavigationLink(value: ManualRoute.reference(replacement)) {
                            Label("Open updated guidance", systemImage: "book.pages.fill")
                                .font(.headline)
                                .padding(14)
                                .frame(maxWidth: .infinity)
                                .background(.tint, in: RoundedRectangle(cornerRadius: 16))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                case .unavailable:
                    ManualUnavailableView(
                        message: "The referenced passage is unavailable, but emergency basics remain usable offline."
                    )
                }
            }
            .padding()
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(reference.sectionTitle)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("manual.reference.\(reference.passageID)")
    }
}

private struct ActionStepsCard: View {
    let actions: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Label("Do this now", systemImage: "figure.walk.motion")
                .font(.title2.bold())
                .foregroundStyle(Color.manualForest)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(actions.enumerated()), id: \.offset) { index, action in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index + 1)")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.manualForest, in: Circle())
                        .accessibilityHidden(true)
                    Text(action)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Step \(index + 1). \(action)")
            }
        }
        .padding(18)
        .background(Color.manualForest.opacity(0.09), in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct WarningCard: View {
    let warnings: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label("Critical warnings", systemImage: "exclamationmark.triangle.fill")
                .font(.title3.bold())
                .foregroundStyle(.orange)
                .accessibilityAddTraits(.isHeader)
            ForEach(warnings, id: \.self) { warning in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "xmark.octagon.fill")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text(warning)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Warning. \(warning)")
            }
        }
        .padding(18)
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct SourceList: View {
    let sources: [SurvivalSource]
    let reviewedAt: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Primary guidance", systemImage: "checkmark.seal.fill")
                .font(.headline)
            ForEach(sources) { source in
                VStack(alignment: .leading, spacing: 4) {
                    Text(source.title)
                        .font(.subheadline.weight(.semibold))
                    Text("\(source.organization) · \(source.locator)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let url = URL(string: source.url) {
                        Link("Open source", destination: url)
                            .font(.caption.weight(.semibold))
                    }
                }
            }
            Text("Source checked \(reviewedAt). This is primary-source verification, not a claim of independent medical certification.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct ManualChapterHero: View {
    let chapter: ManualCourseChapter

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: chapter.symbol)
                    .font(.title2)
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityHidden(true)
                Spacer()
                Text("CHAPTER \(chapter.number)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.88))
            }
            Text(chapter.title)
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            Text(chapter.overview)
                .font(.body)
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [chapter.theme.color, chapter.theme.color.opacity(0.64)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 26)
        )
    }
}

private struct ManualChapterCard: View {
    let chapter: ManualCourseChapter

    var body: some View {
        HStack(spacing: 16) {
            VStack(spacing: 3) {
                Text("\(chapter.number)")
                    .font(.title.bold())
                Image(systemName: chapter.symbol)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(chapter.theme.color)
            .frame(width: 54, height: 62)
            .background(chapter.theme.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(chapter.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(chapter.purpose)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Chapter \(chapter.number), \(chapter.title). \(chapter.purpose)")
    }
}

private struct ManualLessonRow: View {
    let lesson: ManualLesson

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: "bolt.fill")
                .foregroundStyle(.tint)
                .frame(width: 38, height: 38)
                .background(.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(lesson.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(lesson.goal)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
                .accessibilityHidden(true)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}

private struct ReferenceSectionRow: View {
    let section: SurvivalManualSection

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(section.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(section.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
                .accessibilityHidden(true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

private struct SearchGroupHeading: View {
    let title: String
    let count: Int

    var body: some View {
        HStack {
            Text(title)
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Text("\(count)")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
        }
    }
}

private struct ManualUnavailableView: View {
    let message: String

    var body: some View {
        ContentUnavailableView(
            "Passage unavailable",
            systemImage: "book.closed",
            description: Text(message)
        )
    }
}

private extension ManualTheme {
    var color: Color {
        switch self {
        case .forest: return .manualForest
        case .earth: return .brown
        case .water: return .manualWater
        case .fire: return .orange
        case .sky: return .blue
        case .rescue: return .red
        case .wildlife: return .green
        case .road: return .indigo
        }
    }
}

private extension Color {
    static let manualForest = Color(red: 0.12, green: 0.34, blue: 0.25)
    static let manualWater = Color(red: 0.08, green: 0.42, blue: 0.57)
}
