// Copied from Kaset (github.com/sozercan/kaset @ 83513f6), MIT License, see LICENSE.txt in this folder.

import Foundation

/// Response from the YouTube Music home/browse endpoint.
struct HomeResponse {
    let sections: [HomeSection]

    /// Whether the home response is empty.
    var isEmpty: Bool {
        self.sections.isEmpty || self.sections.allSatisfy(\.items.isEmpty)
    }

    static let empty = HomeResponse(sections: [])
}
