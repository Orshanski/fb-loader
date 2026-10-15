import Testing
@testable import FB_Loader

@Suite("TokenStore")
struct TokenStoreTests {
    private let a: [[UInt32]] = [[1, 2, 3], [4]]
    private let b: [[UInt32]] = []
    private let c: [[UInt32]] = [[5, 6], [7, 8, 9], [10]]

    private func store() -> TokenStore {
        var s = TokenStore()
        s.append(a); s.append(b); s.append(c)
        return s
    }

    @Test("ключи читаются обратно, включая пустой")
    func roundTrip() {
        let s = store()
        #expect(s.count == 3)
        #expect(s[0] == a)
        #expect(s[1] == b)
        #expect(s[2] == c)
    }

    @Test("слова ключа через view совпадают с исходными")
    func viewTokens() {
        let s = store()
        let got: [[[UInt32]]] = s.withView { view in
            (0..<s.count).map { i in
                var out: [UnsafeBufferPointer<UInt32>] = []
                view.appendTokens(of: i, to: &out)
                return out.map(Array.init)
            }
        }
        #expect(got == [a, b, c])
    }

    @Test("токенизация прямо в хранилище совпадает с SearchPreprocess.tokens", arguments: [
        "Толстой, Лев Николаевич", "Ёлкин-Палкин", "  ", "", "Київ ŁÓDŹ école 2024",
        "Война и мир!!!", "Gödel, Escher, Bach", "а", "Сандерсон: Мстители (т. 3)",
        "a😀b", "𐐀𐐁 x", "раз,— два…три"])
    func tokenizeParity(_ raw: String) {
        var s = TokenStore()
        s.appendTokenized(raw)
        #expect(s[0] == SearchPreprocess.tokens(raw))
    }

    @Test("пустое хранилище")
    func empty() {
        let s = TokenStore()
        #expect(s.count == 0)
        s.withView { _ in }
    }

    @Test("скорер на указателях даёт то же, что на массивах")
    func scorerParity() {
        let q = SearchPreprocess.tokens("толстой война")
        let cand = SearchPreprocess.tokens("Война и мир Толстой Лев")
        var s = TokenStore()
        s.append(q); s.append(cand)
        let viaArrays = FuzzyScorer.tokenMinRatioCut(qTokens: q, cTokens: cand, cutoff: 50)
        let viaView: Double = s.withView { view in
            var qt: [UnsafeBufferPointer<UInt32>] = [], ct: [UnsafeBufferPointer<UInt32>] = []
            view.appendTokens(of: 0, to: &qt)
            view.appendTokens(of: 1, to: &ct)
            return FuzzyScorer.tokenMinRatioCut(qTokens: qt, cTokens: ct, cutoff: 50)
        }
        #expect(viaArrays == viaView)
        #expect(viaArrays == 100)
    }
}
