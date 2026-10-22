import SwiftUI

struct MascotView: View {
    let working: Bool
    let completion: UUID?
    var size: CGFloat = 178
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var celebrated = false
    @State private var hovering = false
    var body: some View {
        TimelineView(.animation(minimumInterval:working ? 1.0/30:1.0/15,paused:reduceMotion || scenePhase != .active)) { timeline in
            let moving = !reduceMotion && scenePhase == .active
            let time = timeline.date.timeIntervalSinceReferenceDate
            let breath = moving ? sin(time * 1.45):0
            let work = moving && working ? sin(time * 7):0
            let cheer = celebrated && moving
            ZStack {
                if size > 80 {
                    Ellipse().fill(Theme.navy.opacity(0.10))
                        .frame(width:size * (0.52 - 0.025 * breath),height:size * 0.045)
                        .blur(radius:3).offset(y:size * 0.44).accessibilityHidden(true)
                }
                Image(nsImage:AppResources.icon).resizable().scaledToFit().frame(width:size,height:size)
                    .scaleEffect(x:cheer ? 1.055:1 + breath * 0.012 - abs(work) * 0.045,
                                 y:cheer ? 1.055:1 + breath * 0.020 + abs(work) * 0.030)
                    .rotationEffect(.degrees(cheer ? -7:work * 2.5 + (hovering && moving ? -3:0)))
                    .offset(y:cheer ? -size * 0.055:(working ? -abs(work) * size * 0.018:-breath * size * 0.012))
            }.frame(width:size,height:size)
                .overlay(alignment:.bottomTrailing) {
                    if working { Image(systemName:"gearshape.fill").font(.system(size:size * 0.17)).foregroundStyle(Theme.accent).rotationEffect(.degrees(moving ? time.truncatingRemainder(dividingBy:3) * 120:0)).padding(7) }
                    else if celebrated { Image(systemName:"checkmark.circle.fill").font(.system(size:size * 0.18)).foregroundStyle(.green).padding(7) }
                }
        }.accessibilityLabel(working ? "Sıkıştırıcı çalışıyor":"Sıkıştırıcı")
        .onHover { value in
            withAnimation(reduceMotion ? nil:.spring(response:0.35,dampingFraction:0.65)) { hovering = value }
        }
        .task(id:completion) {
            guard completion != nil else { return }
            withAnimation(reduceMotion ? nil:.spring(response:0.3,dampingFraction:0.5)) { celebrated = true }
            try? await Task.sleep(for:.seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil:.easeOut) { celebrated = false }
        }
    }
}
