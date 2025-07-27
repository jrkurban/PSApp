import SwiftUI
import Charts

struct GameDetailView: View {
    let game: Game
    
    // State Değişkenleri
    @State private var selectedEditionIndex: Int = 1
    @State private var priceHistory: [PriceDataPoint] = []
    @State private var isLoading = true
    @State private var statusMessage = ""
    @State private var selectedTimeRange: TimeRange = .all
    
    // --- YENİ: İnteraktif Grafik için State'ler ---
    @State private var selectedDate: Date? = nil
    
    // Seçilen noktaya ait fiyatı hesaplayan yardımcı değişken
    private var selectedPrice: Double? {
        guard let selectedDate = selectedDate,
              let point = filteredPriceHistory.first(where: {
                  // Seçilen tarihe en yakın noktayı bul
                  Calendar.current.isDate($0.date, inSameDayAs: selectedDate)
              }) else {
            return nil
        }
        return point.price
    }
    
    enum TimeRange: String, CaseIterable, Identifiable {
        case week = "Haftalık"
        case month = "Aylık"
        case all = "Tümü"
        var id: Self { self }
    }

    var body: some View {
        VStack {
            // Sürüm Seçici (Picker)
            if game.editions.count > 1 {
                Picker("Sürüm Seç", selection: $selectedEditionIndex) {
                    ForEach(0..<game.editions.count, id: \.self) { index in
                        Text(game.editions[index].name).tag(index + 1)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                .onChange(of: selectedEditionIndex) { _ in
                    Task { await loadPriceHistory() }
                }
            }
            
            // Yükleme ve Durum Görünümleri
            if isLoading {
                ProgressView("Grafik yükleniyor...")
                    .frame(minHeight: 300)
            } else if !priceHistory.isEmpty {
                
                // Zaman Aralığı Seçici
                Picker("Zaman Aralığı", selection: $selectedTimeRange) {
                    ForEach(TimeRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                // --- GÜNCELLENMİŞ GRAFİK ---
                Chart {
                    ForEach(filteredPriceHistory) { point in
                        LineMark(
                            x: .value("Tarih", point.date, unit: .day),
                            y: .value("Fiyat (TL)", point.price)
                        )
                        .foregroundStyle(.blue.gradient)
                        .interpolationMethod(.cardinal) // Çizgiyi yumuşatır
                        
                        PointMark(
                           x: .value("Tarih", point.date, unit: .day),
                           y: .value("Fiyat (TL)", point.price)
                        )
                        .foregroundStyle(.blue)
                    }
                    
                    // Kalıcı Min/Max Fiyat Etiketleri
                    if let (minPoint, maxPoint) = findMinMaxPoints() {
                        // En Düşük Fiyat Noktası
                        PointMark(x: .value("Tarih", minPoint.date), y: .value("Fiyat", minPoint.price))
                            .foregroundStyle(.green)
                            .annotation(position: .bottom, alignment: .center) {
                                Text("\(minPoint.price, specifier: "%.2f") ₺")
                                    .font(.caption).bold()
                                    .padding(4).background(Color.green.opacity(0.2)).cornerRadius(4)
                            }
                        
                        // En Yüksek Fiyat Noktası
                        PointMark(x: .value("Tarih", maxPoint.date), y: .value("Fiyat", maxPoint.price))
                            .foregroundStyle(.red)
                            .annotation(position: .top, alignment: .center) {
                                Text("\(maxPoint.price, specifier: "%.2f") ₺")
                                    .font(.caption).bold()
                                    .padding(4).background(Color.red.opacity(0.2)).cornerRadius(4)
                            }
                    }
                    
                    // Kullanıcı etkileşimi için dikey çizgi ve etiket
                    if let selectedDate {
                        RuleMark(x: .value("Seçilen Tarih", selectedDate))
                            .foregroundStyle(Color.gray.opacity(0.5))
                            .offset(yStart: -10)
                            .zIndex(-1)
                            .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                if let selectedPrice {
                                    VStack(spacing: 4) {
                                        Text(selectedDate, format: .dateTime.day().month())
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text("\(selectedPrice, specifier: "%.2f") TL")
                                            .fontWeight(.bold)
                                            .foregroundColor(.primary)
                                    }
                                    .padding(8)
                                    .background(Color(uiColor: .systemGray6))
                                    .cornerRadius(8)
                                    .shadow(radius: 2)
                                }
                            }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) {
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .chartYScale(domain: 0...(yAxisMax * 1.15))
                .frame(height: 300)
                .padding()
                // Kullanıcının grafiğe dokunmasını ve kaydırmasını algılamak için
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        let location = value.location
                                        // Parmağın x koordinatından grafikteki tarihi bul
                                        if let date: Date = proxy.value(atX: location.x) {
                                            selectedDate = date
                                        }
                                    }
                                    .onEnded { _ in
                                        // Parmağını çektiğinde etiketi gizle
                                        selectedDate = nil
                                    }
                            )
                    }
                }

            } else {
                Text(statusMessage)
                    .frame(minHeight: 300)
            }
            
            Spacer()
        }
        .navigationTitle(game.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if game.editions.count == 1 { selectedEditionIndex = 1 }
            Task { await loadPriceHistory() }
        }
    }
    
    // MARK: - Helper Functions
    
    private var filteredPriceHistory: [PriceDataPoint] {
        guard !priceHistory.isEmpty else { return [] }
        
        let now = Date()
        var startDate: Date?
        
        switch selectedTimeRange {
        case .week:
            startDate = Calendar.current.date(byAdding: .day, value: -7, to: now)
        case .month:
            startDate = Calendar.current.date(byAdding: .month, value: -1, to: now)
        case .all:
            startDate = nil
        }
        
        if let startDate = startDate {
            return priceHistory.filter { $0.date >= startDate }
        }
        return priceHistory
    }
    
    private var yAxisMax: Double {
        filteredPriceHistory.map { $0.price }.max() ?? 100.0
    }
    
    private func findMinMaxPoints() -> (min: PriceDataPoint, max: PriceDataPoint)? {
        guard let minPoint = filteredPriceHistory.min(by: { $0.price < $1.price }),
              let maxPoint = filteredPriceHistory.max(by: { $0.price < $1.price }) else {
            return nil
        }
        // Eğer min ve max aynı noktaysa, sadece birini göster
        return minPoint.id == maxPoint.id ? nil : (minPoint, maxPoint)
    }

    private func loadPriceHistory() async {
        isLoading = true
        statusMessage = ""
        do {
            let history = try await DatabaseManager.shared.fetchPriceHistory(for: game.id, editionIndex: selectedEditionIndex)
            if history.isEmpty {
                statusMessage = "Bu sürüm için fiyat geçmişi bulunamadı."
            }
            self.priceHistory = history
        } catch {
            statusMessage = "Fiyat geçmişi yüklenemedi: \(error.localizedDescription)"
        }
        isLoading = false
    }
}
