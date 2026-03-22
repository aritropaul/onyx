import Foundation

/// Simple fuzzy matching: all characters in query must appear in order in target.
func fuzzyMatch(query: String, target: String) -> Bool {
    let query = query.lowercased()
    let target = target.lowercased()

    var queryIndex = query.startIndex
    var targetIndex = target.startIndex

    while queryIndex < query.endIndex && targetIndex < target.endIndex {
        if query[queryIndex] == target[targetIndex] {
            queryIndex = query.index(after: queryIndex)
        }
        targetIndex = target.index(after: targetIndex)
    }

    return queryIndex == query.endIndex
}

/// Fuzzy match with score (higher = better match).
func fuzzyScore(query: String, target: String) -> Int {
    let query = query.lowercased()
    let target = target.lowercased()

    var score = 0
    var queryIndex = query.startIndex
    var targetIndex = target.startIndex
    var consecutiveBonus = 0

    while queryIndex < query.endIndex && targetIndex < target.endIndex {
        if query[queryIndex] == target[targetIndex] {
            score += 1 + consecutiveBonus
            consecutiveBonus += 1
            queryIndex = query.index(after: queryIndex)

            // Bonus for matching at start of word
            if targetIndex == target.startIndex ||
               target[target.index(before: targetIndex)] == " " ||
               target[target.index(before: targetIndex)] == "/" {
                score += 3
            }
        } else {
            consecutiveBonus = 0
        }
        targetIndex = target.index(after: targetIndex)
    }

    // Penalize if not all query chars matched
    if queryIndex != query.endIndex {
        return 0
    }

    return score
}
