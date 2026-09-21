import SwiftUI
import SpecKit

/// M0 placeholder: proves the app target links PassportKit and reads the spec as data.
/// The real Home screen (document card, Choose Photo, tips) is M5.
struct HomeView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: "person.crop.rectangle")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Scaffolded at M0")
                    .font(.headline)
                Text("Screens arrive at M5.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("Passport Photo")
        }
    }
}

#Preview {
    HomeView()
}
