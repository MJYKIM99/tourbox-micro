# TourBox preset: Codex Micro Advanced

The table below is the default mapping. In TourBox Micro 0.2 and later, all
press actions except Short and Tour can be changed under **设置… → 控制映射**;
the imported TourBox Console preset does not need to be regenerated.

Generate and import this as a **new** preset in TourBox Console. Keep existing
presets such as `vibe coding` untouched.

## Required preset mode

The included generator derives the preset from TourBox Console's official
`Max_MacOS_zh_CN.tb` template, which already assigns **Max/MSP** output actions
to every physical control.

For the imported Codex preset, enable automatic switching, associate it with
the ChatGPT desktop app, and turn off TourBox's static HUD. TourBox Micro
provides its own live six-agent status HUD instead.
TourBox Console then connects to the local TCP server on port `50500`; the
TourBox Micro app decodes the vendor event bytes itself. This is what enables
real press/release push-to-talk and a custom Tour modifier layer.

Native TourBox combinations should remain empty. The bridge handles its own
combinations from the raw press/release stream.

## Physical mapping

| TourBox control | Codex action | Output |
|---|---|---|
| Knob rotate | Decrease/increase reasoning effort | `F17` / `F16` (bind once in Codex) |
| Knob press | Open model picker | `⌃⇧M` |
| Scroll wheel | Scroll conversation | Native scroll event |
| Scroll press | Jump to latest message | `⌘↓` |
| Dial rotate | Previous/next assigned chat | `codex://threads/<id>` |
| Dial press | Search all chats | `⌘G` |
| Top | New independent chat | `⌥⌘O` |
| Tall | Approve or send | `Return` |
| Side | Decline/cancel | `Esc` |
| Short (hold) | Push-to-talk; release stops dictation | Press/release PTT shortcut |
| C1 | Copy in the frontmost app | `⌘C` |
| C2 | Paste in the frontmost app | `⌘V` |
| D-pad Up | Trigger screenshot utility | `⇧⌘2` |
| D-pad Right | Next recently viewed chat | `⌃Tab` |
| D-pad Down | Toggle review panel | `⌥⌘B` |
| D-pad Left | Previous recently viewed chat | `⌃⇧Tab` |
| Tour tap | Show/hide six-agent HUD | Internal action |
| Tour + Knob press | Quick chat | `⌥⌘N` |
| Tour + Scroll press | Find in current chat | `⌘F` |
| Tour + Dial press | Open command menu | `⌘K` |
| Tour + Top | Search project files | `⌘P` |
| Tour + C1 | Agent slot 1 | Codex deep link |
| Tour + C2 | Agent slot 2 | Codex deep link |
| Tour + Up | Agent slot 3 | Codex deep link |
| Tour + Right | Agent slot 4 | Codex deep link |
| Tour + Down | Agent slot 5 | Codex deep link |
| Tour + Left | Agent slot 6 | Codex deep link |

Copy, paste, and screenshot are deliberately sent to the current frontmost
application. Every Codex-specific shortcut activates Codex first. This keeps
general clipboard actions useful without hijacking focus.

## Vendor event bytes used by the bridge

The event map below comes from TourBox's official `startTBService.js` Max/MSP
sample.

| Control | Press / positive | Release / negative |
|---|---:|---:|
| Knob | 55 / CW 196 | 183 / CCW 132 |
| Scroll | 10 / Up 201 | 138 / Down 137 |
| Dial | 56 / CW 207 | 184 / CCW 143 |
| Tall | 0 | 128 |
| Short | 3 | 131 |
| Top | 2 | 130 |
| Side | 1 | 129 |
| Up | 16 | 144 |
| Down | 17 | 145 |
| Left | 18 | 146 |
| Right | 19 | 147 |
| Tour | 42 | 170 |
| C1 | 34 | 162 |
| C2 | 35 | 163 |

## C1/C2 preset repair

TourBox Console 5.2.6 can import the vendor Max/MSP preset without assigning
Max/MSP output to Elite C1 and C2. The hardware still appears in Console logs,
but neither the base actions nor `Tour + C1/C2` reach TourBox Micro. Generate
and import the corrected preset described in the README; it copies the
device-adapted preset and binds event 34 and 35 to the same Max/MSP action as
the other buttons.
