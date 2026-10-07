//
//  NotchPanel.swift
//  Notch
//
//  Created by Vineet Parmar on 25/09/26.
//

import AppKit

final class NotchPanel: NSPanel {
    
    init(contentRect: CGRect) {
        super.init(
            contentRect: contentRect,
            styleMask:[.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        
        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary,
            .ignoresCycle
        ]
        
        becomesKeyOnlyIfNeeded = true
    }
    
    override var canBecomeKey: Bool { true }

    override var canBecomeMain: Bool { true }
    
}
