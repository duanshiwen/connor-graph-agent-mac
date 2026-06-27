import Foundation

public enum MemoryOSL4RelationCategory: String, Codable, Sendable, CaseIterable, Equatable {
    case identity
    case taxonomy
    case composition
    case dependency
    case capability
    case applicability
    case provenance
    case governance
    case causality
    case contribution
    case location
    case reference
}

public enum MemoryOSL4RelationPredicate: String, Codable, Sendable, CaseIterable, Equatable {
    // Identity / equivalence
    case sameAs = "SAME_AS"
    case aliasOf = "ALIAS_OF"
    case equivalentTo = "EQUIVALENT_TO"
    case exactMatch = "EXACT_MATCH"
    case closeMatch = "CLOSE_MATCH"

    // Taxonomy / hierarchy
    case instanceOf = "INSTANCE_OF"
    case subclassOf = "SUBCLASS_OF"
    case broaderThan = "BROADER_THAN"
    case narrowerThan = "NARROWER_THAN"

    // Composition
    case hasPart = "HAS_PART"
    case partOf = "PART_OF"
    case contains = "CONTAINS"
    case memberOf = "MEMBER_OF"
    case overlapsWith = "OVERLAPS_WITH"

    // Dependency / constraint
    case dependsOn = "DEPENDS_ON"
    case requires = "REQUIRES"
    case enables = "ENABLES"
    case prevents = "PREVENTS"
    case constrains = "CONSTRAINS"

    // Capability / function
    case supportsCapability = "SUPPORTS_CAPABILITY"
    case implements = "IMPLEMENTS"
    case uses = "USES"

    // Applicability / abstraction
    case appliesTo = "APPLIES_TO"
    case usedFor = "USED_FOR"
    case specializes = "SPECIALIZES"
    case generalizes = "GENERALIZES"
    case fieldOfWork = "FIELD_OF_WORK"
    case inIndustry = "IN_INDUSTRY"

    // Provenance / evidence
    case derivedFrom = "DERIVED_FROM"
    case basedOn = "BASED_ON"
    case supportedBy = "SUPPORTED_BY"
    case cites = "CITES"
    case quotes = "QUOTES"
    case generatedBy = "GENERATED_BY"
    case validatedBy = "VALIDATED_BY"
    case attributedTo = "ATTRIBUTED_TO"

    // Governance / decision / lifecycle
    case decides = "DECIDES"
    case decidedBy = "DECIDED_BY"
    case governs = "GOVERNS"
    case compliesWith = "COMPLIES_WITH"
    case violates = "VIOLATES"
    case replaces = "REPLACES"
    case supersedes = "SUPERSEDES"
    case deprecates = "DEPRECATES"

    // Causality / influence
    case causes = "CAUSES"
    case influences = "INFLUENCES"
    case mitigates = "MITIGATES"
    case risks = "RISKS"

    // Person / work object / contribution
    case createdBy = "CREATED_BY"
    case maintainedBy = "MAINTAINED_BY"
    case ownedBy = "OWNED_BY"
    case responsibleFor = "RESPONSIBLE_FOR"
    case contributedBy = "CONTRIBUTED_BY"
    case reviewedBy = "REVIEWED_BY"
    case curatedBy = "CURATED_BY"
    case authoredBy = "AUTHORED_BY"
    case publishedBy = "PUBLISHED_BY"
    case developedBy = "DEVELOPED_BY"
    case foundedBy = "FOUNDED_BY"
    case stakeholderOf = "STAKEHOLDER_OF"
    case worksOn = "WORKS_ON"

    // Location / place / coordinates
    case locatedIn = "LOCATED_IN"
    case hasLocation = "HAS_LOCATION"
    case hasCoordinate = "HAS_COORDINATE"

    // Communication / reference / weak relation
    case differentFrom = "DIFFERENT_FROM"
    case oppositeOf = "OPPOSITE_OF"
    case saidToBeSameAs = "SAID_TO_BE_SAME_AS"
    case facetOf = "FACET_OF"
    case studiedBy = "STUDIED_BY"
    case about = "ABOUT"
    case mentions = "MENTIONS"
    case relatedTo = "RELATED_TO"
    case hasOfficialWebsite = "HAS_OFFICIAL_WEBSITE"
    case hasIdentifier = "HAS_IDENTIFIER"
    case associatedWith = "ASSOCIATED_WITH"
}

public extension MemoryOSL4RelationPredicate {
    var category: MemoryOSL4RelationCategory {
        switch self {
        case .sameAs, .aliasOf, .equivalentTo, .exactMatch, .closeMatch:
            return .identity
        case .instanceOf, .subclassOf, .broaderThan, .narrowerThan:
            return .taxonomy
        case .hasPart, .partOf, .contains, .memberOf, .overlapsWith:
            return .composition
        case .dependsOn, .requires, .enables, .prevents, .constrains:
            return .dependency
        case .supportsCapability, .implements, .uses:
            return .capability
        case .appliesTo, .usedFor, .specializes, .generalizes, .fieldOfWork, .inIndustry:
            return .applicability
        case .derivedFrom, .basedOn, .supportedBy, .cites, .quotes, .generatedBy, .validatedBy, .attributedTo:
            return .provenance
        case .decides, .decidedBy, .governs, .compliesWith, .violates, .replaces, .supersedes, .deprecates:
            return .governance
        case .causes, .influences, .mitigates, .risks:
            return .causality
        case .createdBy, .maintainedBy, .ownedBy, .responsibleFor, .contributedBy, .reviewedBy, .curatedBy, .authoredBy, .publishedBy, .developedBy, .foundedBy, .stakeholderOf, .worksOn:
            return .contribution
        case .locatedIn, .hasLocation, .hasCoordinate:
            return .location
        case .differentFrom, .oppositeOf, .saidToBeSameAs, .facetOf, .studiedBy, .about, .mentions, .hasOfficialWebsite, .hasIdentifier, .relatedTo, .associatedWith:
            return .reference
        }
    }

    var inverse: MemoryOSL4RelationPredicate? {
        switch self {
        case .sameAs: return .sameAs
        case .equivalentTo: return .equivalentTo
        case .exactMatch: return .exactMatch
        case .closeMatch: return .closeMatch
        case .relatedTo: return .relatedTo
        case .associatedWith: return .associatedWith
        case .overlapsWith: return .overlapsWith
        case .differentFrom: return .differentFrom
        case .oppositeOf: return .oppositeOf
        case .saidToBeSameAs: return .saidToBeSameAs
        case .hasPart: return .partOf
        case .partOf: return .hasPart
        case .broaderThan: return .narrowerThan
        case .narrowerThan: return .broaderThan
        case .generalizes: return .specializes
        case .specializes: return .generalizes
        case .decides: return .decidedBy
        case .decidedBy: return .decides
        default: return nil
        }
    }

    var isSymmetric: Bool {
        switch self {
        case .sameAs, .equivalentTo, .exactMatch, .closeMatch, .overlapsWith, .differentFrom, .oppositeOf, .saidToBeSameAs, .relatedTo, .associatedWith:
            return true
        default:
            return false
        }
    }

    var isTransitive: Bool {
        switch self {
        case .sameAs, .equivalentTo, .subclassOf, .broaderThan, .narrowerThan, .partOf, .locatedIn, .dependsOn:
            return true
        default:
            return false
        }
    }

    var isStrict: Bool {
        switch self {
        case .closeMatch, .overlapsWith, .differentFrom, .oppositeOf, .saidToBeSameAs, .facetOf, .studiedBy, .about, .mentions, .hasOfficialWebsite, .hasIdentifier, .relatedTo, .associatedWith, .influences:
            return false
        default:
            return true
        }
    }

    var retrievalWeight: Double {
        switch self {
        case .sameAs, .exactMatch:
            return 1.0
        case .aliasOf, .equivalentTo:
            return 0.95
        case .closeMatch:
            return 0.88
        case .instanceOf, .subclassOf, .broaderThan, .narrowerThan:
            return 0.9
        case .hasPart, .partOf, .contains, .memberOf, .overlapsWith, .dependsOn, .requires:
            return 0.8
        case .implements, .appliesTo, .derivedFrom, .basedOn, .supportedBy, .validatedBy, .generatedBy:
            return 0.75
        case .enables, .prevents, .constrains, .supportsCapability, .uses, .usedFor, .specializes, .generalizes, .fieldOfWork, .inIndustry:
            return 0.72
        case .decides, .decidedBy, .governs, .compliesWith, .violates, .replaces, .supersedes, .deprecates:
            return 0.72
        case .causes, .risks, .mitigates:
            return 0.7
        case .influences:
            return 0.65
        case .createdBy, .maintainedBy, .ownedBy, .responsibleFor, .contributedBy, .reviewedBy, .curatedBy, .authoredBy, .publishedBy, .developedBy, .foundedBy, .stakeholderOf, .worksOn:
            return 0.68
        case .locatedIn, .hasLocation:
            return 0.7
        case .hasCoordinate:
            return 0.58
        case .differentFrom, .oppositeOf, .saidToBeSameAs, .facetOf, .studiedBy:
            return 0.62
        case .cites, .quotes, .attributedTo:
            return 0.68
        case .hasOfficialWebsite, .hasIdentifier:
            return 0.55
        case .about:
            return 0.6
        case .mentions:
            return 0.5
        case .relatedTo:
            return 0.45
        case .associatedWith:
            return 0.4
        }
    }

    var description: String {
        switch self {
        case .sameAs: return "Strong identity relation: subject and object denote the same stable entity."
        case .aliasOf: return "Alias/name relation between stable entities or concepts."
        case .equivalentTo: return "Conceptual equivalence without necessarily asserting identical entity identity."
        case .exactMatch: return "Exact cross-vocabulary or cross-system concept/entity match."
        case .closeMatch: return "Close but not exact cross-vocabulary or cross-system match."
        case .instanceOf: return "Subject is an instance of the object type/class/concept."
        case .subclassOf: return "Subject class/concept is a subtype of object class/concept."
        case .broaderThan: return "Subject concept is broader than object concept in a knowledge organization scheme."
        case .narrowerThan: return "Subject concept is narrower than object concept in a knowledge organization scheme."
        case .hasPart: return "Subject has object as a durable structural part."
        case .partOf: return "Subject is a durable structural part of object."
        case .contains: return "Subject contains object as a member, item, or contained concept."
        case .memberOf: return "Subject is a member of object group, organization, collection, or work object."
        case .overlapsWith: return "Subject partially overlaps with object without asserting containment, identity, or hierarchy."
        case .dependsOn: return "Subject depends on object."
        case .requires: return "Subject requires object as a necessary condition."
        case .enables: return "Subject enables object capability, process, or outcome."
        case .prevents: return "Subject prevents object risk, failure, or outcome."
        case .constrains: return "Subject constrains object behavior, scope, or implementation."
        case .supportsCapability: return "Subject supports the object capability."
        case .implements: return "Subject implements object design, interface, standard, or mechanism."
        case .uses: return "Subject uses object tool, resource, technology, or concept."
        case .appliesTo: return "Subject applies to object scope, domain, entity, or situation."
        case .usedFor: return "Subject is used for object purpose or capability."
        case .specializes: return "Subject specializes object abstraction, pattern, or concept."
        case .generalizes: return "Subject generalizes object specialization, pattern, or concept."
        case .fieldOfWork: return "Subject has object as a durable field of work, research, or practice."
        case .inIndustry: return "Subject belongs to or operates in object industry or sector."
        case .derivedFrom: return "Subject is derived from object evidence, source, or prior artifact."
        case .basedOn: return "Subject is based on object source, work, evidence, or idea."
        case .supportedBy: return "Subject is supported by object evidence, source, or justification."
        case .cites: return "Subject cites object source or reference."
        case .quotes: return "Subject directly quotes object source or evidence."
        case .generatedBy: return "Subject was generated by object process, run, tool, or agent."
        case .validatedBy: return "Subject was validated by object validator, standard, or review."
        case .attributedTo: return "Subject is attributed to object person, organization, or source."
        case .decides: return "Subject decision record decides object policy, design, or outcome."
        case .decidedBy: return "Subject policy, design, or outcome was decided by object decision record."
        case .governs: return "Subject standard, rule, or policy governs object."
        case .compliesWith: return "Subject complies with object standard, rule, or policy."
        case .violates: return "Subject violates object standard, rule, or policy."
        case .replaces: return "Subject replaces object."
        case .supersedes: return "Subject supersedes object in a semantic or lifecycle evolution."
        case .deprecates: return "Subject deprecates object."
        case .causes: return "Subject causes object outcome or state, with evidence-backed causal basis."
        case .influences: return "Subject influences object without asserting deterministic causation."
        case .mitigates: return "Subject mitigates object risk, failure mode, or negative outcome."
        case .risks: return "Subject creates or increases risk of object."
        case .createdBy: return "Subject was created by object person, group, organization, or process."
        case .maintainedBy: return "Subject is maintained by object person, group, or organization."
        case .ownedBy: return "Subject is owned by object person, group, or organization."
        case .responsibleFor: return "Subject is responsible for object."
        case .contributedBy: return "Subject received contribution from object person, group, or organization."
        case .reviewedBy: return "Subject was reviewed by object person, group, validator, or organization."
        case .curatedBy: return "Subject was curated by object person, group, or organization."
        case .authoredBy: return "Subject was authored by object person, group, or organization."
        case .publishedBy: return "Subject was published by object person, group, or organization."
        case .developedBy: return "Subject was developed by object person, group, organization, or project."
        case .foundedBy: return "Subject organization, project, or initiative was founded by object person or organization."
        case .stakeholderOf: return "Subject is a stakeholder of object work object, project, product, or decision."
        case .worksOn: return "Subject works on object project, product, research topic, or work object."
        case .locatedIn: return "Subject is durably located in object place, region, jurisdiction, or container place."
        case .hasLocation: return "Subject has object as a location, venue, or place associated with it."
        case .hasCoordinate: return "Subject has object coordinate value or geospatial literal."
        case .differentFrom: return "Subject is explicitly distinct from object and should not be merged with it."
        case .oppositeOf: return "Subject is semantically opposite to object."
        case .saidToBeSameAs: return "Source claims subject may be the same as object, but identity is not strong enough for SAME_AS."
        case .facetOf: return "Subject is a facet, aspect, or view of object."
        case .studiedBy: return "Subject is studied by object field, discipline, method, or research area."
        case .about: return "Subject is primarily about object."
        case .mentions: return "Subject mentions object without making it the primary topic."
        case .hasOfficialWebsite: return "Subject has object URL as official website or canonical web presence."
        case .hasIdentifier: return "Subject has object literal as an external identifier or registry identifier."
        case .relatedTo: return "Weak fallback relation for durable related concepts/entities when no more specific predicate applies."
        case .associatedWith: return "Weak association relation between stable concepts/entities."
        }
    }
}
