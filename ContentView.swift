// ContentView.swift
// GolfShotApp
//
// Main tab-bar navigation container.

import SwiftUI

struct ContentView: View {

    @StateObject private var store = ShotStore.shared

    var body: some View {
        TabView {
            ShotCaptureView()
                .tabItem {
                    Label("Capture", systemImage: "camera.aperture")
                }

            ShotHistoryView()
                .tabItem {
                    Label("History", systemImage: "list.bullet.clipboard")
                }

            StatsView()
                .tabItem {
                    Label("Stats", systemImage: "chart.bar.xaxis")
                }
        }
        .accentColor(Color("GolfGreen"))
        .environmentObject(store)
    }
}

// MARK: - StatsView

struct StatsView: View {

    @EnvironmentObject var store: ShotStore

    var body: some View {
        NavigationView {
            List {
                if store.shots.isEmpty {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "chart.bar")
                                .font(.system(size: 50))
                                .foregroundColor(Color("GolfGreen").opacity(0.4))
                            Text("No data yet")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    }
                } else {
                    // Per-club summary
                    Section(header: Text("By Club")) {
                        ForEach(clubsWithShots) { club in
                            NavigationLink {
                                ClubStatsDetailView(club: club)
                                    .environmentObject(store)
                            } label: {
                                ClubStatRow(club: club, shots: store.shots(for: club))
                            }
                        }
                    }

                    // Overall summary
                    Section(header: Text("Overall")) {
                        LabeledContent("Total Shots", value: "\(store.shots.count)")
                        LabeledContent("Avg Distance",
                                       value: String(format: "%.0f yd",
                                                     store.shots.map(\.metrics.distanceYards).average))
                        LabeledContent("Avg Ball Speed",
                                       value: String(format: "%.0f mph",
                                                     store.shots.map(\.metrics.ballSpeedMPH).average))
                        LabeledContent("Avg Launch Angle",
                                       value: String(format: "%.1f°",
                                                     store.shots.map(\.metrics.launchAngleDegrees).average))
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Statistics")
        }
    }

    private var clubsWithShots: [Club] {
        Club.allCases.filter { !store.shots(for: $0).isEmpty }
    }
}

// MARK: - ClubStatRow

struct ClubStatRow: View {
    let club: Club
    let shots: [Shot]

    var body: some View {
        HStack {
            Text(club.emoji)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(club.rawValue)
                    .font(.headline)
                Text("\(shots.count) shot\(shots.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.0f yd", shots.map(\.metrics.distanceYards).average))
                    .fontWeight(.semibold)
                    .foregroundColor(Color("GolfGreen"))
                Text("avg")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - ClubStatsDetailView

struct ClubStatsDetailView: View {

    let club: Club
    @EnvironmentObject var store: ShotStore

    private var shots: [Shot] { store.shots(for: club) }

    var body: some View {
        List {
            Section(header: Text("Averages")) {
                LabeledContent("Distance",
                               value: String(format: "%.0f yd", shots.map(\.metrics.distanceYards).average))
                LabeledContent("Ball Speed",
                               value: String(format: "%.0f mph", shots.map(\.metrics.ballSpeedMPH).average))
                LabeledContent("Launch Angle",
                               value: String(format: "%.1f°", shots.map(\.metrics.launchAngleDegrees).average))
            }

            Section(header: Text("Shot Distribution")) {
                ForEach(ShotMetrics.ShotShape.allCases, id: \.self) { shape in
                    let count = shots.filter { $0.metrics.shotShape == shape }.count
                    if count > 0 {
                        HStack {
                            Text(shape.rawValue)
                            Spacer()
                            Text("\(count)")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Section(header: Text("All Shots")) {
                ForEach(shots) { shot in
                    ShotRow(shot: shot)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("\(club.emoji) \(club.rawValue)")
    }
}

// MARK: - ShotMetrics.ShotShape CaseIterable

extension ShotMetrics.ShotShape: CaseIterable {
    static var allCases: [ShotMetrics.ShotShape] {
        [.straight, .draw, .fade, .hook, .slice, .push, .pull]
    }
}

#Preview {
    ContentView()
}
