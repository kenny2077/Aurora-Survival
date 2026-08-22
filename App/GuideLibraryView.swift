import SwiftUI
import UIKit

struct GuideLibraryView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isSearching: Bool {
        !model.libraryQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AuroraDesign.Space.lg) {
                if isSearching {
                    searchResults
                } else if let guide = model.fieldGuide {
                    manualHeader(guide.book)
                    chapterLibrary(guide.book.chapters)
                    priorityCard(guide.book)
                    masteryCard(guide.book)
                }
            }
            .padding(AuroraDesign.Space.md)
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Field Guide")
        .searchable(text: $model.libraryQuery, prompt: "Search skills, needs, or conditions")
        .navigationDestination(for: FieldGuideRoute.self) { route in
            switch route {
            case .chapter(let id):
                if let chapter = model.fieldGuide?.chapter(id: id) {
                    FieldGuideChapterView(chapter: chapter)
                } else { FieldGuideUnavailableView() }
            case .skill(let id):
                if let skill = model.fieldGuide?.skill(id: id) {
                    FieldGuideSkillView(skill: skill)
                } else { FieldGuideUnavailableView() }
            }
        }
        .overlay { if model.fieldGuide == nil { FieldGuideUnavailableView() } }
        .accessibilityIdentifier("manual.home")
    }

    private func manualHeader(_ book: FieldGuideBook) -> some View {
        VStack(alignment: .leading, spacing: AuroraDesign.Space.md) {
            HStack(alignment: .top) {
                Image(systemName: "mountain.2.fill")
                    .font(.title2).padding(12)
                    .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityHidden(true)
                Spacer()
                Label("Always offline", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.bold)).padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.white.opacity(0.16), in: Capsule())
            }
            Text(book.title).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
            Text(book.subtitle.uppercased()).font(.caption.weight(.bold)).tracking(1.2).opacity(0.82)
            Text(book.introduction).font(.body).opacity(0.92).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white).padding(AuroraDesign.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [AuroraDesign.spruce, AuroraDesign.river.opacity(0.82)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 28)
        )
    }

    private func chapterLibrary(_ chapters: [FieldGuideChapter]) -> some View {
        VStack(alignment: .leading, spacing: AuroraDesign.Space.sm) {
            Text("Six essential chapters").font(.title2.bold()).accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: chapterColumns, spacing: AuroraDesign.Space.md) {
                ForEach(chapters) { chapter in
                    NavigationLink(value: FieldGuideRoute.chapter(chapter.id)) {
                        FieldGuideChapterCard(chapter: chapter)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private var chapterColumns: [GridItem] {
        horizontalSizeClass == .compact || dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible())]
    }

    @ViewBuilder private var searchResults: some View {
        let results = model.fieldGuideSearchResults
        if results.isEmpty {
            ContentUnavailableView.search(text: model.libraryQuery)
                .frame(maxWidth: .infinity).padding(.vertical, 56)
                .accessibilityIdentifier("manual.search.no-results")
        } else {
            HStack {
                Text("Skills").font(.title2.bold())
                Spacer()
                Text("\(results.count)").font(.caption.bold()).foregroundStyle(.secondary)
            }
            ForEach(results) { result in
                NavigationLink(value: FieldGuideRoute.skill(result.skill.id)) {
                    FieldGuideSkillRow(chapter: result.chapter, skill: result.skill, detail: result.excerpt)
                }.buttonStyle(.plain)
            }
        }
    }

    private func priorityCard(_ book: FieldGuideBook) -> some View {
        VStack(alignment: .leading, spacing: AuroraDesign.Space.sm) {
            Label("Survival priority card", systemImage: "list.number").font(.title3.bold())
            ForEach(Array(book.priorityCard.enumerated()), id: \.element.id) { index, item in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index + 1)").font(.caption.bold()).foregroundStyle(.white)
                        .frame(width: 28, height: 28).background(AuroraDesign.signal, in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.headline)
                        Text(item.text).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Priority \(index + 1), \(item.title). \(item.text)")
            }
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private func masteryCard(_ book: FieldGuideBook) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(book.masterySkills.enumerated()), id: \.offset) { index, item in
                    Label(item, systemImage: "\(index + 1).circle.fill").frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(.top, 10)
        } label: { Text("Six skills to master before you go").font(.headline) }
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct FieldGuideChapterView: View {
    let chapter: FieldGuideChapter
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AuroraDesign.Space.lg) {
                VStack(alignment: .leading, spacing: AuroraDesign.Space.sm) {
                    HStack {
                        Image(systemName: chapter.symbol).font(.title2)
                        Spacer(); Text("CHAPTER \(chapter.order)").font(.caption.bold())
                    }
                    Text(chapter.title).font(.largeTitle.bold())
                    Text(chapter.purpose).font(.body).opacity(0.9)
                }
                .foregroundStyle(.white).padding(AuroraDesign.Space.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(chapterColor(chapter.theme).gradient, in: RoundedRectangle(cornerRadius: 26))
                Text("Skills").font(.title2.bold())
                ForEach(chapter.skills) { skill in
                    NavigationLink(value: FieldGuideRoute.skill(skill.id)) {
                        FieldGuideSkillRow(chapter: chapter, skill: skill, detail: skill.purpose)
                    }.buttonStyle(.plain)
                }
            }
            .padding(AuroraDesign.Space.md).frame(maxWidth: AuroraDesign.readableWidth).frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(chapter.title).navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("manual.chapter.\(chapter.id)")
    }
}

private struct FieldGuideSkillView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let skill: FieldGuideSkill
    @State private var selectedVisual: FieldGuideVisual?

    private var chapter: FieldGuideChapter? { model.fieldGuide?.chapter(containing: skill) }
    private var primaryVisuals: [FieldGuideVisual] { visuals(role: .primary) }
    private var supportingVisuals: [(FieldGuideVisualRole, FieldGuideVisual)] {
        skill.visuals.compactMap { placement in
            guard placement.role != .primary, let item = model.fieldGuide?.visual(id: placement.assetID) else { return nil }
            return (placement.role, item)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AuroraDesign.Space.lg) {
                VStack(alignment: .leading, spacing: AuroraDesign.Space.xs) {
                    if let chapter {
                        Text("CHAPTER \(chapter.order) · \(chapter.title.uppercased())")
                            .font(.caption.bold()).foregroundStyle(chapterColor(chapter.theme))
                    }
                    Text(skill.title).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                    Text(skill.purpose).font(.title3.weight(.medium)).foregroundStyle(.secondary)
                    if let difficulty = skill.difficulty {
                        Label(difficulty, systemImage: "gauge.with.dots.needle.33percent")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
                ForEach(primaryVisuals) { visual in
                    FieldGuideVisualCard(visual: visual, maximumHeight: horizontalSizeClass == .regular ? 360 : 260) {
                        selectedVisual = visual
                    }
                }
                ForEach(skill.sections) { FieldGuideSectionView(section: $0) }
                if !supportingVisuals.isEmpty {
                    VStack(alignment: .leading, spacing: AuroraDesign.Space.sm) {
                        Text("Related visual guidance").font(.title3.bold())
                        ForEach(supportingVisuals, id: \.1.id) { role, visual in
                            DisclosureGroup(role == .secondary ? "Improvised option" : visual.title) {
                                FieldGuideVisualCard(visual: visual, maximumHeight: horizontalSizeClass == .regular ? 340 : 240) {
                                    selectedVisual = visual
                                }.padding(.top, 10)
                            }
                            .padding(16).background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
                        }
                    }
                }
                relatedSkills
                adjacentNavigation
            }
            .padding(AuroraDesign.Space.md).frame(maxWidth: AuroraDesign.readableWidth, alignment: .leading).frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(skill.title).navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $selectedVisual) { FieldGuideImageViewer(visual: $0) }
        .accessibilityIdentifier("manual.skill.\(skill.id)")
    }

    private func visuals(role: FieldGuideVisualRole) -> [FieldGuideVisual] {
        skill.visuals.filter { $0.role == role }.compactMap { model.fieldGuide?.visual(id: $0.assetID) }
    }

    @ViewBuilder private var relatedSkills: some View {
        let related = skill.relatedSkillIDs.compactMap { model.fieldGuide?.skill(id: $0) }
        if !related.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Related skills").font(.title3.bold())
                ForEach(related) { item in
                    NavigationLink(value: FieldGuideRoute.skill(item.id)) {
                        Label(item.title, systemImage: "arrow.up.right")
                            .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder private var adjacentNavigation: some View {
        if let adjacent = model.fieldGuide?.adjacentSkills(to: skill) {
            HStack(spacing: AuroraDesign.Space.sm) {
                if let previous = adjacent.previous {
                    NavigationLink(value: FieldGuideRoute.skill(previous.id)) {
                        Label(previous.title, systemImage: "chevron.left").frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.bordered).accessibilityIdentifier("manual.previous.\(previous.id)")
                }
                if let next = adjacent.next {
                    NavigationLink(value: FieldGuideRoute.skill(next.id)) {
                        Label(next.title, systemImage: "chevron.right").labelStyle(TrailingIconLabelStyle())
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }.buttonStyle(.borderedProminent).accessibilityIdentifier("manual.next.\(next.id)")
                }
            }.controlSize(.large)
        }
    }
}

private struct FieldGuideChapterCard: View {
    let chapter: FieldGuideChapter
    var body: some View {
        HStack(spacing: AuroraDesign.Space.md) {
            VStack(spacing: 4) { Image(systemName: chapter.symbol).font(.title2); Text("\(chapter.order)").font(.caption.bold()) }
                .foregroundStyle(chapterColor(chapter.theme)).frame(width: 54, height: 62)
                .background(chapterColor(chapter.theme).opacity(0.12), in: RoundedRectangle(cornerRadius: 16)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(chapter.title).font(.headline).foregroundStyle(.primary)
                Text(chapter.purpose).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                Text("\(chapter.skills.count) skills").font(.caption.weight(.semibold)).foregroundStyle(chapterColor(chapter.theme))
            }
            Spacer(minLength: 4); Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        .contentShape(RoundedRectangle(cornerRadius: 20)).accessibilityElement(children: .combine)
        .accessibilityLabel("Chapter \(chapter.order), \(chapter.title). \(chapter.skills.count) skills. \(chapter.purpose)")
    }
}

private struct FieldGuideSkillRow: View {
    let chapter: FieldGuideChapter
    let skill: FieldGuideSkill
    let detail: String
    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Text("\(skill.order)").font(.caption.bold()).foregroundStyle(chapterColor(chapter.theme))
                .frame(width: 38, height: 38).background(chapterColor(chapter.theme).opacity(0.11), in: RoundedRectangle(cornerRadius: 11)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(skill.title).font(.headline).foregroundStyle(.primary)
                    if !skill.visuals.isEmpty {
                        Label("Visual guide", systemImage: "photo").labelStyle(.iconOnly).font(.caption)
                            .foregroundStyle(chapterColor(chapter.theme)).accessibilityLabel("Includes visual guide")
                    }
                }
                Text(chapter.title.uppercased()).font(.caption2.bold()).foregroundStyle(chapterColor(chapter.theme))
                Text(detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 4); Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary).padding(.top, 4)
        }
        .padding(15).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .contentShape(RoundedRectangle(cornerRadius: 18)).accessibilityElement(children: .combine)
    }
}

private struct FieldGuideSectionView: View {
    let section: FieldGuideSection
    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            if let heading = section.heading {
                Text(heading).font(section.kind == .callout ? .headline : .title3.bold()).accessibilityAddTraits(.isHeader)
            }
            FieldGuideMarkdownContent(content: section.content)
        }
        .padding(section.kind == .callout ? 16 : 0)
        .background(section.kind == .callout ? Color.accentColor.opacity(0.09) : Color.clear, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct FieldGuideMarkdownContent: View {
    let content: String
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                if line.hasPrefix("- ") {
                    HStack(alignment: .top, spacing: 10) {
                        Circle().fill(Color.accentColor).frame(width: 6, height: 6).padding(.top, 8)
                        markdown(String(line.dropFirst(2)))
                    }
                } else if let step = numbered(line) {
                    HStack(alignment: .top, spacing: 10) {
                        Text(step.number).font(.caption.bold()).foregroundStyle(.white)
                            .frame(width: 26, height: 26).background(AuroraDesign.spruce, in: Circle())
                        markdown(step.text)
                    }.accessibilityElement(children: .combine).accessibilityLabel("Step \(step.number). \(plain(step.text))")
                } else { markdown(line) }
            }
        }
    }
    private var lines: [String] {
        content.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
    private func numbered(_ line: String) -> (number: String, text: String)? {
        let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[0].hasSuffix("."), Int(parts[0].dropLast()) != nil else { return nil }
        return (String(parts[0].dropLast()), parts[1])
    }
    private func markdown(_ value: String) -> Text {
        if let attributed = try? AttributedString(markdown: value) { return Text(attributed) }
        return Text(value)
    }
    private func plain(_ value: String) -> String { value.replacingOccurrences(of: "**", with: "") }
}

private struct FieldGuideVisualCard: View {
    let visual: FieldGuideVisual
    let maximumHeight: CGFloat
    let open: () -> Void
    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(visual.title).font(.headline); Spacer()
                    Label("Enlarge", systemImage: "arrow.up.left.and.arrow.down.right").font(.caption.weight(.semibold))
                }
                if let image = fieldGuideImage(named: visual.imageName) {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: maximumHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                } else {
                    Label("Visual unavailable", systemImage: "photo.badge.exclamationmark").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 100).background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
                }
                Text(visual.caption).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(14).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain).accessibilityLabel("\(visual.title). \(visual.altText)")
        .accessibilityHint("Opens a full-screen zoomable image").accessibilityIdentifier("manual.visual.\(visual.id)")
    }
}

private struct FieldGuideImageViewer: View {
    @Environment(\.dismiss) private var dismiss
    let visual: FieldGuideVisual
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image = fieldGuideImage(named: visual.imageName) {
                ZoomableFieldGuideImage(image: image).ignoresSafeArea().accessibilityLabel(visual.altText)
            } else {
                ContentUnavailableView("Visual unavailable", systemImage: "photo.badge.exclamationmark").foregroundStyle(.white)
            }
            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.headline).foregroundStyle(.white)
                            .frame(width: 44, height: 44).background(.black.opacity(0.65), in: Circle())
                    }.accessibilityLabel("Close visual").accessibilityIdentifier("manual.visual.close")
                }.padding()
                Spacer()
                VStack(alignment: .leading, spacing: 5) {
                    Text(visual.title).font(.headline); Text(visual.caption).font(.caption).opacity(0.85)
                    Text("Pinch or double-tap to zoom").font(.caption2).opacity(0.65)
                }
                .foregroundStyle(.white).padding().frame(maxWidth: .infinity, alignment: .leading).background(.black.opacity(0.72))
            }
        }
    }
}

private struct ZoomableFieldGuideImage: UIViewRepresentable {
    let image: UIImage
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView(); scroll.delegate = context.coordinator
        scroll.minimumZoomScale = 1; scroll.maximumZoomScale = 5
        scroll.showsHorizontalScrollIndicator = false; scroll.showsVerticalScrollIndicator = false; scroll.backgroundColor = .black
        let imageView = UIImageView(image: image); imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false; imageView.isUserInteractionEnabled = true; scroll.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])
        context.coordinator.imageView = imageView; context.coordinator.scrollView = scroll
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2; scroll.addGestureRecognizer(doubleTap)
        return scroll
    }
    func updateUIView(_ uiView: UIScrollView, context: Context) { context.coordinator.imageView?.image = image }
    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?; weak var scrollView: UIScrollView?
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
        @objc func doubleTapped(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView else { return }; scrollView.setZoomScale(scrollView.zoomScale > 1 ? 1 : 2.5, animated: true)
        }
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View { HStack { configuration.title; configuration.icon } }
}

private struct FieldGuideUnavailableView: View {
    var body: some View {
        ContentUnavailableView("Field Guide unavailable", systemImage: "book.closed", description: Text("Reinstall Aurora before travelling so the bundled offline guide is available."))
    }
}

private func fieldGuideImage(named name: String) -> UIImage? {
    guard let url = Bundle.main.url(forResource: name, withExtension: "png") else { return nil }
    return UIImage(contentsOfFile: url.path)
}

private func chapterColor(_ theme: String) -> Color {
    switch theme {
    case "fire": return .orange
    case "water": return AuroraDesign.river
    case "earth": return .brown
    case "rescue": return AuroraDesign.signal
    case "sky": return .blue
    case "wildlife": return .green
    default: return AuroraDesign.spruce
    }
}
