import SwiftUI

struct ProgressBar: View {
    let percent: Double
    let tint: Color
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.15))
                Capsule()
                    .fill(tint)
                    .frame(width: geo.size.width * CGFloat(max(0.02, min(1.0, percent))))
            }
        }
        .frame(height: 6)
    }
}
