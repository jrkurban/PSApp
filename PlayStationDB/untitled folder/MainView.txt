//
//  MainView.swift
//  PlayStationDB
//
//  Created by Batuhan Alp Kurban on 21/07/2025.
//
// MainView.swift

import SwiftUI

struct MainView: View {
    var body: some View {
        // Uygulamanın ana sekme yapısını oluşturur
        TabView {
            // Birinci Sekme: Oyun Arama
            GameSearchView()
                .tabItem {
                    Label("Oyunlar", systemImage: "gamecontroller.fill")
                }
            
            // İkinci Sekme: İndirimler
            DiscountsView()
                .tabItem {
                    Label("İndirimler", systemImage: "tag.fill")
                }
        }
    }
}

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        MainView()
    }
}
