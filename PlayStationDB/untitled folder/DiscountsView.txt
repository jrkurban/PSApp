// DiscountsView.swift

import SwiftUI

struct DiscountsView: View {
    @State private var discounts: [DiscountedGame] = []
    @State private var isLoading = false
    @State private var statusMessage = "İndirimler kontrol ediliyor..."
    
    var body: some View {
        NavigationStack {
            VStack {
                if isLoading {
                    Spacer()
                    ProgressView()
                    Text("İndirimler aranıyor...")
                        .foregroundColor(.secondary)
                    Spacer()
                } else if discounts.isEmpty {
                    Spacer()
                    Image(systemName: "tag.slash")
                        .font(.system(size: 50))
                        .foregroundColor(.gray.opacity(0.5))
                    Text(statusMessage)
                        .padding()
                        .multilineTextAlignment(.center)
                    Spacer()
                } else {
                    List(discounts) { discount in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(discount.name)
                                .fontWeight(.bold)
                            Text(discount.editionName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            HStack {
                                Text("\(discount.oldPrice) TL")
                                    .strikethrough()
                                    .foregroundColor(.gray)
                                
                                Image(systemName: "arrow.right.circle.fill")
                                    .foregroundColor(.green)
                                
                                Text("\(discount.newPrice) TL")
                                    .fontWeight(.bold)
                                    .foregroundColor(.green)
                            }
                        }
                        .padding(.vertical, 5)
                    }
                }
            }
            .navigationTitle("Güncel İndirimler")
            // Pull-to-refresh (aşağı çekip yenileme) özelliği
            .refreshable {
                await loadDiscounts()
            }
            // Ekran ilk göründüğünde indirimleri yükle
            .onAppear {
                if discounts.isEmpty { // Sadece ilk açılışta yükle
                    Task {
                        await loadDiscounts()
                    }
                }
            }
        }
    }
    
    func loadDiscounts() async {
        isLoading = true
        do {
            let fetchedDiscounts = try await DatabaseManager.shared.fetchPriceDrops()
            if fetchedDiscounts.isEmpty {
                statusMessage = "Bugün yeni bir indirim bulunamadı."
            }
            discounts = fetchedDiscounts
        } catch {
            statusMessage = "İndirimler yüklenirken bir hata oluştu:\n\(error.localizedDescription)"
        }
        isLoading = false
    }
}

struct DiscountsView_Previews: PreviewProvider {
    static var previews: some View {
        DiscountsView()
    }
}
