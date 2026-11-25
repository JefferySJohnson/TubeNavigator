import SwiftUI

// MARK: - Boards (v1.10, v1.11)
//
// The TV's Boards feature, on iPhone/iPad: live departure boards
// for the same seven stations as the TV. First-guess design (Jeffery,
// 23 Nov 2026 — he hasn't decided the details yet, so this is the
// first guess): a 5th tab, "Boards", after Status, so the live info
// sits together. Station picker is a plain list (name + coloured
// line dots); the board itself has line chips across the top (tap to
// switch — touch, so none of the TV's focus questions apply),
// platform sections stacked vertically and scrolling naturally, up
// to 5 trains per platform: destination (+ "via" on the Elizabeth
// line), minutes ("arriving" at a minute or less, same as the TV),
// London arrival clock time, and where the train is now where the
// feed gives it. 30-second auto-refresh, pull-to-refresh, "Updated"
// time. The feed logic (ghost filter, composite-key dedupe, per-line
// stop points) is ported from the TV into TubeService — see
// fetchArrivals there.
//
// v1.11: a List / Map segmented switch at the top of the tab. The
// map is the full-line MapKit live map (LiveMapView.swift) —
// another way to see the same live trains, so it lives with
// Boards rather than as a 6th tab (which would land in iOS's
// "More" menu). Jeffery hasn't picked the placement — he can
// ask to move it.
//
// NOT in the first cut: the arrival chime (the iOS silent switch and
// background-audio rules make it fiddly, and the TV chime is a
// living-room feature); "Plan from here" (tap a train to start a
// journey — later idea); searching all 97 stations (follow-up after
// the seven — most Tube stations answer to one stop point, but the
// Elizabeth/DLR stations each need their rail ids verified).

enum BoardsMode {
    case list, map
}

struct BoardsView: View {
    @State private var mode: BoardsMode = .list

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("View", selection: $mode) {
                    Text("List").tag(BoardsMode.list)
                    Text("Map").tag(BoardsMode.map)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                if mode == .list {
                    boardsList
                } else {
                    LiveMapView()
                }
            }
            .navigationTitle(mode == .list ? "Departure boards" : "Live map")
        }
    }

    private var boardsList: some View {
        List {
            Section {
                ForEach(TubeService.boardStations) { station in
                    NavigationLink {
                        StationBoardView(station: station)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(station.name)
                                Text(station.lines.map { TubeLines.name(for: $0) }.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            HStack(spacing: 4) {
                                ForEach(station.lines, id: \.self) { lineId in
                                    Circle()
                                        .fill(lineColor(for: lineId))
                                        .frame(width: 10, height: 10)
                                }
                            }
                        }
                    }
                }
            }
            Section {
                Text("Live departure boards for the main termini — the same seven stations as the TV board. Times are live from Transport for London; a board only fetches while it is open.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct StationBoardView: View {
    @EnvironmentObject private var service: TubeService

    let station: BoardStation
    @State private var lineId: String
    // Which station the board last loaded for — a line change keeps
    // the old trains until the new fetch lands, so switching lines
    // never flashes an empty board; a station change clears it
    // (same pattern as the TV, v1.16).
    @State private var loadedStationId: String?

    init(station: BoardStation) {
        self.station = station
        _lineId = State(initialValue: station.lines[0])
    }

    // Platform sections, A first: the arrivals are already sorted
    // by time, and the platform names sort alphabetically, so
    // "Platform A" (Elizabeth line) always sits on top.
    private var platformSections: [(name: String, trains: [Arrival])] {
        let grouped = Dictionary(grouping: service.arrivals) { $0.platformName }
        return grouped.keys.sorted().map { key in
            (key, Array((grouped[key] ?? []).prefix(5)))
        }
    }

    var body: some View {
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(station.lines, id: \.self) { id in
                            Button {
                                lineId = id
                            } label: {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(lineColor(for: id))
                                        .frame(width: 10, height: 10)
                                    Text(TubeLines.name(for: id))
                                        .font(.subheadline)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(lineId == id ? lineColor(for: id).opacity(0.2) : Color.secondary.opacity(0.12))
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(lineId == id ? lineColor(for: id) : Color.clear, lineWidth: 1.5)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }

            if service.isLoadingArrivals && service.arrivals.isEmpty {
                Section {
                    HStack {
                        ProgressView()
                        Text("Checking trains…").foregroundStyle(.secondary)
                    }
                }
            } else if let error = service.arrivalsError, service.arrivals.isEmpty {
                Section { Text(error).foregroundStyle(.secondary) }
            } else if service.arrivals.isEmpty {
                Section {
                    Text("No trains on this line right now — try another line, or check again in a minute.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(platformSections, id: \.name) { section in
                    Section(section.name) {
                        ForEach(section.trains) { train in
                            trainRow(train)
                        }
                    }
                }
            }

            if let updated = service.lastArrivalsUpdate {
                Section {
                    Text("Updated \(updated.formatted(date: .omitted, time: .shortened)) · Data: Transport for London")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(station.name)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await service.fetchArrivals(station: station, lineId: lineId) }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await service.fetchArrivals(station: station, lineId: lineId) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(service.isLoadingArrivals)
            }
        }
        // The task restarts whenever the line changes — the old fetch
        // loop is cancelled and the new line's trains load — and it
        // re-fetches every 30 seconds while the board is open.
        .task(id: "\(station.id)|\(lineId)") {
            if loadedStationId != station.id {
                service.arrivals = []
                loadedStationId = station.id
            }
            await service.fetchArrivals(station: station, lineId: lineId)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { return }
                await service.fetchArrivals(station: station, lineId: lineId)
            }
        }
    }

    private func trainRow(_ train: Arrival) -> some View {
        let via = TubeService.viaText(for: train.destinationName, lineId: lineId, stationName: station.name)
        let minutes = train.timeToStation.map(TubeService.minutesText) ?? "—"
        let clock = TubeService.arrivalTimeText(train.expectedArrival)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(TubeService.cleanDestination(train.destinationName)).bold()
                        if !via.isEmpty {
                            Text(via)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !train.currentLocation.isEmpty {
                        Text(train.currentLocation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(minutes).bold()
                    if !clock.isEmpty {
                        Text(clock)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}
