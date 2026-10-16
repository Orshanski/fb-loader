import Foundation

/// Score per token pair: `(|q|+|c| - dl_osa(q,c)) / (|q|+|c|) * 100` (Damerau-Levenshtein, OSA variant).
/// If `q[0] != c[0]` the score is multiplied by 0.85: this kills cross-prefix false positives like
/// «сандерсо → Андерсон» (87.5 → 74) without hurting «достоевск → Достоевский» (90).
///
/// `tokenMinRatio*`: every query token must find its best match among the choice tokens;
/// the weakest of those bests is the final score.
nonisolated enum FuzzyScorer {
    /// Tuned on the full 167k-author catalog: 83 keeps typos and prefixes («короли → королей» = 84.6)
    /// and rejects false positives («Толстой → Толстиков» = 81.2, «сандерсо → Андерсон» = 74).
    nonisolated static let scoreCutoff: Double = 83.0

    /// OSA variant: substitutions and adjacent transpositions cost 1. Rolling 3-row DP; `prev2` serves
    /// the transposition lookback.
    nonisolated static func damerauLevenshteinOSA(_ a: [UInt32], _ b: [UInt32]) -> Int {
        let a = a.map(TokenStore.char), b = b.map(TokenStore.char)
        return a.withUnsafeBufferPointer { a in b.withUnsafeBufferPointer { b in damerauLevenshteinOSA(a, b) } }
    }

    nonisolated static func damerauLevenshteinOSA(_ a: SearchToken,
                                                  _ b: SearchToken) -> Int {
        let m = a.count
        let n = b.count
        if m == 0 { return n }
        if n == 0 { return m }
        var prev2 = [Int](repeating: 0, count: n + 1)
        var prev = [Int](repeating: 0, count: n + 1)
        var cur = [Int](repeating: 0, count: n + 1)
        for j in 0...n { prev[j] = j }
        for i in 1...m {
            cur[0] = i
            let ai = a[i - 1]
            let aiPrev: SearchChar = i >= 2 ? a[i - 2] : 0
            for j in 1...n {
                let bj = b[j - 1]
                let cost = ai == bj ? 0 : 1
                var v = min(prev[j] + 1, cur[j - 1] + 1)
                v = min(v, prev[j - 1] + cost)
                if i > 1, j > 1, ai == b[j - 2], aiPrev == bj {
                    v = min(v, prev2[j - 2] + 1)
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

    nonisolated static func tokenMatchScore(_ q: [UInt32], _ c: [UInt32]) -> Double {
        let q = q.map(TokenStore.char), c = c.map(TokenStore.char)
        return q.withUnsafeBufferPointer { q in c.withUnsafeBufferPointer { c in tokenMatchScore(q, c) } }
    }

    nonisolated static func tokenMatchScore(_ q: SearchToken,
                                            _ c: SearchToken) -> Double {
        if q.isEmpty || c.isEmpty { return 0 }
        let d = damerauLevenshteinOSA(q, c)
        let total = q.count + c.count
        var score = Double(total - d) / Double(total) * 100.0
        if q[0] != c[0] { score *= 0.85 }
        return score
    }

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

    /// Like `tokenMinRatio`, but returns 0 as soon as one query token's best match is below `cutoff`
    /// (the final min would be too).
    nonisolated static func tokenMinRatioCut(qTokens: [[UInt32]], cTokens: [[UInt32]],
                                             cutoff: Double) -> Double {
        var store = TokenStore()
        store.append(qTokens)
        store.append(cTokens)
        return store.withView { view in
            var q: [SearchToken] = [], c: [SearchToken] = []
            view.appendTokens(of: 0, to: &q)
            view.appendTokens(of: 1, to: &c)
            return tokenMinRatioCut(qTokens: q, cTokens: c, cutoff: cutoff)
        }
    }

    nonisolated static func tokenMinRatioCut(qTokens: [SearchToken],
                                             cTokens: [SearchToken],
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
            if bestForQ < cutoff { return 0 }
            if bestForQ < minScore { minScore = bestForQ }
        }
        return minScore == .infinity ? 0 : minScore
    }
}
