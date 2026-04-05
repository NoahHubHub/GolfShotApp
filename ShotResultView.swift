// ShotResultView.swift
// GolfShotApp
//
// Displays the results of a single golf shot with metrics and trajectory.

import SwiftUI
import AVKit

struct ShotResultView: View {

    let shot: Shot
    var onDone: (() -> Void)?

    @State private var showVideo = false
    @State private var videoPlayer: AVPlayer?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                headerSection

                // Trajectory preview
                trajectoryCard

                // Metrics grid
                metricsGrid

                // Shot shape badge
                shotShapeBadge

                // Video button
                if shot.videoFilename != nil {
                    videoButton
                }

                Spacer(minLength: 40)
            }
            .padding()
        }
        .background(Color("GolfGreen").opacity(0.06).ignoresSafeArea())
        .navigationTitle("Shot Result")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") { onDone?() }
                    .fontWeight(.semibold)
                    .foregroundColor(Color("GolfGreen"))
            }
        }
        .sheet(isPresented: $showVideo) {
            if let player = videoPlayer {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: - Subviews

    private var headerSection: some View {
        VStack(spacing: 4) {
            Text(shot.club.emoji)
                .font(.system(size: 48))
            Text(shot.club.rawValue)
                .font(.title2)
                .fontWeight(.bold)
            Text(shot.formattedDate)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemBackground))
            .shadow(color: .black.opacity(0.06), radius: 8))
    }

    private var trajectoryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Trajectory", systemImage: "arrow.up.right")
                .font(.headline)
                .foregroundColor(Color("GolfGreen"))

            TrajectoryView(points: shot.trajectoryPoints)
                .frame(height: 140)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemBackground))
            .shadow(color: .black.opacity(0.06), radius: 8))
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricCard(
                icon: "arrow.right",
                title: "Distance",
                value: String(format: "%.0f", shot.metrics.distanceYards),
                unit: "yards",
                color: Color("GolfGreen")
            )
            MetricCard(
                icon: "speedometer",
                title: "Ball Speed",
                value: String(format: "%.0f", shot.metrics.ballSpeedMPH),
                unit: "mph",
                color: .orange
            )
            MetricCard(
                icon: "angle",
                title: "Launch Angle",
                value: String(format: "%.1f°", shot.metrics.launchAngleDegrees),
                unit: "",
                color: .blue
            )
            MetricCard(
                icon: "arrow.left.and.right",
                title: "Direction",
                value: directionString,
                unit: "",
                color: .purple
            )
            MetricCard(
                icon: "mountain.2",
                title: "Peak Height",
                value: String(format: "%.0f", shot.metrics.peakHeightFeet),
                unit: "ft",
                color: .teal
            )
        }
    }

    private var shotShapeBadge: some View {
        HStack {
            Text("Shot Shape")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(shot.metrics.shotShape.rawValue)
                .font(.headline)
                .fontWeight(.bold)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(shotShapeColor.opacity(0.15))
                )
                .foregroundColor(shotShapeColor)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemBackground))
            .shadow(color: .black.opacity(0.06), radius: 8))
    }

    private var videoButton: some View {
        Button {
            loadAndShowVideo()
        } label: {
            Label("Watch Recording", systemImage: "play.circle.fill")
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(RoundedRectangle(cornerRadius: 14).fill(Color("GolfGreen")))
        }
    }

    // MARK: - Helpers

    private var directionString: String {
        let deg = shot.metrics.directionDegrees
        let abs = Swift.abs(deg)
        let side = deg >= 0 ? "R" : "L"
        return String(format: "%.1f° %@", abs, side)
    }

    private var shotShapeColor: Color {
        switch shot.metrics.shotShape {
        case .straight:            return Color("GolfGreen")
        case .draw, .fade:         return .blue
        case .hook, .slice:        return .red
        case .push, .pull:         return .orange
        }
    }

    private func loadAndShowVideo() {
        guard let filename = shot.videoFilename else { return }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url  = docs.appendingPathComponent("Videos").appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: url.path) {
            videoPlayer = AVPlayer(url: url)
            showVideo = true
        }
    }
}

// MARK: - MetricCard

struct MetricCard: View {
    let icon: String
    let title: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 6)
        )
    }
}

// MARK: - TrajectoryView

struct TrajectoryView: View {

    let points: [CGPoint]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            if points.count >= 2 {
                // Draw the path
                Path { path in
                    let mapped = points.map { CGPoint(x: $0.x * w, y: (1 - $0.y) * h) }
                    path.move(to: mapped[0])
                    for pt in mapped.dropFirst() {
                        path.addLine(to: pt)
                    }
                }
                .stroke(
                    LinearGradient(colors: [Color("GolfGreen"), .blue],
                                   startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                )

                // Ball indicator at end
                if let last = points.last {
                    Circle()
                        .fill(Color("GolfGreen"))
                        .frame(width: 8, height: 8)
                        .position(x: last.x * w, y: (1 - last.y) * h)
                }
                // Start indicator
                if let first = points.first {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().strokeBorder(Color("GolfGreen"), lineWidth: 1.5))
                        .position(x: first.x * w, y: (1 - first.y) * h)
                }
            } else {
                Text("No trajectory data")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(8)
    }
}

#Preview {
    NavigationView {
        ShotResultView(shot: Shot(
            club: .driver,
            metrics: ShotMetrics(
                distanceYards: 247,
                carryYards: 235,
                launchAngleDegrees: 12.5,
                directionDegrees: -3.2,
                ballSpeedMPH: 158,
                clubSpeedMPH: 105,
                smashFactor: 1.50,
                shotShape: .draw,
                peakHeightFeet: 98
            ),
            trajectoryPoints: stride(from: 0.0, through: 1.0, by: 0.05).map {
                CGPoint(x: $0, y: sin($0 * .pi))
            }
        ))
    }
}
