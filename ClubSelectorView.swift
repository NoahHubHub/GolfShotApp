// ClubSelectorView.swift
// GolfShotApp
//
// A scrollable grid to pick the active golf club.

import SwiftUI

struct ClubSelectorView: View {

    @Binding var selectedClub: Club
    var onDismiss: (() -> Void)?

    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 140), spacing: 12)
    ]

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Club.allCases) { club in
                        ClubCell(club: club, isSelected: club == selectedClub)
                            .onTapGesture {
                                selectedClub = club
                                onDismiss?()
                            }
                    }
                }
                .padding()
            }
            .background(Color("GolfGreen").opacity(0.08).ignoresSafeArea())
            .navigationTitle("Select Club")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { onDismiss?() }
                        .fontWeight(.semibold)
                        .foregroundColor(Color("GolfGreen"))
                }
            }
        }
    }
}

// MARK: - ClubCell

private struct ClubCell: View {

    let club: Club
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            Text(club.emoji)
                .font(.system(size: 32))
            Text(club.rawValue)
                .font(.caption)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .foregroundColor(isSelected ? .white : .primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color("GolfGreen") : Color(.systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelected ? Color("GolfGreen") : Color.gray.opacity(0.2), lineWidth: 1.5)
        )
        .scaleEffect(isSelected ? 1.04 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
    }
}

#Preview {
    ClubSelectorView(selectedClub: .constant(.driver))
}
