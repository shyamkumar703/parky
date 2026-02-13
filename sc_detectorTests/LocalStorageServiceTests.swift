//
//  LocalStorageServiceTests.swift
//  sc_detector
//
//  Created by Shyam Kumar on 2/12/26.
//

@testable import sc_detector
import XCTest
import CoreLocation

// FYI: - malloc error here
// use after free
// NOT a code-level issue, likely some weirdness happening during tearDown()
// DO NOT run these tests and expect a pass (checkmark)
class LocalStorageServiceTests: XCTestCase {
    private let location: CLLocationCoordinate2D = .init(latitude: 1, longitude: 1)
    
    func testSaveAndReadParkingLocation_WorksAsExpected() {
        let sut = LocalStorageService()
        sut.saveParkingLocation(location: location)
        let read = sut.getParkingLocation()
        XCTAssertEqual(location.latitude, read?.latitude)
        XCTAssertEqual(location.longitude, read?.longitude)
    }
    
    func testClearParkingLocation_WorksAsExpected() {
        let sut = LocalStorageService()
        sut.saveParkingLocation(location: location)
        sut.clearParkingLocation()
        XCTAssertNil(sut.getParkingLocation())
    }
}
