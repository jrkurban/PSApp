// Game.swift

import Foundation

// Bir oyunun tek bir sürümünü temsil eder
struct Edition: Identifiable {
    let id = UUID()
    var name: String
    var price: String
}

// Bir oyunun tamamını ve sürümlerini temsil eder
struct Game: Identifiable {
    let id: String // concept_id
    var name: String
    var editions: [Edition]
}

// Grafik için tek bir fiyat veri noktasını temsil eder
struct PriceDataPoint: Identifiable {
    let id = UUID()
    var date: Date
    var price: Double
}

// İndirimler sekmesinde gösterilecek bir öğeyi temsil eder
struct DiscountedGame: Identifiable {
    let id = UUID()
    var name: String
    var editionName: String
    var oldPrice: String
    var newPrice: String
}
