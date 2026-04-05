// ShotHistoryView.swift
// GolfShotApp
//
// Displays a list of past shots, optionally filtered by club.

import SwiftUI

struct ShotHistoryView: View {

    @EnvironmentObject var store: ShotStore
    @State private var filterClub: Club? = nil
    @State private var selectedShot: Shot?
    @State private var showClubFilter = false

    private var displayedShots: [Shot] {
        if let club = filterClub {
            return store.shots(for: club)
        }
        return store.shots
    }

    var body: some View {
        NavigationView {
            Group {
                if displayedShots.isEmpty {
                    emptyState
                } else {
                    shotList
                }
            }
            .navigationTitle("Shot History")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    filterButton
                }
            }
            .sheet(item: $selectedShot) { shot in
                NavigationView {
                    ShotResultView(shot: shot, onDone: { selectedShot = nil })
                }
            }
            .confirmationDialog("Filter by Club", isPresented: $showClubFilter, titleVisibility: .visible) {
                Button("All Clubs") { filterClub = nil }
                ForEach(Club.allCases) { club in
                    Button("\(club.emoji) \(club.rawValue)") { filterClub = club }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    // MARK: - Subviews

    private var shotList: some View {
        List {
            if let club = filterClub {
                Section {
                    averageRow(for: club)
                } header: {
                    Text("Averages – \(club.rawValue)")
                }
            }

            Section {
                ForEach(displayedShots) { shot in
                    ShotRow(shot: shot)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedShot = shot }
                }
                .onDelete { indexSet in
                    for idx in indexSet {
                        store.delete(shot: displayedShots[idx])
                    }
                }
            } header: {
                Text(filterClub == nil ? "All Shots" : "Shots")
            }
        }
        .listStyle(.insetGrouped)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.golf")
                .font(.system(size: 60))
                .foregroundColor(Color("GolfGreen").opacity(0.5))
            Text("No shots yet")
                .font(.title3)
                .fontWeight(.semibold)
            Text("Hit the \"Capture\" tab to record your first shot.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private var filterButton: some View {
        Button {
            showClubFilter = true
        } label: {
            Label(filterClub?.rawValue ?? "All", systemImage: "line.3.horizontal.decrease.circle")
                .labelStyle(.iconOnly)
                .foregroundColor(filterClub != nil ? Color("GolfGreen") : .primary)
        }
    }

    @ViewBuilder
    private func averageRow(for club: Club) -> some View {
        let shots = store.shots(for: club)
        if !shots.isEmpty {
            let avgDist  = shots.map(\.metrics.distanceYards).average
            let avgSpeed = shots.map(\.metrics.ballSpeedMPH).average
            HStack(spacing: 0) {
                AverageStatView(label: "Avg Dist",  value: String(format: "%.0f yd", avgDist))
                Divider()
                AverageStatView(label: "Avg Speed", value: String(format: "%.0f mph", avgSpeed))
                Divider()
                AverageStatView(label: "Shots",     value: "\(shots.count)")
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - ShotRow

struct ShotRow: View {

    let shot: Shot

    var body: some View {
        HStack(spacing: 12) {
            // Club emoji
            Text(shot.club.emoji)
                .font(.title2)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color("GolfGreen").opacity(0.12)))

            VStack(alignment: .leading, spacing: 2) {
                Text(shot.club.rawValue)
                    .font(.headline)
                Text(shot.formattedDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.0f yd", shot.metrics.distanceYards))
                    .font(.headline)
                    .foregroundColor(Color("GolfGreen"))
                Text(String(format: "%.0f mph", shot.metrics.ballSpeedMPH))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - AverageStatView

struct AverageStatView: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

// MARK: - Array<Double> average

extension Array where Element == Double {
    var average: Double {
        guard !isEmpty else { return 0 }
        return reduce(0, +) / Double(count)
    }
}

#Preview {
    ShotHistoryView()
        .environmentObject(ShotStore.shared)
}
