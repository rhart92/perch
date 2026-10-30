import SwiftUI

struct GitHubMark: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        return Self.outline.applying(CGAffineTransform(
            a: scale, b: 0, c: 0, d: scale,
            tx: rect.midX - 12 * scale, ty: rect.midY - 12 * scale
        ))
    }

    private static let outline = Path { path in
        path.move(to: CGPoint(x: 12.000000, y: 0.750000))
        path.addCurve(to: CGPoint(x: 0.901106, y: 10.196530), control1: CGPoint(x: 6.485040, y: 0.752750), control2: CGPoint(x: 1.785200, y: 4.752895))
        path.addCurve(to: CGPoint(x: 8.440000, y: 22.670000), control1: CGPoint(x: 0.017012, y: 15.640165), control2: CGPoint(x: 3.209366, y: 20.922072))
        path.addCurve(to: CGPoint(x: 9.210000, y: 22.130000), control1: CGPoint(x: 9.000000, y: 22.770000), control2: CGPoint(x: 9.210000, y: 22.430000))
        path.addLine(to: CGPoint(x: 9.210000, y: 20.030000))
        path.addCurve(to: CGPoint(x: 5.420000, y: 18.700000), control1: CGPoint(x: 6.080000, y: 20.710000), control2: CGPoint(x: 5.420000, y: 18.700000))
        path.addCurve(to: CGPoint(x: 4.170000, y: 17.060000), control1: CGPoint(x: 4.910000, y: 17.400000), control2: CGPoint(x: 4.170000, y: 17.060000))
        path.addCurve(to: CGPoint(x: 4.250000, y: 16.370000), control1: CGPoint(x: 3.150000, y: 16.360000), control2: CGPoint(x: 4.250000, y: 16.370000))
        path.addCurve(to: CGPoint(x: 5.980000, y: 17.530000), control1: CGPoint(x: 5.380000, y: 16.450000), control2: CGPoint(x: 5.980000, y: 17.530000))
        path.addCurve(to: CGPoint(x: 9.250000, y: 18.460000), control1: CGPoint(x: 6.980000, y: 19.250000), control2: CGPoint(x: 8.610000, y: 18.750000))
        path.addCurve(to: CGPoint(x: 9.960000, y: 16.960000), control1: CGPoint(x: 9.350000, y: 17.730000), control2: CGPoint(x: 9.640000, y: 17.240000))
        path.addCurve(to: CGPoint(x: 4.830000, y: 11.400000), control1: CGPoint(x: 7.460000, y: 16.680000), control2: CGPoint(x: 4.830000, y: 15.710000))
        path.addCurve(to: CGPoint(x: 5.990000, y: 8.380000), control1: CGPoint(x: 4.830000, y: 10.170000), control2: CGPoint(x: 5.270000, y: 9.170000))
        path.addCurve(to: CGPoint(x: 6.100000, y: 5.400000), control1: CGPoint(x: 5.870000, y: 8.100000), control2: CGPoint(x: 5.490000, y: 6.950000))
        path.addCurve(to: CGPoint(x: 9.190000, y: 6.550000), control1: CGPoint(x: 6.100000, y: 5.400000), control2: CGPoint(x: 7.050000, y: 5.100000))
        path.addCurve(to: CGPoint(x: 14.810000, y: 6.550000), control1: CGPoint(x: 11.030191, y: 6.051656), control2: CGPoint(x: 12.969809, y: 6.051656))
        path.addCurve(to: CGPoint(x: 17.900000, y: 5.400000), control1: CGPoint(x: 16.960000, y: 5.100000), control2: CGPoint(x: 17.900000, y: 5.400000))
        path.addCurve(to: CGPoint(x: 18.010000, y: 8.380000), control1: CGPoint(x: 18.510000, y: 6.950000), control2: CGPoint(x: 18.130000, y: 8.100000))
        path.addCurve(to: CGPoint(x: 19.170000, y: 11.400000), control1: CGPoint(x: 18.740000, y: 9.170000), control2: CGPoint(x: 19.170000, y: 10.170000))
        path.addCurve(to: CGPoint(x: 14.030000, y: 16.950000), control1: CGPoint(x: 19.170000, y: 15.720000), control2: CGPoint(x: 16.540000, y: 16.670000))
        path.addCurve(to: CGPoint(x: 14.790000, y: 19.030000), control1: CGPoint(x: 14.430000, y: 17.300000), control2: CGPoint(x: 14.790000, y: 17.980000))
        path.addLine(to: CGPoint(x: 14.790000, y: 22.130000))
        path.addCurve(to: CGPoint(x: 15.560000, y: 22.670000), control1: CGPoint(x: 14.790000, y: 22.430000), control2: CGPoint(x: 14.990000, y: 22.780000))
        path.addCurve(to: CGPoint(x: 23.098894, y: 10.196530), control1: CGPoint(x: 20.790634, y: 20.922072), control2: CGPoint(x: 23.982988, y: 15.640165))
        path.addCurve(to: CGPoint(x: 12.000000, y: 0.750000), control1: CGPoint(x: 22.214800, y: 4.752895), control2: CGPoint(x: 17.514960, y: 0.752750))
        path.closeSubpath()
    }
}
