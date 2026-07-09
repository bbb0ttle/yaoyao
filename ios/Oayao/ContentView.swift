import SwiftUI

struct ContentView: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                CanvasView()
                    .ignoresSafeArea()

//                ForecastView()
//                    .frame(maxWidth: .infinity)
//                    .cornerRadius(12)
//                    .padding(.horizontal, 16)
//                    .padding(.bottom, 16)
//                    .allowsHitTesting(true)
            }
        }
    }
}
