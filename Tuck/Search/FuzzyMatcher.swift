import Foundation

/// A namespace for fuzzy subsequence matching, used to rank menu bar items in
/// search results.
nonisolated enum FuzzyMatcher {
    /// Scores `candidate` against `query`, treating the query as a case-insensitive
    /// subsequence of the candidate's characters. Matching is performed greedily,
    /// left to right.
    ///
    /// Returns `nil` if `query` is not a subsequence of `candidate`. Otherwise,
    /// higher scores indicate a better match: a prefix match, matches that fall on
    /// word boundaries, and consecutively matched characters are all rewarded, while
    /// longer candidates are penalized.
    static func score(query: String, candidate: String) -> Int? {
        let queryChars = Array(query.lowercased())
        let candidateChars = Array(candidate)
        let candidateLowerChars = Array(candidate.lowercased())

        guard candidateLowerChars.count == candidateChars.count else {
            // Case-folding changed the character count (rare, non-ASCII edge case);
            // fall back to a plain case-insensitive containment check.
            return candidate.range(of: query, options: .caseInsensitive) != nil ? -candidateChars.count : nil
        }

        var matchedIndices: [Int] = []
        var candidateIndex = 0
        for queryChar in queryChars {
            var found = false
            while candidateIndex < candidateLowerChars.count {
                if candidateLowerChars[candidateIndex] == queryChar {
                    matchedIndices.append(candidateIndex)
                    candidateIndex += 1
                    found = true
                    break
                }
                candidateIndex += 1
            }
            if !found { return nil }
        }

        var score = -candidateChars.count

        if candidateLowerChars.starts(with: queryChars) {
            score += 100
        }

        let separators: Set<Character> = [" ", "-", "_", "."]
        func isWordBoundary(_ index: Int) -> Bool {
            if index == 0 { return true }
            let previous = candidateChars[index - 1]
            if separators.contains(previous) { return true }
            return previous.isLowercase && candidateChars[index].isUppercase
        }

        for index in matchedIndices where isWordBoundary(index) {
            score += 30
        }

        for i in 1..<matchedIndices.count where matchedIndices[i] == matchedIndices[i - 1] + 1 {
            score += 10
        }

        return score
    }
}
