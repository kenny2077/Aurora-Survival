import Foundation

public enum OfflineMapStyleError: Error, Equatable {
    case invalidTemplate
    case missingVectorSource
    case missingGlyphAssets
}

/// Resolves the signed style template to package-local PMTiles and glyph URLs.
/// The returned style has no HTTP(S) resource and can be reloaded in airplane
/// mode without silently contacting a basemap service.
public struct OfflineMapStyleAssembler: Sendable {
    public init() {}

    public func assemble(
        templateData: Data,
        pmtilesURL: URL,
        glyphsDirectoryURL: URL?
    ) throws -> Data {
        try assemble(
            templateData: templateData,
            sourceURLs: ["protomaps": pmtilesURL],
            glyphsDirectoryURL: glyphsDirectoryURL
        )
    }

    public func assemble(
        templateData: Data,
        sourceURLs: [String: URL],
        glyphsDirectoryURL: URL?
    ) throws -> Data {
        guard var style = try JSONSerialization.jsonObject(
            with: templateData
        ) as? [String: Any],
              var sources = style["sources"] as? [String: Any]
        else {
            throw OfflineMapStyleError.invalidTemplate
        }
        for (name, url) in sourceURLs {
            guard var source = sources[name] as? [String: Any],
                  source["type"] as? String == "vector"
            else { throw OfflineMapStyleError.missingVectorSource }
            source["url"] = "pmtiles://\(url.absoluteString)"
            sources[name] = source
        }
        style["sources"] = sources

        if style["glyphs"] != nil {
            guard let glyphsDirectoryURL else {
                throw OfflineMapStyleError.missingGlyphAssets
            }
            var glyphsBase = glyphsDirectoryURL.absoluteString
            while glyphsBase.hasSuffix("/") {
                glyphsBase.removeLast()
            }
            style["glyphs"] = glyphsBase + "/{fontstack}/{range}.pbf"
        }

        let data = try JSONSerialization.data(
            withJSONObject: style,
            options: [.sortedKeys]
        )
        guard !Self.containsNetworkURL(in: style) else {
            throw OfflineMapStyleError.invalidTemplate
        }
        return data
    }

    private static func containsNetworkURL(in value: Any) -> Bool {
        if let string = value as? String {
            let lowercased = string.lowercased()
            return lowercased.contains("http://")
                || lowercased.contains("https://")
        }
        if let array = value as? [Any] {
            return array.contains(where: containsNetworkURL)
        }
        if let dictionary = value as? [String: Any] {
            return dictionary.values.contains(where: containsNetworkURL)
        }
        return false
    }
}
