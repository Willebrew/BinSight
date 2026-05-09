import Foundation

/// Direct Perplexity client for the iPhone-first build.
///
/// Mirrors the prompt/schema/endpoint we proved works against
/// /Users/willkillebrew/Desktop/product-jpeg-500x500.png with sonar-pro.
/// Reads `PERPLEXITY_API_KEY` from Info.plist (or the bundle env). For
/// production, swap to a server-side action so the key never ships in the app.
enum PerplexityClient {
    private static let chatURL = URL(string: "https://api.perplexity.ai/chat/completions")!
    private static let model = "sonar-pro"

    static var apiKey: String? {
        Bundle.main.object(forInfoDictionaryKey: "PERPLEXITY_API_KEY") as? String
    }

    static var isConfigured: Bool { (apiKey ?? "").isEmpty == false }

    struct Result {
        let items: [ItemDoc]
        let localRules: String
        let citations: [String]
        let model: String
    }

    static func classify(jpeg: Data, lat: Double?, lng: Double?) async throws -> Result {
        guard let key = apiKey, !key.isEmpty else {
            throw NSError(domain: "Perplexity", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "PERPLEXITY_API_KEY missing in Info.plist"])
        }

        let dataUrl = "data:image/jpeg;base64,\(jpeg.base64EncodedString())"

        let body: [String: Any] = [
            "model": model,
            "response_format": ["type": "json_schema", "json_schema": Self.schema],
            "messages": [
                ["role": "system", "content": Self.systemPrompt(lat: lat, lng: lng)],
                ["role": "user", "content": [
                    ["type": "text", "text": "Classify the items in this photo for disposal."],
                    ["type": "image_url", "image_url": ["url": dataUrl]]
                ]]
            ]
        ]

        var req = URLRequest(url: chatURL)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 60
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "Perplexity", code: 2, userInfo: [NSLocalizedDescriptionKey: "No HTTP response"])
        }
        guard (200..<300).contains(http.statusCode) else {
            let s = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "Perplexity", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "API \(http.statusCode): \(s.prefix(400))"])
        }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        let content = envelope.choices.first?.message.content ?? ""
        let parsed = try parseStructured(content)
        let items = parsed.items.map { it in
            ItemDoc(
                label: it.label,
                material: it.material,
                decision: it.decision,
                confidence: max(0, min(1, it.confidence)),
                co2Kg: ImpactTable.estimate(material: it.material, decision: it.decision),
                disposalNotes: it.disposalNotes
            )
        }
        return Result(items: items,
                      localRules: parsed.localRules,
                      citations: envelope.citations ?? [],
                      model: envelope.model ?? model)
    }

    private static func systemPrompt(lat: Double?, lng: Double?) -> String {
        let loc = (lat != nil && lng != nil)
            ? String(format: "User location: %.3f, %.3f.", lat!, lng!)
            : "Location unknown."
        return [
            "You are BinSight, an expert in municipal waste classification.",
            "Identify every distinct waste item visible in the photo.",
            "For each item, decide whether it should be recycled, composted, trashed, or treated as hazardous, given the user's location.",
            "Search the web when local recycling rules might change the answer.",
            "Be conservative: if a container is contaminated and the local program rejects contaminated items, mark as trash.",
            loc,
        ].joined(separator: " ")
    }

    private static let schema: [String: Any] = [
        "schema": [
            "type": "object",
            "additionalProperties": false,
            "required": ["items", "localRules"],
            "properties": [
                "items": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "required": ["label", "material", "decision", "confidence", "disposalNotes"],
                        "properties": [
                            "label": ["type": "string"],
                            "material": ["type": "string", "description": "pet|hdpe|aluminum|steel|paper|cardboard|glass|organic|mixed|unknown"],
                            "decision": ["type": "string", "enum": ["recycle", "trash", "compost", "hazard"]],
                            "confidence": ["type": "number", "minimum": 0, "maximum": 1],
                            "disposalNotes": ["type": "string"],
                        ]
                    ]
                ],
                "localRules": ["type": "string"],
            ]
        ]
    ]

    // MARK: - Decoding

    private struct Envelope: Decodable {
        let model: String?
        let choices: [Choice]
        let citations: [String]?
        struct Choice: Decodable { let message: Message }
        struct Message: Decodable { let content: String }
    }

    private struct ParsedContent: Decodable {
        let items: [ParsedItem]
        let localRules: String
    }

    private struct ParsedItem: Decodable {
        let label: String
        let material: String
        let decision: String
        let confidence: Double
        let disposalNotes: String
    }

    private static func parseStructured(_ raw: String) throws -> ParsedContent {
        if let data = raw.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(ParsedContent.self, from: data) {
            return decoded
        }
        if let openIdx = raw.firstIndex(of: "{"),
           let closeIdx = raw.lastIndex(of: "}"),
           openIdx <= closeIdx,
           let data = String(raw[openIdx...closeIdx]).data(using: .utf8),
           let decoded = try? JSONDecoder().decode(ParsedContent.self, from: data) {
            return decoded
        }
        throw NSError(domain: "Perplexity", code: 3,
                      userInfo: [NSLocalizedDescriptionKey: "Could not parse model output as JSON"])
    }
}
