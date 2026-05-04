import Foundation

/// Fuzzy-matching scorer for the search pipeline.
///
/// Port of `librarium-py/backend/app/search.py:token_min_ratio` semantics:
/// every query token must find a best match in some choice token; the
/// weakest per-token best across the query drags the final `min(...)`
/// score down. Score is the minimum of LCS-coverage-from-query and
/// symmetric `fuzz.ratio`, both expressed as 0..100 doubles.
///
/// This task introduces only the DP-based variant, which serves as the
/// reference (correctness-first, performance-naïve). Task 3 layers on a
/// bit-parallel LCS (Hyyrö'04) and pre-built query-pattern objects for
/// the production hot path.
///
/// `nonisolated enum` namespace pattern matches `SearchPreprocess` /
/// `NamePattern` / `LibraryLoader` in this codebase. Required because the
/// project compiles with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, and
/// these functions are called from `Task.detached` and
/// `DispatchQueue.concurrentPerform` workers.
nonisolated enum FuzzyScorer {
    /// SCORE cutoff used to separate real matches from noise.
    /// Empirically (librarium): real matches land at 80..100, noise ≤ 66.
    /// 75 sits in the gap. Tune via the corpus tests if behaviour drifts.
    static let SCORE_CUTOFF: Double = 75.0

    /// Standard 1D rolling-DP LCS. O(m·n) in time, O(min(m, n)) in memory.
    /// Used as the reference implementation for cross-checking the
    /// bit-parallel variant added in Task 3, and as the fallback for
    /// patterns longer than 64 codepoints.
    static func lcsLengthDP(_ a: [UInt32], _ b: [UInt32]) -> Int {
        let m = a.count, n = b.count
        if m == 0 || n == 0 { return 0 }
        let (s, t): ([UInt32], [UInt32]) = m < n ? (b, a) : (a, b)
        let cols = t.count + 1
        var prev = [Int](repeating: 0, count: cols)
        var cur  = [Int](repeating: 0, count: cols)
        for i in 1...s.count {
            let si = s[i - 1]
            for j in 1...t.count {
                if si == t[j - 1] {
                    cur[j] = prev[j - 1] + 1
                } else {
                    cur[j] = max(prev[j], cur[j - 1])
                }
            }
            swap(&prev, &cur)
        }
        return prev[t.count]
    }

    /// Per-token score: minimum of LCS-coverage-from-query and symmetric
    /// `fuzz.ratio`. Returns 0..100. Used by the non-pre-built `tokenMinRatio`
    /// for the DP corpus path; bit-parallel + pre-built variants come in
    /// Task 3.
    static func tokenMatchScore(_ q: [UInt32], _ c: [UInt32]) -> Double {
        if q.isEmpty || c.isEmpty { return 0 }
        let lcs = lcsLengthDP(q, c)
        let lcsCov = Double(lcs) / Double(q.count) * 100.0
        let ratio = Double(lcs) * 200.0 / Double(q.count + c.count)
        return min(lcsCov, ratio)
    }

    /// `token_min_ratio` semantics: every query-token must find a best
    /// match in some choice-token; the weakest per-token best across the
    /// query drags the final `min(...)` score down.
    static func tokenMinRatio(qTokens: [[UInt32]], cTokens: [[UInt32]]) -> Double {
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
}
