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
    ///
    /// Naming: SCREAMING_SNAKE_CASE intentionally mirrors
    /// `librarium-py/backend/app/search.py:SEARCH_SCORE_CUTOFF` so the
    /// cross-port parity is grep-able. Swift API guidelines would prefer
    /// `scoreCutoff`; we keep parity over convention here.
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

    // MARK: - Bit-parallel LCS (Hyyrö 2004)
    //
    // Adapted from `rapidfuzz-cpp/rapidfuzz/distance/LCSseq_impl.hpp` (MIT,
    // © Max Bachmann). For patterns ≤64 codepoints — O(n) with a 4-op inner
    // loop on a single UInt64 register. Falls back to DP for longer patterns
    // (rare in our use case — words rarely exceed 30 chars).

    /// Direct bit-parallel LCS for ad-hoc pairs (used by `dpEqualsBP`
    /// cross-check tests, not by production scoring). Production scoring
    /// goes through `LcsPattern` + `lcsLengthPre` for the pre-built
    /// pattern-match-vector optimisation.
    static func lcsLengthBP(_ a: [UInt32], _ b: [UInt32]) -> Int {
        let m = a.count, n = b.count
        if m == 0 || n == 0 { return 0 }
        // Pattern is the shorter of the two so it fits in a single UInt64.
        let (pat, txt): ([UInt32], [UInt32]) = m <= n ? (a, b) : (b, a)
        if pat.count > 64 { return lcsLengthDP(a, b) }
        var pmv = [UInt32: UInt64](minimumCapacity: pat.count)
        for (i, c) in pat.enumerated() {
            pmv[c, default: 0] |= UInt64(1) << i
        }
        var S = UInt64.max
        for c in txt {
            guard let matches = pmv[c] else { continue }
            let u = S & matches
            S = (S &+ u) | (S &- u)
        }
        return (~S).nonzeroBitCount
    }

    // MARK: - Pre-built query pattern
    //
    // Bit-parallel сам по себе не даёт ускорения, потому что Swift `Dictionary`
    // аллоцируется на каждом вызове `lcsLength` (миллионы раз) и хеш-лукапы
    // съедают всю экономию от 4-операционного inner loop. Ключевая оптимизация:
    // pattern-match-vector для каждого query-токена строится ОДИН раз на
    // нажатие «Поиск» и переиспользуется на всех 581k+ кандидатах.
    // На спайке это даёт ~6× по сравнению с per-call PMV setup.

    /// Pre-built bit-parallel pattern for one query token. Stores the
    /// pattern-match-vector (`pmv`) so the inner LCS loop just reads it
    /// — no per-pair Dictionary construction.
    ///
    /// `nonisolated ... Sendable` because instances cross actor boundaries
    /// (read by `concurrentPerform` workers and across `Task.detached`).
    /// All fields are `let` — fully immutable post-init — so Sendable is
    /// safe by construction.
    nonisolated struct LcsPattern: Sendable {
        let m: Int
        /// Empty for `isLong == true` patterns (those use `fallback` + DP).
        let pmv: [UInt32: UInt64]
        let isLong: Bool
        /// Original raw scalars — used only when `isLong` to feed DP fallback.
        let fallback: [UInt32]

        init(_ pat: [UInt32]) {
            self.m = pat.count
            self.fallback = pat
            if pat.count > 64 {
                self.pmv = [:]
                self.isLong = true
            } else {
                var pmv = [UInt32: UInt64](minimumCapacity: pat.count)
                for (i, c) in pat.enumerated() {
                    pmv[c, default: 0] |= UInt64(1) << i
                }
                self.pmv = pmv
                self.isLong = false
            }
        }
    }

    /// Bit-parallel LCS using a pre-built `LcsPattern`. Falls back to DP
    /// for patterns longer than 64 codepoints.
    static func lcsLengthPre(_ p: LcsPattern, _ text: [UInt32]) -> Int {
        if p.m == 0 || text.isEmpty { return 0 }
        if p.isLong { return lcsLengthDP(p.fallback, text) }
        var S = UInt64.max
        for c in text {
            guard let matches = p.pmv[c] else { continue }
            let u = S & matches
            S = (S &+ u) | (S &- u)
        }
        return (~S).nonzeroBitCount
    }

    /// Per-token match score using a pre-built `LcsPattern`. Same scoring
    /// formula as `tokenMatchScore` (min of LCS-coverage and `fuzz.ratio`).
    static func tokenMatchScorePre(_ p: LcsPattern, _ c: [UInt32]) -> Double {
        if p.m == 0 || c.isEmpty { return 0 }
        let lcs = lcsLengthPre(p, c)
        let lcsCov = Double(lcs) / Double(p.m) * 100.0
        let ratio = Double(lcs) * 200.0 / Double(p.m + c.count)
        return min(lcsCov, ratio)
    }

    /// Production-pace `tokenMinRatio`: query tokens come pre-built as
    /// `[LcsPattern]` (one PMV per token, computed once per search click).
    /// Adds cutoff-pruning: if any query-token's best match across choice
    /// tokens is below `cutoff`, the final `min(...)` will also be below
    /// `cutoff` — return 0 immediately. Sharply reduces work on multi-token
    /// queries against most candidates.
    static func tokenMinRatioPre(qPatterns: [LcsPattern], cTokens: [[UInt32]],
                                 cutoff: Double) -> Double {
        if qPatterns.isEmpty || cTokens.isEmpty { return 0 }
        var minScore = Double.infinity
        for qp in qPatterns {
            var bestForQ = 0.0
            for ct in cTokens {
                let s = tokenMatchScorePre(qp, ct)
                if s > bestForQ { bestForQ = s }
                if bestForQ >= 100.0 { break }
            }
            if bestForQ < cutoff { return 0 }     // pruning
            if bestForQ < minScore { minScore = bestForQ }
        }
        return minScore == .infinity ? 0 : minScore
    }
}
