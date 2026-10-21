import WidgetKit
import SwiftUI
import AppKit
@main struct R { @MainActor static func main() {
let now = Date()
var s = UsageSnapshot.placeholder
s.email = "voce@exemplo.com"; s.plan = "Max 5x"
s.fiveHour = .init(utilization: 62, resetsAt: now.addingTimeInterval(2*3600+14*60))
s.sevenDay = .init(utilization: 38, resetsAt: now.addingTimeInterval(3*86400+5*3600))
s.scoped = [.init(name: "Opus", percent: 21)]
s.breakdown = [.init(name: "Claude Code", percent: 84), .init(name: "Chats", percent: 11), .init(name: "Cowork", percent: 5)]
s.fetchedAt = now
s.modelsSession = UsageSnapshot.placeholder.modelsSession
s.modelsWeek = UsageSnapshot.placeholder.modelsWeek
let sizes: [(WidgetFamily, CGSize, String)] = [(.systemSmall, .init(width: 158, height: 158), "small"), (.systemMedium, .init(width: 364, height: 158), "medium"), (.systemLarge, .init(width: 364, height: 382), "large"), (.systemExtraLarge, .init(width: 760, height: 382), "xlarge")]
for dark in [false, true] { for (fam, size, name) in sizes {
  let v = UsageWidgetView(family: fam, entry: Entry(date: now, snapshot: s))
    .padding(16).frame(width: size.width, height: size.height)
    .background(RoundedRectangle(cornerRadius: 22).fill(dark ? Color(white: 0.17) : Color(white: 0.96)))
    .padding(20).environment(\.colorScheme, dark ? .dark : .light)
  let r = ImageRenderer(content: v); r.scale = 2
  let rep = NSBitmapImageRep(cgImage: r.cgImage!)
  try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "docs/images/widget-\(name)\(dark ? "-dark" : "").png"))
}}}}
