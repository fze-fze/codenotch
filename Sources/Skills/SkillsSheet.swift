import SwiftUI

enum SkillsSheet: Identifiable, Hashable {
    case library(String)
    case agent(String)

    var id: String {
        switch self {
        case .library(let id): return "library:\(id)"
        case .agent(let id):   return "agent:\(id)"
        }
    }
}
