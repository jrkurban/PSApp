// DatabaseManager.swift

import Foundation
import GRDB
import BackgroundTasks
import UserNotifications

// Bu fonksiyonu global olarak tanımlayarak hem DatabaseManager hem de diğer View'lardan erişilebilir yapıyoruz.
func parsePrice(_ price_str: String?) -> Double? {
    guard let price_str = price_str else { return nil }
    let priceStr = price_str.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    
    if priceStr.contains("ücretsiz") { return 0.0 }
    
    // Türk para formatını (1.749,00) standart float formatına (1749.00) çevir
    let cleanedStr = priceStr.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
    return Double(cleanedStr)
}


class DatabaseManager: ObservableObject {
    static let shared = DatabaseManager()
    
    // ⚠️⚠️⚠️ BU URL'Yİ KENDİ GITHUB REPOSITORY'NİZDEKİ "RAW" URL İLE DEĞİŞTİRİN! ⚠️⚠️⚠️
    private let dbURL = URL(string: "https://raw.githubusercontent.com/jrkurban/playstation-scraper/main/playstation_games.db")!
    
    // ⚠️⚠️⚠️ BU KİMLİĞİ INFO.PLIST'E GİRDİĞİNİZ DEĞERLE AYNI YAPIN! ⚠️⚠️⚠️
    let backgroundAppRefreshTaskId = "com.batuhanalpkurban.PlayStationDB.appRefresh" // KENDİ BUNDLE ID'NİZLE GÜNCELLEYİN

    private var dbQueue: DatabaseQueue?
    
    var databasePath: String {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsDirectory.appendingPathComponent("playstation_games.db").path
    }
    
    init() {
        do {
            dbQueue = try DatabaseQueue(path: databasePath)
        } catch {
            print("Veritabanı açılamadı: \(error)")
        }
    }
    func fetchPriceDrops() async throws -> [DiscountedGame] {
            guard let dbQueue = dbQueue else { return [] }

            // En son iki tabloyu al
            let tables = try await findLatestTables(count: 2)
            guard tables.count == 2 else {
                print("Karşılaştırma için yeterli tablo (en az 2) bulunamadı.")
                return [] // Karşılaştırma yapılamazsa boş dizi döndür
            }
            
            let oldTable = tables[0] // Daha eski olan
            let newTable = tables[1] // En yeni olan
            
            print("İndirimler için karşılaştırılıyor: '\(oldTable)' vs '\(newTable)'")

            let oldData = try await fetchAllGamesAsDict(from: oldTable)
            let newData = try await fetchAllGamesAsDict(from: newTable)
            
            var priceDrops: [DiscountedGame] = []

            // Yeni verilerdeki her oyunu, eski verilerle karşılaştır
            for (conceptId, newGameRow) in newData {
                if let oldGameRow = oldData[conceptId] {
                    // Her bir oyunun 5 sürümünü de kontrol et
                    for i in 1...5 {
                        let fiyatCol = "fiyat_\(i)"
                        let surumCol = "surum_adi_\(i)"

                        guard let oldPriceStr: String = oldGameRow[fiyatCol],
                              let newPriceStr: String = newGameRow[fiyatCol] else {
                            continue
                        }

                        let oldPriceVal = parsePrice(oldPriceStr)
                        let newPriceVal = parsePrice(newPriceStr)
                        
                        if let oldVal = oldPriceVal, let newVal = newPriceVal, newVal < oldVal {
                            let editionName = newGameRow[surumCol] as? String ?? "Standart Sürüm"
                            let gameName = newGameRow["name"] as? String ?? "Bilinmeyen Oyun"
                            
                            priceDrops.append(DiscountedGame(
                                name: gameName,
                                editionName: editionName,
                                oldPrice: oldPriceStr,
                                newPrice: newPriceStr
                            ))
                        }
                    }
                }
            }
            return priceDrops
        }
        
        // Yardımcı Fonksiyon: Veritabanındaki tüm oyunları sözlük olarak çeker
        private func fetchAllGamesAsDict(from tableName: String) async throws -> [String: Row] {
            guard let dbQueue = dbQueue else { return [:] }
            return try await dbQueue.read { db in
                let rows = try Row.fetchAll(db, sql: "SELECT * FROM \"\(tableName)\"")
                return Dictionary(uniqueKeysWithValues: rows.map { ($0["concept_id"], $0) })
            }
        }
        
        // Yardımcı Fonksiyon: En son 'count' adet tabloyu bulur (eskiden yeniye sıralı)
        private func findLatestTables(count: Int) async throws -> [String] {
            guard let dbQueue = dbQueue else { return [] }
            
            let tables: [String] = try await dbQueue.read { db in
                return try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'games_%'")
            }
            
            let sortedTables = tables.compactMap { name -> (Date, String)? in
                let formatter = DateFormatter()
                formatter.dateFormat = "'games'_dd_MM_yyyy_HH_mm"
                if let date = formatter.date(from: name) {
                    return (date, name)
                }
                return nil
            }.sorted(by: { $0.0 < $1.0 }) // Eskiden yeniye sırala
            
            // En son 'count' adet tabloyu al
            let latestTables = sortedTables.suffix(count).map { $0.1 }
            return Array(latestTables)
        }
    
    func downloadDatabase() async throws {
        print("Veritabanı indiriliyor...")
        let (data, response) = try await URLSession.shared.data(from: dbURL)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        try data.write(to: URL(fileURLWithPath: databasePath), options: .atomic)
        print("Veritabanı başarıyla indirildi/güncellendi.")
        dbQueue = try DatabaseQueue(path: databasePath)
    }
    
    private func findLatestTable() async throws -> String {
        guard let dbQueue = dbQueue else {
            throw NSError(domain: "DBError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Veritabanı bağlantısı yok."])
        }
        
        let tables: [String] = try await dbQueue.read { db in
            return try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'games_%'")
        }
        
        let sortedTables = tables.compactMap { name -> (Date, String)? in
            let formatter = DateFormatter()
            formatter.dateFormat = "'games'_dd_MM_yyyy_HH_mm"
            if let date = formatter.date(from: name) {
                return (date, name)
            }
            return nil
        }.sorted(by: { $0.0 > $1.0 })
        
        guard let latestTable = sortedTables.first?.1 else {
            throw NSError(domain: "DBError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Geçerli oyun tablosu bulunamadı."])
        }
        
        return latestTable
    }

    func searchGames(searchTerm: String) async throws -> [Game] {
        guard let dbQueue = dbQueue else { return [] }

        let latestTable = try await findLatestTable()
        
        let rows = try await dbQueue.read { db -> [Row] in
            let query = "SELECT * FROM \"\(latestTable)\" WHERE name LIKE ?"
            return try Row.fetchAll(db, sql: query, arguments: ["%\(searchTerm)%"])
        }
        
        var games: [Game] = []
        for row in rows {
            var editions: [Edition] = []
            for i in 1...5 {
                if let editionName: String = row["surum_adi_\(i)"], !editionName.isEmpty {
                    let price: String = row["fiyat_\(i)"] ?? "N/A"
                    editions.append(Edition(name: editionName, price: price))
                }
            }
            
            if !editions.isEmpty {
                games.append(Game(
                    id: row["concept_id"],
                    name: row["name"],
                    editions: editions
                ))
            }
        }
        return games
    }
    
    func fetchPriceHistory(for conceptId: String, editionIndex: Int) async throws -> [PriceDataPoint] {
        guard let dbQueue = dbQueue else { return [] }

        let allTables = try await dbQueue.read { db -> [String] in
            return try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'games_%' ORDER BY name ASC")
        }

        var priceHistory: [PriceDataPoint] = []
        let fiyatColumn = "fiyat_\(editionIndex)"
        let formatter = DateFormatter()
        formatter.dateFormat = "'games'_dd_MM_yyyy_HH_mm"

        for tableName in allTables {
            guard let date = formatter.date(from: tableName) else { continue }
            
            let row = try await dbQueue.read { db -> Row? in
                let query = "SELECT \"\(fiyatColumn)\" FROM \"\(tableName)\" WHERE concept_id = ?"
                return try Row.fetchOne(db, sql: query, arguments: [conceptId])
            }

            if let priceString: String = row?[fiyatColumn], let priceValue = parsePrice(priceString) {
                priceHistory.append(PriceDataPoint(date: date, price: priceValue))
            }
        }
        
        var uniqueHistory: [Date: PriceDataPoint] = [:]
        for point in priceHistory {
            let dayStart = Calendar.current.startOfDay(for: point.date)
            if let existing = uniqueHistory[dayStart] {
                if point.date > existing.date {
                    uniqueHistory[dayStart] = point
                }
            } else {
                uniqueHistory[dayStart] = point
            }
        }
        
        return Array(uniqueHistory.values).sorted(by: { $0.date < $1.date })
    }
    
    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundAppRefreshTaskId)
        
        var components = DateComponents()
        components.hour = 9
        components.minute = 0
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        request.earliestBeginDate = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("Arka plan görevi bir sonraki gün için planlandı.")
        } catch {
            print("Arka plan görevi planlanamadı: \(error)")
        }
    }
    func sendDiscountNotification(count: Int) {
        let content = UNMutableNotificationContent()
        content.title = "PlayStation Store İndirimleri!"
        content.body = "\(count) yeni oyunda veya sürümde indirim tespit edildi. Göz atmak için dokunun!"
        content.sound = UNNotificationSound.default
        content.badge = NSNumber(value: count)

        // Bildirimi 1 saniye sonra tetikle
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Bildirim gönderilirken hata oluştu: \(error.localizedDescription)")
            } else {
                print("\(count) indirim için bildirim başarıyla gönderildi.")
            }
        }
    }
}
