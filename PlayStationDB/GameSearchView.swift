// GameSearchView.swift (Eski ContentView.swift)

import SwiftUI
import Combine

struct GameSearchView: View { // İsim değişikliği
    @StateObject private var dbManager = DatabaseManager.shared
    
    @State private var searchTerm = ""
    @State private var games: [Game] = []
    @State private var statusMessage = "Veritabanını indirmek için 🔄 butonuna basın."
    @State private var isLoading = false
    
    @State private var debounceTimer: AnyCancellable?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .padding(.leading)
                    
                    Spacer()
                    
                    if isLoading {
                        ProgressView().padding(.trailing)
                    } else {
                        Button(action: { Task { await updateDatabase() } }) {
                            Image(systemName: "arrow.clockwise.circle")
                                .font(.title3)
                        }.padding(.trailing)
                    }
                }
                .frame(height: 30)
                .padding(.bottom, 5)

                List(games) { game in
                    NavigationLink(destination: GameDetailView(game: game)) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(game.name)
                                .font(.headline)
                            
                            if let firstEdition = game.editions.first {
                                Text("\(firstEdition.name) - \(firstEdition.price) TL")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 5)
                    }
                }
                .listStyle(.insetGrouped)
                .searchable(text: $searchTerm, prompt: "Oyun Adı Ara...")
                .onChange(of: searchTerm) { newSearchTerm in
                    debounceTimer?.cancel()
                    debounceTimer = Just(newSearchTerm)
                        .delay(for: .milliseconds(500), scheduler: DispatchQueue.main)
                        .sink { term in
                            Task { await performSearch(for: term) }
                        }
                }
            }
            .navigationTitle("Oyunlar") // Başlığı "Oyunlar" olarak değiştirdik
            .onAppear {
                if !FileManager.default.fileExists(atPath: dbManager.databasePath) {
                    Task { await updateDatabase() }
                } else {
                    statusMessage = "Yerel veritabanı bulundu. Güncelleyebilirsiniz."
                }
            }
        }
    }
    
    func performSearch(for term: String) async {
        guard !term.isEmpty else {
            games = []
            return
        }
        
        isLoading = true
        do {
            games = try await dbManager.searchGames(searchTerm: term)
        } catch {
            statusMessage = "Arama hatası: \(error.localizedDescription)"
        }
        isLoading = false
    }
    
    func updateDatabase() async {
        isLoading = true
        statusMessage = "Veritabanı indiriliyor..."
        do {
            try await dbManager.downloadDatabase()
            statusMessage = "Veritabanı başarıyla güncellendi!"
        } catch {
            statusMessage = "İndirme başarısız: \(error.localizedDescription)"
        }
        isLoading = false
    }
}

// İsim değişikliği
struct GameSearchView_Previews: PreviewProvider {
    static var previews: some View {
        GameSearchView()
    }
}
