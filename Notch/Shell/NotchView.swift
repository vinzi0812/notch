import ServiceManagement
import SwiftUI

struct NotchView: View {

    let viewModel: NotchViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Lets the glass pill find the selected tab.
    @Namespace private var tabGlass

    private var geometry: NotchGeometry { viewModel.geometry }
    private var motionSpeed: Double { viewModel.settings.animationSpeed.multiplier }

    private var size: CGSize {
        switch viewModel.presentation {
        case .collapsed: geometry.collapsedRect.size
        case .expanded: geometry.expandedSize(height: viewModel.expandedHeight)
        case .activity: geometry.activitySize
        }
    }

    private var cornerRadius: CGFloat {
        switch viewModel.presentation {
        case .collapsed: 10
        case .expanded: viewModel.settings.cornerRadius
        // Slightly tighter than expanded, as before; the activity shape is much shorter.
        case .activity: min(viewModel.settings.cornerRadius, 22)
        }
    }

    private var notchShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            bottomLeadingRadius: cornerRadius,
            bottomTrailingRadius: cornerRadius
        )
    }

    /// Solid black over a hardware notch, so it blends into the camera housing. On a screen without
    /// one there's nothing to hide, so the notch is smoked Liquid Glass: tinted dark enough that its
    /// white content stays readable over any menu bar or wallpaper.
    @ViewBuilder
    private var notchSurface: some View {
        switch geometry.kind {
        case .hardware:
            notchShape.fill(.black)
        case .virtual:
            notchShape
                .fill(.clear)
                .glassTinted(.black.opacity(0.55), in: notchShape)
        }
    }

    var body: some View {
        notchSurface
            .frame(width: size.width, height: size.height)
            .overlay {
                switch viewModel.presentation {
                case .collapsed:
                    collapsedContent
                        .transition(NotchMotion.content(reduceMotion: reduceMotion, speed: motionSpeed))
                case .expanded:
                    expandedContent
                case .activity(let module):
                    activityContent(for: module)
                        .transition(NotchMotion.content(reduceMotion: reduceMotion, speed: motionSpeed))
                }
            }
            .foregroundStyle(.white)
            .clipShape(notchShape)
            // Below the clip on purpose: `.animation` only animates what's above it. Above the clip,
            // the clip would jump to the new size while the shape animated inside it, hiding a shrink.
            .animation(NotchMotion.pageResize(reduceMotion: reduceMotion, speed: motionSpeed), value: viewModel.expandedHeight)
            .animation(NotchMotion.pageResize(reduceMotion: reduceMotion, speed: motionSpeed), value: viewModel.settings.cornerRadius)
            .environment(\.notchAccent, viewModel.settings.accent.color)
            .environment(\.calendarLayout, viewModel.settings.calendarLayout)
            .environment(\.timerPresets, viewModel.settings.showsTimerPresets ? viewModel.settings.timerPresets.map { $0 * 60 } : [])
            .environment(\.hapticFeedbackEnabled, viewModel.settings.hapticFeedbackEnabled)
            .environment(\.terminalFontSize, viewModel.settings.terminalFontSize)
            .contextMenu { appMenu }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var earModule: (any NotchModule)? {
        viewModel.modules.earOwner
    }

    /// Which module owns the ears; changes to it are animated no matter which module caused them.
    private var earOwnerID: ObjectIdentifier? {
        earModule.map { ObjectIdentifier($0) }
    }

    private var collapsedContent: some View {
        Group {
            switch geometry.kind {
            case .hardware where !geometry.showsEars:
                EmptyView()
            case .hardware:
                HStack(spacing: 0) {
                    ear(.leadingEar)
                        .frame(width: NotchGeometry.earWidth)
                    Spacer()
                    ear(.trailingEar)
                        .frame(width: NotchGeometry.earWidth)
                }
            case .virtual:
                ear(.pill)
            }
        }
        .animation(NotchMotion.earHandover(reduceMotion: reduceMotion, speed: motionSpeed), value: earOwnerID)
    }

    private var expandedContent: some View {
        ZStack(alignment: .top) {
            Group {
                if let tabModule = viewModel.selectedTabModule {
                    tabPage(for: tabModule)
                } else {
                    homePage
                }
            }
            .id(viewModel.selectedTab)
            .transition(NotchMotion.earContent(reduceMotion: reduceMotion, speed: motionSpeed))

            if viewModel.isEditingHome {
                editBar
            } else if !viewModel.tabModules.isEmpty {
                tabBar
            }
        }
        .animation(NotchMotion.earHandover(reduceMotion: reduceMotion, speed: motionSpeed), value: viewModel.selectedTab)
        .environment(\.openNotchPage, OpenNotchPageAction { [viewModel] module in viewModel.select(tab: module) })
        .environment(\.textEditing, TextEditingAction { [viewModel] editing in viewModel.setEditingText(editing) })
        .overlay(alignment: .bottom) {
            if viewModel.showsLevelsOverExpanded {
                levelsOverlay
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: viewModel.showsLevelsOverExpanded)
        .transition(.opacity)
    }

    /// Volume or brightness along the bottom of the open notch.
    private var levelsOverlay: some View {
        let levels = viewModel.levels
        return HStack(spacing: 10) {
            Image(systemName: levels.symbol)
                .frame(width: 20)
                .contentTransition(.symbolEffect(.replace))
            LevelBar(level: levels.isMuted ? 0 : levels.level)
            Text(levels.percentText)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassControl(in: Capsule(), interactive: false)
        .padding(.horizontal, 40)
        .padding(.bottom, 10)
    }

    private var homeColumns: Int {
        HomeLayout.columns(forWidth: geometry.expandedWidth)
    }

    /// Replaces the tabs while arranging Home: Add Widget on the left, Done on the right of the camera.
    private var editBar: some View {
        HStack(spacing: 10) {
            AddWidgetMenu(settings: viewModel.settings)
                .menuStyle(.button)
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .glassControl(in: Capsule())
                .fixedSize()
            OverflowNote(settings: viewModel.settings, columns: homeColumns)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
            Spacer()
            Button {
                withAnimation(.snappy) { viewModel.endEditingHome() }
            } label: {
                Text("Done")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(.white, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .frame(height: geometry.notchRect.height)
    }

    /// Home and the labelled tabs left of the camera; icon buttons (like the mirror) right of it.
    private var tabBar: some View {
        HStack(spacing: 0) {
            let labels = tabLabels
            HStack(spacing: tabs(.tab).count >= 3 ? 1 : TabBarLayout.spacing) {
                tabButton(title: "Home", symbol: "house.fill", module: nil, labels: labels)
                ForEach(tabs(.tab).indices, id: \.self) { index in
                    let module = tabs(.tab)[index]
                    if let tab = module.tab {
                        tabButton(title: tab.title, symbol: tab.symbol, module: module, labels: labels)
                    }
                }
            }
            .padding(.leading, 22)

            Spacer()

            HStack(spacing: 6) {
                ForEach(tabs(.button).indices, id: \.self) { index in
                    let module = tabs(.button)[index]
                    if let tab = module.tab {
                        iconButton(tab: tab, module: module)
                    }
                }

                if viewModel.settings.showsSettingsButton {
                    Button {
                        viewModel.onOpenSettings?()
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.caption.weight(.medium))
                            .frame(width: 24, height: 22)
                            .foregroundStyle(.white.opacity(0.55))
                            .contentShape(Capsule())
                    }
                    .help("Settings")
                }
            }
            .padding(.trailing, 22)
        }
        .background { tabPill }
        .buttonStyle(.plain)
        .frame(height: geometry.notchRect.height)
    }

    private func tabs(_ style: NotchTab.Style) -> [any NotchModule] {
        viewModel.tabModules.filter { $0.tab?.style == style }
    }

    /// Marks where the selected tab is; the glass pill behind the bar follows it.
    @ViewBuilder
    private func selectionPill(_ selected: Bool) -> some View {
        if selected {
            Color.clear.matchedGeometryEffect(id: "selected-tab", in: tabGlass)
        }
    }

    /// One glass pill behind the whole bar that slides to the selected tab. Behind, not around: glass
    /// drawn in a container sits above sibling views, which hid the tab's label.
    @ViewBuilder
    private var tabPill: some View {
        if viewModel.selectedTabModule?.tab?.style != .page {
            Capsule()
                .fill(.clear)
                .glassSurface(in: Capsule(), fallbackOpacity: 0.18)
                .matchedGeometryEffect(id: "selected-tab", in: tabGlass, isSource: false)
        }
    }

    private func isSelected(_ module: (any NotchModule)?) -> Bool {
        viewModel.selectedTab == module.map { ObjectIdentifier($0) }
    }

    /// Room for the tabs left of the camera, less a little breathing space.
    private var tabSpace: CGFloat {
        (geometry.expandedWidth - geometry.notchRect.width) / 2 - 22 - 10
    }

    private var tabLabels: TabBarLayout.Labels {
        let modules: [(any NotchModule)?] = [nil] + tabs(.tab).map { $0 }
        let titles = modules.map { $0?.tab?.title ?? "Home" }
        return TabBarLayout.labels(
            titleWidths: titles.map { TabBarLayout.measure($0) },
            selected: modules.firstIndex { isSelected($0) },
            available: tabSpace
        )
    }

    private func tabButton(title: String, symbol: String, module: (any NotchModule)?, labels: TabBarLayout.Labels) -> some View {
        let selected = isSelected(module)
        let showsTitle = labels == .all || (labels == .selectedOnly && selected)
        return Button {
            viewModel.select(tab: module)
        } label: {
            Label(title, systemImage: symbol)
                .labelStyle(TabLabelStyle(showsTitle: showsTitle))
                .font(.caption.weight(.medium))
                .padding(.horizontal, tabs(.tab).count >= 3 ? 5 : 9)
                .padding(.vertical, 4)
                .background { selectionPill(selected) }
                .foregroundStyle(.white.opacity(selected ? 1 : 0.55))
                .contentShape(Capsule())
        }
        .help(title)
    }

    /// Toggles its page: opens it, or goes back to Home if it's already open.
    private func iconButton(tab: NotchTab, module: any NotchModule) -> some View {
        let selected = isSelected(module)
        return Button {
            viewModel.select(tab: selected ? nil : module)
        } label: {
            NotchIcon(name: tab.symbol)
                .font(.caption.weight(.medium))
                .frame(width: 24, height: 22)
                .background { selectionPill(selected) }
                .foregroundStyle(.white.opacity(selected ? 1 : 0.55))
                .contentShape(Capsule())
        }
        .help(tab.title)
    }

    private func tabPage(for module: any NotchModule) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: geometry.notchRect.height)
            AnyView(module.content(for: .page))
                .padding(.horizontal, 24)
                .padding(.top, 2)
                .padding(.bottom, 10)
                .frame(maxHeight: .infinity)
        }
    }

    private var homePage: some View {
        VStack(spacing: 0) {
            // Clear of the camera band and the tab bar in it.
            Color.clear.frame(height: geometry.notchRect.height)
            if let headliner = viewModel.modules.headliner {
                // The full-width player row, then the widgets.
                AnyView(headliner.content(for: .headline))
                    .frame(height: NotchGeometry.headlineHeight - 8)
                    .padding(.horizontal, 24)
                    .transition(NotchMotion.earContent(reduceMotion: reduceMotion, speed: motionSpeed))
                Divider()
                    .overlay(.white.opacity(0.15))
                    .padding(.horizontal, 24)
            }
            if viewModel.isEditingHome {
                HomeLayoutEditor(settings: viewModel.settings, columns: homeColumns) { widget in
                    // The live widget, just not tappable while arranging.
                    HomeWidgetView(kind: widget.kind, size: widget.size, viewModel: viewModel)
                        .padding(8)
                        .allowsHitTesting(false)
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 10)
                .frame(maxHeight: .infinity)
            } else if viewModel.homeWidgets.isEmpty {
                Text("Nothing on Home. Right-click → Edit Home to add widgets.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxHeight: .infinity)
            } else {
                HomeGrid(viewModel: viewModel)
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 10)
                    .frame(maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private var appMenu: some View {
        let launchAtLogin = viewModel.launchAtLogin

        Text(AppVersion.current)
        Divider()
        Toggle("Launch at Login", isOn: Binding(
            get: { launchAtLogin.isEnabled },
            set: { launchAtLogin.setEnabled($0) }
        ))
        if launchAtLogin.needsApproval {
            Button("Allow in Login Items Settings…") {
                SMAppService.openSystemSettingsLoginItems()
            }
        }
        if let error = launchAtLogin.lastError {
            Text(error)
        }
        Divider()
        Button("Edit Home…") {
            withAnimation(.snappy) { viewModel.beginEditingHome() }
        }
        .disabled(viewModel.isEditingHome)
        Button("Settings…") {
            viewModel.onOpenSettings?()
        }
        Button("Quit Notch") {
            NSApplication.shared.terminate(nil)
        }
    }

    private func activityContent(for module: any NotchModule) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                AnyView(module.content(for: .activityLeading))
                    .frame(width: NotchGeometry.activityEarWidth)
                Spacer()
                AnyView(module.content(for: .activityTrailing))
                    .frame(width: NotchGeometry.activityEarWidth)
            }
            .frame(height: geometry.notchRect.height)

            AnyView(module.content(for: .activityDetail))
                .frame(maxHeight: .infinity)
        }
    }

    private func ear(_ placement: NotchPlacement) -> some View {
        ZStack {
            if let earModule {
                // A new identity per owner makes a handover a transition, not an in-place swap.
                AnyView(earModule.content(for: placement))
                    .id(earOwnerID)
                    .transition(NotchMotion.earContent(reduceMotion: reduceMotion, speed: motionSpeed))
            }
        }
    }
}

extension NotchGeometry {
    static let previewHardware = NotchGeometry(
        screenFrame: CGRect(x: 0, y: 0, width: 1470, height: 956),
        leftAreaWidth: 645.5,
        rightAreaWidth: 645.5,
        notchHeight: 32,
        kind: .hardware
    )

    static let previewVirtual = NotchGeometry(
        screenFrame: CGRect(x: 0, y: 0, width: 1470, height: 956),
        leftAreaWidth: 645,
        rightAreaWidth: 645,
        notchHeight: 24,
        kind: .virtual
    )
}

#Preview("Collapsed · hardware") {
    NotchView(viewModel: NotchViewModel(geometry: .previewHardware))
        .frame(width: 400, height: 150)
}

#Preview("Collapsed · virtual") {
    NotchView(viewModel: NotchViewModel(geometry: .previewVirtual))
        .frame(width: 400, height: 150)
}

#Preview("Expanded") {
    let model = NotchViewModel(geometry: .previewHardware)
    model.presentation = .expanded
    return NotchView(viewModel: model)
        .frame(width: 400, height: 150)
}

#Preview("Activity · charging") {
    ChargingBattery(status: BatteryStatus(level: 78, isCharging: true, isPluggedIn: true), startsFinished: true)
        .padding()
        .background(.black)
}

/// A tab's icon, with its title when there's room for it.
private struct TabLabelStyle: LabelStyle {
    let showsTitle: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: TabBarLayout.iconTitleGap) {
            configuration.icon
                .frame(width: TabBarLayout.iconWidth)
            if showsTitle {
                configuration.title
                    .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .leading)))
            }
        }
    }
}

extension EnvironmentValues {
    @Entry var hapticFeedbackEnabled: Bool = false
}
