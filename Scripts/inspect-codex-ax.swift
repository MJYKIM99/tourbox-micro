#!/usr/bin/env swift

import AppKit
import ApplicationServices

private func axString(_ element: AXUIElement, _ attribute: CFString) -> String {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
          let value else {
        return ""
    }
    if let string = value as? String {
        return string.replacingOccurrences(of: "\n", with: " ")
    }
    if CFGetTypeID(value) == AXUIElementGetTypeID() {
        return "<element>"
    }
    return String(describing: value)
}

guard let app = NSRunningApplication.runningApplications(
    withBundleIdentifier: "com.openai.codex"
).first else {
    fatalError("ChatGPT is not running")
}

let root = AXUIElementCreateApplication(app.processIdentifier)
var queue: [(element: AXUIElement, depth: Int)] = [(root, 0)]
var index = 0

while index < queue.count, index < 10_000 {
    let (element, depth) = queue[index]
    index += 1

    let fields = [
        axString(element, kAXRoleAttribute as CFString),
        axString(element, kAXSubroleAttribute as CFString),
        axString(element, kAXTitleAttribute as CFString),
        axString(element, kAXDescriptionAttribute as CFString),
        axString(element, kAXValueAttribute as CFString),
        axString(element, kAXIdentifierAttribute as CFString),
        axString(element, kAXHelpAttribute as CFString)
    ]
    if fields.contains(where: { !$0.isEmpty }) {
        var actions: CFArray?
        AXUIElementCopyActionNames(element, &actions)
        let actionNames = (actions as? [String] ?? []).joined(separator: ",")
        print(([String(depth)] + fields + [actionNames]).joined(separator: "|"))
    }

    guard depth < 32 else { continue }
    var childrenValue: CFTypeRef?
    if AXUIElementCopyAttributeValue(
        element,
        kAXChildrenAttribute as CFString,
        &childrenValue
    ) == .success,
       let children = childrenValue as? [AXUIElement] {
        queue.append(contentsOf: children.map { ($0, depth + 1) })
    }
}
