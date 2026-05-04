import Foundation

/// Fuzzy-matching scorer for the search pipeline.
///
/// Scoring formula: per-token sum-normalized Damerau-Levenshtein ratio
/// with first-character anchor.
/// `score = (|q|+|c| - dl_osa(q,c)) / (|q|+|c|) * 100`
/// If `q[0] != c[0]`, score is multiplied by `0.85`. The anchor empirically
/// kills cross-prefix false positives like «сандерсо → Андерсон» (87.5 → 74)
/// and «Достоевский → Островский» (85.7 → 73), without hurting prefix-
/// anchored real matches («достоевск → Достоевский» = 90).
///
/// `tokenMinRatio*` semantics: every query token must find a best match
/// among choice tokens; the weakest per-token best across the query drags
/// the final `min(...)` score down. Same shape as the previous LCS-based
/// scorer — the change is purely in `tokenMatchScore`.
///
/// `nonisolated enum` namespace pattern matches `SearchPreprocess` /
/// `LibraryLoader` in this codebase. Required because the project compiles
/// with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, and these functions
/// are called from `Task.detached` and `DispatchQueue.concurrentPerform`
/// workers.
nonisolated enum FuzzyScorer {
    /// Score cutoff used to separate real matches from noise. Empirically
    /// tuned against the spike4 corpus on the full 167k-author / 581k-book
    /// catalog: at 83 we keep all real typos and prefix matches («короли →
    /// королей» = 84.6, «Махабрахата → Махабхарата» = 90.9, «достоевск →
    /// Достоевский» = 90), and reject the previously-leaking false
    /// positives («сандерсо → Андерсон» = 74, «Достоевский → Островский» =
    /// 73, «Толстой → Толстиков» = 81.2).
    nonisolated static let SCORE_CUTOFF: Double = 83.0

    /// Damerau-Levenshtein distance, OSA variant: substitutions and
    /// adjacent transpositions count as 1 op. Standard 3-row rolling DP,
    /// O(m·n) time, O(n) space. The 3rd row (`prev2`) is needed for the
    /// transposition lookback.
    nonisolated static func damerauLevenshteinOSA(_ a: [UInt32], _ b: [UInt32]) -> Int {
        let m = a.count, n = b.count
        if m == 0 { return n }
        if n == 0 { return m }
        var prev2 = [Int](repeating: 0, count: n + 1)
        var prev = [Int](repeating: 0, count: n + 1)
        var cur = [Int](repeating: 0, count: n + 1)
        for j in 0...n { prev[j] = j }
        for i in 1...m {
            cur[0] = i
            let ai = a[i - 1]
            let aiPrev: UInt32 = i >= 2 ? a[i - 2] : 0
            for j in 1...n {
                let bj = b[j - 1]
                let cost = ai == bj ? 0 : 1
                var v = min(prev[j] + 1, cur[j - 1] + 1)         // del / ins
                v = min(v, prev[j - 1] + cost)                    // sub / match
                if i > 1, j > 1, ai == b[j - 2], aiPrev == bj {
                    v = min(v, prev2[j - 2] + 1)                  // transposition
                }
                cur[j] = v
            }
            let tmp = prev2
            prev2 = prev
            prev = cur
            cur = tmp
        }
        return prev[n]
    }

    /// Per-token score: sum-normalized DL ratio with first-character anchor.
    /// Returns 0..100.
    nonisolated static func tokenMatchScore(_ q: [UInt32], _ c: [UInt32]) -> Double {
        if q.isEmpty || c.isEmpty { return 0 }
        let d = damerauLevenshteinOSA(q, c)
        let total = q.count + c.count
        var score = Double(total - d) / Double(total) * 100.0
        if q[0] != c[0] { score *= 0.85 }
        return score
    }

    /// `token_min_ratio` semantics: every query-token must find a best
    /// match in some choice-token; the weakest per-token best across the
    /// query drags the final `min(...)` score down.
    nonisolated static func tokenMinRatio(qTokens: [[UInt32]], cTokens: [[UInt32]]) -> Double {
        if qTokens.isEmpty || cTokens.isEmpty { return 0 }
        var minScore = Double.infinity
        for qt in qTokens {
            var bestForQ = 0.0
            for ct in cTokens {
                let s = tokenMatchScore(qt, ct)
                if s > bestForQ { bestForQ = s }
                if bestForQ >= 100.0 { break }
            }
            if bestForQ < minScore { minScore = bestForQ }
            if minScore == 0 { return 0 }
        }
        return minScore == .infinity ? 0 : minScore
    }

    /// Production-pace `tokenMinRatio` with cutoff-pruning early exit:
    /// if any query-token's best match across choice tokens is below
    /// `cutoff`, the final `min(...)` will also be below `cutoff` —
    /// return 0 immediately. Sharply reduces work on multi-token queries
    /// against most candidates.
    nonisolated static func tokenMinRatioCut(qTokens: [[UInt32]], cTokens: [[UInt32]],
                                             cutoff: Double) -> Double {
        if qTokens.isEmpty || cTokens.isEmpty { return 0 }
        var minScore = Double.infinity
        for qt in qTokens {
            var bestForQ = 0.0
            for ct in cTokens {
                let s = tokenMatchScore(qt, ct)
                if s > bestForQ { bestForQ = s }
                if bestForQ >= 100.0 { break }
            }
            if bestForQ < cutoff { return 0 }     // pruning
            if bestForQ < minScore { minScore = bestForQ }
        }
        return minScore == .infinity ? 0 : minScore
    }
}
