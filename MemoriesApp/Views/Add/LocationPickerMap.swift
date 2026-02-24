//
//  LocationPickerMap.swift
//  MemoriesApp
//

import SwiftUI
import MapKit
import CoreLocation
import Foundation

struct LocationPickerMap: View {
    @Binding var coordinate: CLLocationCoordinate2D?
    @Binding var locationName: String
    /// 可选：初始地图区域（如 Story 范围），便于在已知区域选点
    var initialRegion: MKCoordinateRegion?
    
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 39.9, longitude: 116.4),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
    )
    @State private var lastCoordinateString: String = ""
    @State private var didApplyInitialRegion = false
    @State private var didTryUserLocation = false
    @StateObject private var locationHelper = LocationPickerLocationHelper()
    private static let defaultRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.9, longitude: 116.4),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    
    /// 将坐标转换为字符串用于比较
    private var coordinateString: String {
        guard let coord = coordinate else { return "" }
        return "\(coord.latitude),\(coord.longitude)"
    }

    var body: some View {
        MapReader { proxy in
            Map(position: $cameraPosition) {
                if let coord = coordinate {
                    Annotation(locationName.isEmpty ? "选中的位置" : locationName, coordinate: coord) {
                        ZStack {
                            Circle()
                                .fill(.white)
                                .frame(width: 32, height: 32)
                                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                            Image(systemName: "mappin.circle.fill")
                                .foregroundStyle(AppTheme.accent)
                                .font(.title2)
                        }
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
            .onTapGesture { screenCoord in
                let mapCoord = proxy.convert(screenCoord, from: .local)
                if let c = mapCoord {
                    coordinate = c
                    reverseGeocode(coordinate: c)
                }
            }
            .onChange(of: coordinateString) { _, newString in
                guard newString != lastCoordinateString, let coord = coordinate else { return }
                lastCoordinateString = newString
                withAnimation(.easeInOut(duration: 0.5)) {
                    cameraPosition = .region(MKCoordinateRegion(
                        center: coord,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    ))
                }
            }
            .onAppear {
                if !didApplyInitialRegion, let region = initialRegion {
                    didApplyInitialRegion = true
                    cameraPosition = .region(region)
                } else if let coord = coordinate {
                    cameraPosition = .region(MKCoordinateRegion(
                        center: coord,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    ))
                } else if !didTryUserLocation {
                    didTryUserLocation = true
                    locationHelper.requestAndFetchLocation()
                }
            }
            .onChange(of: locationHelper.latestCoordinate) { _, newCoord in
                guard let coord = newCoord else { return }
                withAnimation(.easeInOut(duration: 0.4)) {
                    cameraPosition = .region(MKCoordinateRegion(
                        center: coord,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    ))
                }
            }
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .bottomTrailing) {
            Button {
                if let coord = locationHelper.latestCoordinate {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        cameraPosition = .region(MKCoordinateRegion(
                            center: coord,
                            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                        ))
                    }
                }
                locationHelper.requestAndFetchLocation()
            } label: {
                Image(systemName: "location.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(AppTheme.accent))
            }
            .padding(10)
        }
    }
    
    private func reverseGeocode(coordinate: CLLocationCoordinate2D) {
        Task {
            if let name = await GeocodeService.landmarkStyleName(coordinate: coordinate) {
                await MainActor.run {
                    locationName = name
                }
            }
        }
    }
    
}

// MARK: - 定位到当前所在位置
private final class LocationPickerLocationHelper: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var latestCoordinate: CLLocationCoordinate2D?
    private let manager = CLLocationManager()
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }
    
    func requestAndFetchLocation() {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            // 先尝试用系统缓存的当前位置，立即生效
            if let loc = manager.location {
                DispatchQueue.main.async { [weak self] in
                    self?.latestCoordinate = loc.coordinate
                }
            }
            manager.requestLocation()
            // 若上面没有缓存，约 1 秒后再读一次（requestLocation 可能稍晚回调）
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self = self else { return }
                if self.latestCoordinate == nil, let loc = self.manager.location {
                    self.latestCoordinate = loc.coordinate
                }
            }
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            break
        }
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            if let loc = manager.location {
                DispatchQueue.main.async { [weak self] in
                    self?.latestCoordinate = loc.coordinate
                }
            }
            manager.requestLocation()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coord = locations.last?.coordinate else { return }
        DispatchQueue.main.async { [weak self] in
            self?.latestCoordinate = coord
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

// MARK: - CLLocationCoordinate2D Equatable（供 onChange 等比较使用）
extension CLLocationCoordinate2D: @retroactive Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State var coord: CLLocationCoordinate2D?
        @State var name = ""
        var body: some View {
            LocationPickerMap(coordinate: $coord, locationName: $name)
        }
    }
    return PreviewWrapper()
}
