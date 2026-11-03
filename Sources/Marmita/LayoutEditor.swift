import AppKit
import MarmitaCore
import SwiftUI

@MainActor
final class EditorWindowController: NSWindowController {
    init(state: AppState) {
        let host = NSHostingController(rootView: LayoutEditorView().environmentObject(state))
        let window = NSWindow(contentViewController: host)
        window.title = "Marmita — Layouts"
        window.styleMask.insert([.resizable, .miniaturizable])
        window.setContentSize(NSSize(width: 960, height: 620))
        window.setFrameAutosaveName("MarmitaEditor")
        window.isReleasedWhenClosed = false

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func present() {
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct ScreenSummary: Identifiable, Equatable {
    let id: String
    let name: String

    static func captureCurrent() -> [ScreenSummary] {
        NSScreen.screens.map { ScreenSummary(id: $0.displayKey, name: $0.localizedName) }
    }
}

struct LayoutEditorView: View {
    @EnvironmentObject private var state: AppState
    @State private var selectedLayoutID: UUID?
    @State private var selectedZoneID: UUID?
    @State private var screens = ScreenSummary.captureCurrent()

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedLayoutID) {
                ForEach(state.preferences.layouts) { layout in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(layout.name.isEmpty ? "Sem nome" : layout.name)
                        Text(layout.zones.count == 1 ? "1 zona" : "\(layout.zones.count) zonas")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(layout.id)
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220)
            .safeAreaInset(edge: .bottom) {
                sidebarActions
            }
        } detail: {
            if let binding = makeLayoutBinding(for: selectedLayoutID) {
                LayoutDetailView(layout: binding, selectedZoneID: $selectedZoneID, screens: screens)
            } else {
                Text("Escolhe ou cria um layout")
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            if selectedLayoutID == nil {
                selectedLayoutID = state.preferences.layouts.first?.id
            }
        }
        .onChange(of: selectedLayoutID) {
            selectedZoneID = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screens = ScreenSummary.captureCurrent()
        }
    }

    private var sidebarActions: some View {
        HStack(spacing: 8) {
            Menu {
                Button("Layout vazio") {
                    addLayout(ZoneLayout(name: "Novo layout", zones: []))
                }

                Divider()

                ForEach(LayoutPreset.allCases, id: \.self) { preset in
                    Button(preset.displayName) {
                        addLayout(preset.makeLayout())
                    }
                }
            } label: {
                Image(systemName: "plus")
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Novo layout")

            Button {
                duplicateSelectedLayout()
            } label: {
                Image(systemName: "plus.square.on.square")
            }
            .disabled(selectedLayoutID == nil)
            .help("Duplicar layout")

            Button {
                deleteSelectedLayout()
            } label: {
                Image(systemName: "minus")
            }
            .disabled(selectedLayoutID == nil || state.preferences.layouts.count <= 1)
            .help("Apagar layout")

            Spacer()
        }
        .buttonStyle(.borderless)
        .padding(8)
    }

    private func makeLayoutBinding(for id: UUID?) -> Binding<ZoneLayout>? {
        guard let id, let initial = state.preferences.layouts.first(where: { $0.id == id }) else {
            return nil
        }

        return Binding(
            get: { state.preferences.layouts.first { $0.id == id } ?? initial },
            set: { updated in
                if let index = state.preferences.layouts.firstIndex(where: { $0.id == id }) {
                    state.preferences.layouts[index] = updated
                }
            }
        )
    }

    private func addLayout(_ layout: ZoneLayout) {
        state.preferences.layouts.append(layout)
        selectedLayoutID = layout.id
    }

    private func duplicateSelectedLayout() {
        guard let layout = state.preferences.layouts.first(where: { $0.id == selectedLayoutID }) else {
            return
        }

        let zones = layout.zones.map { Zone(rect: $0.rect) }

        addLayout(ZoneLayout(name: "\(layout.name) (cópia)", zones: zones))
    }

    private func deleteSelectedLayout() {
        guard let id = selectedLayoutID, state.preferences.layouts.count > 1 else {
            return
        }

        state.preferences.removeLayout(id: id)
        selectedLayoutID = state.preferences.layouts.first?.id
    }
}

private struct LayoutDetailView: View {
    @EnvironmentObject private var state: AppState
    @Binding var layout: ZoneLayout
    @Binding var selectedZoneID: UUID?
    @FocusState private var isNameFocused: Bool
    let screens: [ScreenSummary]

    /// The shape of the first screen using this layout, or of the primary
    /// screen, so a layout for a portrait monitor is drawn portrait.
    private var aspectRatio: CGFloat {
        let screen = NSScreen.screens.first { state.preferences.getLayout(forScreen: $0.displayKey)?.id == layout.id }
            ?? NSScreen.screens.first

        guard let frame = screen?.visibleFrame, frame.height > 0 else {
            return 16.0 / 10
        }

        return frame.width / frame.height
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Nome do layout", text: $layout.name)
                .focused($isNameFocused)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .frame(maxWidth: 360)

            screenAssignments

            ZoneCanvas(layout: $layout, selectedZoneID: $selectedZoneID, aspectRatio: aspectRatio)
                // A drag on the canvas never takes focus, so working with the
                // zones hands it back from the name field and ⌘⌫ works again.
                .onChange(of: selectedZoneID) {
                    isNameFocused = false
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 10) {
                Menu("Aplicar modelo") {
                    ForEach(LayoutPreset.allCases, id: \.self) { preset in
                        Button(preset.displayName) {
                            layout.zones = preset.makeZones()
                            selectedZoneID = nil
                        }
                    }
                }
                .fixedSize()

                Button("Apagar zona") {
                    layout.zones.removeAll { $0.id == selectedZoneID }
                    selectedZoneID = nil
                }
                .keyboardShortcut(.delete, modifiers: .command)
                // Off while typing, so ⌘⌫ deletes text in the name field, not a zone.
                .disabled(selectedZoneID == nil || isNameFocused)

                Button("Limpar") {
                    layout.zones.removeAll()
                    selectedZoneID = nil
                }
                .disabled(layout.zones.isEmpty)

                Spacer()
            }

            Text("Arrasta numa área livre para desenhar uma zona. Arrasta uma zona para a mover e o canto inferior direito para a redimensionar. ⌘⌫ apaga a zona selecionada.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }

    private var screenAssignments: some View {
        HStack(spacing: 8) {
            Text("Usar em:")
                .foregroundStyle(.secondary)

            ForEach(screens) { screen in
                let isActive = state.preferences.getLayout(forScreen: screen.id)?.id == layout.id

                Button {
                    state.preferences.screenLayouts[screen.id] = layout.id
                } label: {
                    Label(screen.name, systemImage: isActive ? "checkmark.circle.fill" : "display")
                }
                .disabled(isActive)
            }
        }
    }
}

/// The drawing surface: a miniature of a screen where zones are drawn, moved
/// and resized on a grid of 24 × 24 cells.
private struct ZoneCanvas: View {
    @Binding var layout: ZoneLayout
    @Binding var selectedZoneID: UUID?
    let aspectRatio: CGFloat
    @State private var gesture: CanvasGesture?
    @State private var gestureStart: CGPoint?
    @State private var draft: UnitRect?

    private let cells = 24.0
    private let handleSize: CGFloat = 16

    private var step: Double {
        1 / cells
    }

    private enum CanvasGesture {
        case draw(start: CGPoint)
        case move(id: UUID, original: UnitRect)
        case resize(id: UUID, original: UnitRect)
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let numbered = Array(layout.orderedZones.enumerated())

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(colors: [Color(white: 0.22), Color(white: 0.12)], startPoint: .top, endPoint: .bottom))

                makeGridLines(size: size)

                ForEach(numbered, id: \.element.id) { index, zone in
                    ZoneTile(number: index + 1, isSelected: zone.id == selectedZoneID, handleSize: handleSize)
                        .frame(width: zone.rect.width * size.width, height: zone.rect.height * size.height)
                        .offset(x: zone.rect.x * size.width, y: zone.rect.y * size.height)
                }

                if let draft {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        .background(Color.accentColor.opacity(0.15))
                        .frame(width: draft.width * size.width, height: draft.height * size.height)
                        .offset(x: draft.x * size.width, y: draft.y * size.height)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        handleChange(value, size: size)
                    }
                    .onEnded { value in
                        handleEnd(value, size: size)
                    }
            )
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
    }

    private func makeGridLines(size: CGSize) -> some View {
        Canvas { context, canvasSize in
            var path = Path()

            for i in 1..<12 {
                let x = canvasSize.width * CGFloat(i) / 12
                let y = canvasSize.height * CGFloat(i) / 12
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: canvasSize.height))
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: canvasSize.width, y: y))
            }

            context.stroke(path, with: .color(.white.opacity(0.06)), lineWidth: 1)
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }

    private func handleChange(_ value: DragGesture.Value, size: CGSize) {
        guard size.width > 0, size.height > 0 else {
            return
        }

        // SwiftUI skips onEnded when it cancels a drag, so a new start
        // location is what marks a new gesture.
        if gesture == nil || gestureStart != value.startLocation {
            gestureStart = value.startLocation
            draft = nil
            gesture = beginGesture(at: value.startLocation, size: size)
        }

        let dx = Double(value.translation.width / size.width)
        let dy = Double(value.translation.height / size.height)

        switch gesture {
        case let .draw(start):
            draft = makeDraft(from: start, to: value.location, size: size)
        case let .move(id, original):
            var moved = original
            moved.x = snap(original.x + dx)
            moved.y = snap(original.y + dy)
            updateZone(id, rect: moved.makeClamped(minSize: step))
        case let .resize(id, original):
            var resized = original
            resized.width = max(snap(original.maxX + dx) - original.x, step)
            resized.height = max(snap(original.maxY + dy) - original.y, step)
            resized.width = min(resized.width, 1 - original.x)
            resized.height = min(resized.height, 1 - original.y)
            updateZone(id, rect: resized)
        case nil:
            break
        }
    }

    private func handleEnd(_ value: DragGesture.Value, size: CGSize) {
        // Half a cell, because differences of snapped values can land a hair under one cell.
        if case .draw = gesture, let draft, draft.width >= step / 2, draft.height >= step / 2 {
            let zone = Zone(rect: draft)
            layout.zones.append(zone)
            selectedZoneID = zone.id
        } else if case .draw = gesture {
            selectedZoneID = nil
        }

        gesture = nil
        gestureStart = nil
        draft = nil
    }

    private func beginGesture(at point: CGPoint, size: CGSize) -> CanvasGesture {
        if let selected = layout.zones.first(where: { $0.id == selectedZoneID }) {
            let corner = CGPoint(x: selected.rect.maxX * size.width, y: selected.rect.maxY * size.height)

            if abs(point.x - corner.x) <= handleSize, abs(point.y - corner.y) <= handleSize {
                return .resize(id: selected.id, original: selected.rect)
            }
        }

        let unit = CGPoint(x: point.x / size.width, y: point.y / size.height)
        let hit = layout.zones
            .filter { unit.x >= $0.rect.x && unit.x <= $0.rect.maxX && unit.y >= $0.rect.y && unit.y <= $0.rect.maxY }
            .min { $0.rect.width * $0.rect.height < $1.rect.width * $1.rect.height }

        if let hit {
            selectedZoneID = hit.id

            return .move(id: hit.id, original: hit.rect)
        }

        return .draw(start: point)
    }

    private func makeDraft(from start: CGPoint, to end: CGPoint, size: CGSize) -> UnitRect {
        let x1 = snap(clampUnit(Double(start.x / size.width)))
        let y1 = snap(clampUnit(Double(start.y / size.height)))
        let x2 = snap(clampUnit(Double(end.x / size.width)))
        let y2 = snap(clampUnit(Double(end.y / size.height)))

        return UnitRect(x: min(x1, x2), y: min(y1, y2), width: abs(x2 - x1), height: abs(y2 - y1))
    }

    private func updateZone(_ id: UUID, rect: UnitRect) {
        if let index = layout.zones.firstIndex(where: { $0.id == id }), layout.zones[index].rect != rect {
            layout.zones[index].rect = rect
        }
    }

    private func snap(_ value: Double) -> Double {
        (value / step).rounded() * step
    }

    private func clampUnit(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

private struct ZoneTile: View {
    let number: Int
    let isSelected: Bool
    let handleSize: CGFloat

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(isSelected ? 0.45 : 0.22))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.accentColor.opacity(isSelected ? 1 : 0.7), lineWidth: isSelected ? 3 : 1.5)
                )
                .overlay(
                    Text("\(number)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                )

            if isSelected {
                Image(systemName: "arrow.down.right.square.fill")
                    .font(.system(size: handleSize))
                    .foregroundStyle(.white, Color.accentColor)
                    .padding(2)
            }
        }
        .padding(2)
        .allowsHitTesting(false)
    }
}
