import CoreLocation
import Foundation

/// 촬영 위치를 한국어 지명으로 바꾼다. 애플 서버에 좌표만 보낸다 (사진은 보내지 않음).
final class PlaceResolver: @unchecked Sendable {
    private let geocoder = CLGeocoder()
    private let locale = Locale(identifier: "ko_KR")
    /// 애플 지오코딩 속도 제한을 지키기 위한 요청 간격
    let interval: Duration = .milliseconds(1200)

    enum Outcome {
        case resolved(PlaceInfo)
        /// 네트워크 문제 등으로 지금은 할 수 없음 (나중에 다시 시도)
        case retryLater
    }

    func resolve(lat: Double, lon: Double) async -> Outcome {
        let location = CLLocation(latitude: lat, longitude: lon)
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location, preferredLocale: locale)
            guard let mark = placemarks.first else { return .resolved(.empty) }
            return .resolved(
                PlaceInfo(
                    country: mark.country, admin: mark.administrativeArea, locality: mark.locality,
                    subLocality: mark.subLocality, name: mark.name))
        } catch let error as CLError where error.code == .geocodeFoundNoResult {
            return .resolved(.empty)
        } catch {
            return .retryLater
        }
    }
}
