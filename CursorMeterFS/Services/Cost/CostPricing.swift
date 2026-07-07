import Foundation

/// Built-in per-token USD price table for local cost estimation.
/// Costs are ESTIMATES: token counts come from local session logs, prices from this table.
/// Keyed by model-id prefix; lookup picks the longest matching prefix so versioned ids
/// ("claude-opus-4-8-20260115") resolve to their base entry.
enum CostPricing {

    struct ModelPricing {
        let input: Double          // USD per input token
        let output: Double         // USD per output token
        let cacheRead: Double      // USD per cache-read token
        let cacheWrite: Double     // USD per cache-creation token (Claude only; 0 for OpenAI)

        init(input: Double, output: Double, cacheRead: Double = 0, cacheWrite: Double = 0) {
            self.input = input
            self.output = output
            self.cacheRead = cacheRead
            self.cacheWrite = cacheWrite
        }
    }

    // MARK: - OpenAI / Codex models

    static let codex: [String: ModelPricing] = [
        "gpt-5.4":            ModelPricing(input: 2.5e-6,  output: 1.5e-5, cacheRead: 2.5e-7),
        "gpt-5.3-codex-spark": ModelPricing(input: 0,      output: 0),      // research preview
        "gpt-5.3-codex":      ModelPricing(input: 1.75e-6, output: 1.4e-5, cacheRead: 1.75e-7),
        "gpt-5.2-pro":        ModelPricing(input: 2.1e-5,  output: 1.68e-4),
        "gpt-5.2":            ModelPricing(input: 1.75e-6, output: 1.4e-5, cacheRead: 1.75e-7),
        "gpt-5.1-codex-mini": ModelPricing(input: 2.5e-7,  output: 2e-6,   cacheRead: 2.5e-8),
        "gpt-5.1":            ModelPricing(input: 1.25e-6, output: 1e-5,   cacheRead: 1.25e-7),
        "gpt-5-pro":          ModelPricing(input: 1.5e-5,  output: 1.2e-4),
        "gpt-5-mini":         ModelPricing(input: 2.5e-7,  output: 2e-6,   cacheRead: 2.5e-8),
        "gpt-5-nano":         ModelPricing(input: 5e-8,    output: 4e-7,   cacheRead: 5e-9),
        "gpt-5":              ModelPricing(input: 1.25e-6, output: 1e-5,   cacheRead: 1.25e-7),
    ]

    // MARK: - Claude models

    static let claude: [String: ModelPricing] = [
        "claude-fable-5":   ModelPricing(input: 1e-5,   output: 5e-5,   cacheRead: 1e-6,   cacheWrite: 1.25e-5),
        "claude-opus-4-1":  ModelPricing(input: 1.5e-5, output: 7.5e-5, cacheRead: 1.5e-6, cacheWrite: 1.875e-5),
        "claude-opus-4":    ModelPricing(input: 5e-6,   output: 2.5e-5, cacheRead: 5e-7,   cacheWrite: 6.25e-6),
        "claude-sonnet-5":  ModelPricing(input: 3e-6,   output: 1.5e-5, cacheRead: 3e-7,   cacheWrite: 3.75e-6),
        "claude-sonnet-4":  ModelPricing(input: 3e-6,   output: 1.5e-5, cacheRead: 3e-7,   cacheWrite: 3.75e-6),
        "claude-haiku-4":   ModelPricing(input: 1e-6,   output: 5e-6,   cacheRead: 1e-7,   cacheWrite: 1.25e-6),
    ]

    // MARK: - Lookup & math

    /// Longest matching prefix wins; nil when the model is unknown (caller skips it).
    static func pricing(forModel model: String, in table: [String: ModelPricing]) -> ModelPricing? {
        let lower = model.lowercased()
        var best: (prefix: String, pricing: ModelPricing)?
        for (prefix, pricing) in table where lower.hasPrefix(prefix) {
            if best == nil || prefix.count > best!.prefix.count {
                best = (prefix, pricing)
            }
        }
        return best?.pricing
    }

    /// Claude accounting: input / cacheCreation / cacheRead are disjoint counts.
    static func claudeCost(
        model: String,
        inputTokens: Int,
        outputTokens: Int,
        cacheCreationTokens: Int,
        cacheReadTokens: Int
    ) -> Double? {
        guard let p = pricing(forModel: model, in: claude) else { return nil }
        return Double(inputTokens) * p.input
            + Double(outputTokens) * p.output
            + Double(cacheCreationTokens) * p.cacheWrite
            + Double(cacheReadTokens) * p.cacheRead
    }

    /// OpenAI accounting: `cachedInputTokens` is a SUBSET of `inputTokens`.
    static func codexCost(
        model: String,
        inputTokens: Int,
        cachedInputTokens: Int,
        outputTokens: Int
    ) -> Double? {
        guard let p = pricing(forModel: model, in: codex) else { return nil }
        let uncached = max(inputTokens - cachedInputTokens, 0)
        return Double(uncached) * p.input
            + Double(cachedInputTokens) * p.cacheRead
            + Double(outputTokens) * p.output
    }
}
