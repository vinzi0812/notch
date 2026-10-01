//
//  NotchGeometry.swift
//  Notch
//
//  Created by Vineet Parmar on 26/09/26.
//

import AppKit

struct NotchGeometry {
    
    static let defaultExpandedWidth: CGFloat = 540
    static let expandedHeight: CGFloat = 150
    /// Extra height for a full-width headline row (the media player) above the module columns.
    static let headlineHeight: CGFloat = 74

    /// The expanded width the user chose in Settings.
    var expandedWidth: CGFloat = NotchGeometry.defaultExpandedWidth
    /// Whether the collapsed notch has ears beside the camera; without them it's just the notch.
    var showsEars = true

    /// How much taller than "tall" a page may make the notch: the calendar's month-above layout.
    /// Zero unless that layout is chosen, so the panel only grows when something uses the room.
    var extraPageHeight: CGFloat = 0

    /// The month-above calendar's extra height (a 330 pt notch instead of 224).
    static let calendarMonthAboveExtra: CGFloat = 106

    /// The notch with the player row or a tall page.
    var tallHeight: CGFloat { Self.expandedHeight + Self.headlineHeight }

    func expandedSize(height: CGFloat) -> CGSize {
        CGSize(width: expandedWidth, height: height)
    }

    func expandedSize(withHeadline: Bool) -> CGSize {
        expandedSize(height: withHeadline ? tallHeight : Self.expandedHeight)
    }

    /// The panel is sized for the tallest state, so it never resizes while in use; the shape grows
    /// inside it. (It's rebuilt when the screen, the chosen width or the calendar layout changes.)
    var panelSize: CGSize { expandedSize(height: tallHeight + extraPageHeight) }
    static let activityEarWidth: CGFloat = 80
    static let activityDetailHeight: CGFloat = 26
    let screenFrame: CGRect
    let notchRect: CGRect
    enum Kind { case hardware, virtual }
    let kind: Kind
    static let virtualNotchSize = CGSize(width: 180, height: 24)
    static let earWidth: CGFloat = 40
    
    var collapsedRect: CGRect {
        switch kind {
        case .hardware where showsEars: notchRect.insetBy(dx: -Self.earWidth, dy: 0)
        case .hardware: notchRect
        case .virtual:  notchRect
        }
    }
    
    init(screenFrame: CGRect, leftAreaWidth: CGFloat, rightAreaWidth: CGFloat, notchHeight: CGFloat, kind: Kind) {
        self.screenFrame = screenFrame
        self.notchRect = CGRect(
            x: screenFrame.minX + leftAreaWidth,
            y: screenFrame.maxY - notchHeight,
            width: screenFrame.width - leftAreaWidth - rightAreaWidth,
            height: notchHeight
        )
        self.kind = kind
    }
    
    init(screen: NSScreen) {
        if let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea,
           screen.safeAreaInsets.top > 0 {
            self.init(screenFrame: screen.frame,
                      leftAreaWidth: left.width,
                      rightAreaWidth: right.width,
                      notchHeight: screen.safeAreaInsets.top,
                      kind: .hardware
            )
        } else {
            let sideWidth = (screen.frame.width - Self.virtualNotchSize.width) / 2
            self.init(screenFrame: screen.frame,
                      leftAreaWidth: sideWidth,
                      rightAreaWidth: sideWidth,
                      notchHeight: Self.virtualNotchSize.height,
                      kind: .virtual
            )
        }
    }
    
    var activitySize: CGSize {
        CGSize(
            width: notchRect.width + 2 * Self.activityEarWidth,
            height: notchRect.height + Self.activityDetailHeight
        )
    }

    /// Where the pointer has to be for the notch to open (or stay open).
    /// A file drag opens it from anywhere over the expanded area, so the user never has to
    /// push against the top edge of the screen, which would trigger Mission Control.
    func hoverTarget(isExpanded: Bool, hasHeadline: Bool = false, isDraggingFile: Bool) -> CGRect {
        hoverTarget(isExpanded: isExpanded, height: hasHeadline ? tallHeight : Self.expandedHeight, isDraggingFile: isDraggingFile)
    }

    /// The same, for an open notch of any height.
    func hoverTarget(isExpanded: Bool, height: CGFloat, isDraggingFile: Bool) -> CGRect {
        let target: CGRect
        if isExpanded {
            target = expandedRect(height: height)
        } else if isDraggingFile {
            target = expandedRect(withHeadline: false)
        } else {
            target = collapsedRect
        }
        return target.insetBy(dx: 0, dy: -1)
    }

    /// Where the expanded shape actually is: the visible part of the panel.
    func expandedRect(withHeadline: Bool) -> CGRect {
        expandedRect(height: withHeadline ? tallHeight : Self.expandedHeight)
    }

    func expandedRect(height: CGFloat) -> CGRect {
        let size = expandedSize(height: height)
        return CGRect(x: notchRect.midX - size.width / 2, y: screenFrame.maxY - size.height, width: size.width, height: size.height)
    }

    var panelRect: CGRect {
        CGRect(
            x: notchRect.midX - panelSize.width / 2,
            y: screenFrame.maxY - panelSize.height,
            width: panelSize.width,
            height: panelSize.height
        )
    }
    
}
