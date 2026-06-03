import SwiftUI

// Temporary placeholder — replaced in Task 12
struct UsageView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var settings: AppSettings

    var body: some View {
        Text("Loading...")
            .frame(width: 280, height: 200)
    }
}
