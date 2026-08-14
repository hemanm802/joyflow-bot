import Foundation
import Testing

@testable import JoyflowKit

struct PluginCatalogTests {
    @Test func featuredIncludesCoreSet() {
        let slugs = Set(PluginCatalog.featuredSlugs)
        let names = Dictionary(uniqueKeysWithValues: PluginCatalog.featured.map { ($0.slug, $0.name) })
        let required: [(String, String)] = [
            ("gmail", "Gmail"),
            ("googlecalendar", "Google Calendar"),
            ("googledrive", "Google Drive"),
            ("granola", "Granola"),
            ("arize", "Arize"),
            ("atlan", "Atlan"),
            ("awsagents", "AWS Agents"),
            ("awssagemaker", "AWS SageMaker"),
        ]
        for (slug, name) in required {
            #expect(slugs.contains(slug), "missing \(slug)")
            #expect(names[slug] == name, "\(slug) display name")
            #expect(PluginCatalog.contains(slug))
        }
        let extras = Set(PluginCatalog.extraSlugs)
        for slug in ["slack", "notion", "github"] {
            #expect(extras.contains(slug), "missing extra \(slug)")
        }
    }

    @Test func catalogExceedsOriginalEleven() {
        let original: Set<String> = [
            "gmail", "googlecalendar", "googledrive", "granola", "arize", "atlan",
            "awsagents", "awssagemaker", "slack", "notion", "github",
        ]
        #expect(PluginCatalog.bundledSlugs.count > 18)
        #expect(Set(PluginCatalog.bundledSlugs).isSuperset(of: original))
        #expect(PluginCatalog.contains("linear"))
        #expect(PluginCatalog.contains("figma"))
        #expect(PluginCatalog.contains("trello"))
        #expect(PluginCatalog.contains("stripe"))
    }

    @Test func searchFiltersByNameAndSlug() {
        let gmail = PluginCatalog.search("gmail")
        #expect(gmail.contains { $0.slug == "gmail" })
        #expect(!gmail.contains { $0.slug == "arize" })
        #expect(!gmail.contains { $0.name == "Arize" })
        let calendar = PluginCatalog.search("Google Calendar")
        #expect(calendar.contains { $0.slug == "googlecalendar" })
        #expect(PluginCatalog.search("   ").count == PluginCatalog.allBundled.count)
        #expect(PluginCatalog.search("GITHUB").contains { $0.slug == "github" })
    }
}

struct PluginIconTests {
    @Test func bundledSlugsHavePackSourcedImages() {
        var seen = Set<String>()
        for slug in PluginCatalog.bundledSlugs {
            let ref = PluginIcon.lookup(slug)
            #expect(ref != nil, "missing lookup for \(slug)")
            guard let ref else { continue }
            #expect(!ref.identifier.isEmpty)
            #expect(!ref.fileName.isEmpty)
            #expect(ref.packSource.hasPrefix("iconify:") || ref.packSource.hasPrefix("official"))
            #expect(!ref.packSource.contains("handmade"))
            #expect(!seen.contains(ref.identifier), "duplicate \(ref.identifier)")
            seen.insert(ref.identifier)

            let data = PluginIcon.bundledImageData(for: slug)
            #expect(data != nil, "missing PNG for \(slug)")
            #expect((data?.count ?? 0) > 0, "empty PNG for \(slug)")
            #expect(PluginIcon.identifier(for: slug.uppercased()) == ref.identifier)
        }
        #expect(seen.count == PluginCatalog.bundledSlugs.count)
    }

    @Test func unknownSlugHasNoImage() {
        #expect(PluginIcon.lookup("not-a-featured-toolkit") == nil)
        #expect(PluginIcon.bundledImageData(for: "not-a-featured-toolkit") == nil)
    }
}

struct ColorTokenAppearanceTests {
    @Test func lightAndDarkTokensDiffer() {
        #expect(ColorTokens.background.light != ColorTokens.background.dark)
        #expect(ColorTokens.surface.light != ColorTokens.surface.dark)
        #expect(ColorTokens.textPrimary.light != ColorTokens.textPrimary.dark)
    }
}
