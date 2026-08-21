import Foundation

public enum IncidentRuntimeIssue: Equatable, Sendable {
    case compiledKnowledgeUnavailable
}

public struct IncidentRuntimeResolution: Sendable {
    public let assistant: IncidentAssistant
    public let activePacks: ActivePackSnapshot
    public let runtimeTiers: Set<ModelTier>
    public let usesCompiledKnowledge: Bool
    public let issues: [IncidentRuntimeIssue]

    public init(
        assistant: IncidentAssistant,
        activePacks: ActivePackSnapshot,
        runtimeTiers: Set<ModelTier>,
        usesCompiledKnowledge: Bool,
        issues: [IncidentRuntimeIssue]
    ) {
        self.assistant = assistant
        self.activePacks = activePacks
        self.runtimeTiers = runtimeTiers
        self.usesCompiledKnowledge = usesCompiledKnowledge
        self.issues = issues
    }
}

public struct IncidentRuntimeBootstrap: Sendable {
    private let bundledArticles: [KnowledgeArticle]
    private let survivalKnowledge: SurvivalKnowledgeStore?
    private let modelProvider: @Sendable (ModelTier) -> any LocalLanguageModel

    public init(
        bundledArticles: [KnowledgeArticle],
        survivalKnowledge: SurvivalKnowledgeStore? = nil,
        modelProvider: @escaping @Sendable (ModelTier) -> any LocalLanguageModel = {
            UnavailableLanguageModel(tier: $0)
        }
    ) {
        self.bundledArticles = bundledArticles
        self.survivalKnowledge = survivalKnowledge
        self.modelProvider = modelProvider
    }

    public func resolve(
        activePacks: ActivePackSnapshot,
        availableModelTiers: Set<ModelTier> = [],
        expertContextAssembler: ExpertContextAssembler? = nil,
        embeddingProvider: (any QueryEmbeddingProvider)? = nil,
        expertEmbeddingProvider: (any ExpertQueryEmbeddingProvider)? = nil,
        expertVectorIndex: ShardedExpertVectorIndex? = nil
    ) -> IncidentRuntimeResolution {
        let bundled = RetrievalEngine(articles: bundledArticles)
        let retrieval: any EvidenceRetrieving
        let usesCompiledKnowledge: Bool
        var issues: [IncidentRuntimeIssue] = []

        if let survivalKnowledge {
            retrieval = SurvivalKnowledgeRetriever(store: survivalKnowledge)
            usesCompiledKnowledge = true
        } else if activePacks.knowledge.isEmpty {
            retrieval = bundled
            usesCompiledKnowledge = false
        } else {
            do {
                let compiled = try SQLiteHybridRetriever(
                    activeKnowledgePackages: activePacks.knowledge,
                    embeddingProvider: embeddingProvider
                )
                retrieval = RankFusingRetriever(sources: [bundled, compiled])
                usesCompiledKnowledge = true
            } catch {
                retrieval = bundled
                usesCompiledKnowledge = false
                issues.append(.compiledKnowledgeUnavailable)
            }
        }

        let runtimeTiers = activePacks.installedTiers
            .intersection(availableModelTiers)
        let assistant = IncidentAssistant(
            articles: bundledArticles,
            installedTiers: runtimeTiers,
            retrieval: retrieval,
            expertEvidenceRetrieval: survivalKnowledge,
            expertValidated: runtimeTiers.contains(.expert),
            expertContextAssembler: expertContextAssembler,
            expertEmbeddingProvider: expertEmbeddingProvider,
            expertVectorIndex: expertVectorIndex,
            modelProvider: modelProvider
        )
        return IncidentRuntimeResolution(
            assistant: assistant,
            activePacks: activePacks,
            runtimeTiers: runtimeTiers,
            usesCompiledKnowledge: usesCompiledKnowledge,
            issues: issues
        )
    }
}
