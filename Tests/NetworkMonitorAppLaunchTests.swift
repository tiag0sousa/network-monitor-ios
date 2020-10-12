//
// Copyright (c) 2020, Farfetch.
// All rights reserved.
//
// This source code is licensed under the MIT-style license found in the
// LICENSE file in the root directory of this source tree.
//

import Foundation
import XCTest

@testable import FNMNetworkMonitor

class NetworkMonitorTests: NetworkMonitorUnitTests {

    func test() {

        let recordBuilder = FFSDebugEnvironmentHelperRecordBuilder()

        XCTAssertNotNil(FNMNetworkMonitor.shared)
        XCTAssertEqual(self.networkMonitor.records.count, 0)

        self.networkMonitor.configure(profiles: Constants.Sites.allCases.map { $0.profile })
        self.networkMonitor.clear(completion: { } )
        FNMNetworkMonitor.registerToLoadingSystem()
        FNMNetworkMonitor.shared.startMonitoring()
        FNMNetworkMonitor.shared.passiveExportPreference = .on(setting: .unlimited)

        let debugListingViewController = FNMDebugListingViewController()
        debugListingViewController.view.layoutIfNeeded()

        let robotsExpectation = expectation(description: "Some Robots")

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { recordBuilder.recordProgress(.overall, dateType: .start) }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { recordBuilder.recordProgress(.firstPartyFramework, dateType: .start) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { recordBuilder.recordProgress(.firstPartyFramework, dateType: .end) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {

            recordBuilder.recordProgress(.thirdPartyFramework, dateType: .start)

            self.reachSitesSequencially(sites: [.alphabet],
                                        completion: {})
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { recordBuilder.recordProgress(.thirdPartyFramework, dateType: .end) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {

            recordBuilder.recordProgress(.firstPartyAPISetup, dateType: .start)

            self.reachSitesSequencially(sites: [.intel],
                                        completion: {})
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) { recordBuilder.recordProgress(.firstPartyAPISetup, dateType: .end) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { recordBuilder.recordProgress(.uiSetup, dateType: .start) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 9) { recordBuilder.recordProgress(.uiSetup, dateType: .end) }

        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { recordBuilder.recordProgress(.overall, dateType: .end)

            self.commit(from: recordBuilder)

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { robotsExpectation.fulfill() }
        }

        waitForExpectations(timeout: 60) { _ in

            /// The files arent decodable, so lets just check for the string count. We just want to make sure something is being written out
            XCTAssertGreaterThan(self.exportFileCount, 1000)
        }
    }
}

private extension NetworkMonitorTests {

    enum FFSLaunchDateType: Int {

        case start
        case end
    }

    enum FFSLaunchReportElement: Int {

        private enum Constants {

            static let overall = "overall"
            static let thirdPartyFramework = "thirdPartyFramework"
            static let firstPartyFramework = "firstPartyFramework"
            static let firstPartyAPISetup = "firstPartyAPISetup"
            static let uiSetup = "uiSetup"
        }

        case overall
        case thirdPartyFramework
        case firstPartyFramework
        case firstPartyAPISetup
        case uiSetup

        func elementIdentifier() -> String {

            switch self {

            case .overall: return Constants.overall
            case .thirdPartyFramework: return Constants.thirdPartyFramework
            case .firstPartyFramework: return Constants.firstPartyFramework
            case .firstPartyAPISetup: return Constants.firstPartyAPISetup
            case .uiSetup: return Constants.uiSetup
            }
        }
    }

    class FFSElementBuilder {

        var identifier: String
        var start: Date?
        var end: Date?

        init(identifier: String) {

            self.identifier = identifier
        }

        func build() -> FNMElement? {

            guard let start = self.start, let end = self.end else {

                return nil
            }

            return FNMElement(identifier: self.identifier,
                                       start: start,
                                       end: end,
                                       subElements: [])
        }
    }

    class FFSDebugEnvironmentHelperRecordBuilder: NSObject {

        var overall = FFSElementBuilder(identifier: FFSLaunchReportElement.overall.elementIdentifier())
        var thirdPartyFrameworkSetup = FFSElementBuilder(identifier: FFSLaunchReportElement.thirdPartyFramework.elementIdentifier())
        var firstPartyFrameworkSetup = FFSElementBuilder(identifier: FFSLaunchReportElement.firstPartyFramework.elementIdentifier())
        var firstPartyAPISetup = FFSElementBuilder(identifier: FFSLaunchReportElement.firstPartyAPISetup.elementIdentifier())
        var uiSetup = FFSElementBuilder(identifier: FFSLaunchReportElement.uiSetup.elementIdentifier())

        func recordProgress(_ elementType: FFSLaunchReportElement, dateType: FFSLaunchDateType) {

            let date = Date()

            var element: FFSElementBuilder?

            switch elementType {

            case .overall:
                element = self.overall
            case .thirdPartyFramework:
                element = self.thirdPartyFrameworkSetup
            case .firstPartyFramework:
                element = self.firstPartyFrameworkSetup
            case .firstPartyAPISetup:
                element = self.firstPartyAPISetup
            case .uiSetup:
                element = self.uiSetup
            }

            switch dateType {
            case .start:
                element?.start = date
            case .end:
                element?.end = date
            }
        }
    }

    func commit(from recordBuilder: FFSDebugEnvironmentHelperRecordBuilder) {

        guard let overall = recordBuilder.overall.build(),
            let thirdPartyFrameworkSetup = recordBuilder.thirdPartyFrameworkSetup.build(),
            let firstPartyFrameworkSetup = recordBuilder.firstPartyFrameworkSetup.build(),
            let firstPartyAPISetup = recordBuilder.firstPartyAPISetup.build(),
            let uiSetup = recordBuilder.uiSetup.build() else {

                assertionFailure("Cannot commit record with insufficient data")
                return
        }

        let firstPartyRequestNodes: [FNMRequestNode] = FNMRequestNode.decodedElements(from: Bundle.main,
                                                                                                        filename: Constants.coldStartFirstPartyCallsFilename)
        let thirdPartyRequestNodes: [FNMRequestNode] = FNMRequestNode.decodedElements(from: Bundle.main,
                                                                                                        filename: Constants.coldStartThirdPartyCallsFilename)

        let timestamps = ["overall": overall,
                          "thirdPartyFrameworkSetup": thirdPartyFrameworkSetup,
                          "firstPartyFrameworkSetup": firstPartyFrameworkSetup,
                          "firstPartyAPISetup": firstPartyAPISetup,
                          "uiSetup": uiSetup]

        let record = FNMRecord(version: "1.0.0",
                                                 freshInstall: false,
                                                 timestamps: timestamps,
                                                 requestCluster: (firstPartyRequestNodes, thirdPartyRequestNodes))

        FNMNetworkMonitor.shared.exportData(record: record)
    }

    var exportFileCount: Int {

        do {

            let currentRunConfigurationFile = try String(contentsOf: FNMRecordExporter.currentRunConfigurationFilenameURL(),
                                                         encoding: .utf8)

            return currentRunConfigurationFile.count

        } catch {

            return 0
        }
    }
}
