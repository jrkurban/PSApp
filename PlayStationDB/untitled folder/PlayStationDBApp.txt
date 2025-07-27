// PlayStationDBApp.swift

import SwiftUI
import BackgroundTasks
import UserNotifications

@main
struct PlayStationDBApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        registerBackgroundTasks()
        requestNotificationPermission()
    }
    
    var body: some Scene {
        WindowGroup {
            // UYGULAMANIN BAŞLANGIÇ EKRANI ARTIK MAINVIEW
            MainView()
        }
        .onChange(of: scenePhase) { newScenePhase in
            if newScenePhase == .background {
                print("Uygulama arka plana geçti. Görev planlanıyor...")
                DatabaseManager.shared.scheduleAppRefresh()
            }
        }
    }
    
    private func requestNotificationPermission() {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
                if granted {
                    print("Bildirim izni verildi.")
                } else if let error = error {
                    print("Bildirim izni alınırken hata oluştu: \(error.localizedDescription)")
                }
            }
        }
    
    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: DatabaseManager.shared.backgroundAppRefreshTaskId, using: nil) { task in
            print("Arka plan görevi çalıştırılıyor!")
            
            // Bir sonraki çalıştırma için görevi yeniden planla
            DatabaseManager.shared.scheduleAppRefresh()
            
            // Veritabanını indirme işlemini başlat
            handleAppRefresh(task: task as! BGAppRefreshTask)
        }
    }
    
    private func handleAppRefresh(task: BGAppRefreshTask) {
        // Görevin süresi dolarsa işlemi iptal et
        task.expirationHandler = {
            print("Arka plan görevi zaman aşımına uğradı.")
            task.setTaskCompleted(success: false)
        }

        print("Arka plan güncelleme işlemi başlatılıyor...")

        Task {
            do {
                // 1. Veritabanını indir/güncelle
                try await DatabaseManager.shared.downloadDatabase()
                print("Arka plan: Veritabanı başarıyla güncellendi.")
                
                // 2. İndirimleri kontrol et
                let priceDrops = try await DatabaseManager.shared.fetchPriceDrops()
                print("Arka plan: \(priceDrops.count) adet indirim bulundu.")
                
                // 3. Eğer indirim varsa, bildirim gönder
                if !priceDrops.isEmpty {
                    DatabaseManager.shared.sendDiscountNotification(count: priceDrops.count)
                }
                
                // 4. Görevi başarılı olarak tamamla
                task.setTaskCompleted(success: true)
                
            } catch {
                print("Arka plan güncelleme ve kontrol işlemi başarısız: \(error)")
                task.setTaskCompleted(success: false)
            }
        }
    }
}
