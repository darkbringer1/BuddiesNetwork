import Foundation
import OSLog

struct AppLogger {
    let bundle: String
    let category: String

    private let logger: Logger

    init(bundle: String = Bundle.main.bundleIdentifier ?? "", category: String) {
        self.bundle = bundle
        self.category = category
        logger = Logger(subsystem: bundle, category: category)
    }

    func error(_ error: Error) {
        logger.error("\(error.localizedDescription)")
    }

    func error(_ str: String) {
        logger.error("\(str)")
    }

    func warning(_ str: String) {
        logger.warning("\(str)")
    }

    func debug(_ str: String?) {
        logger.debug("\(str ?? "")")
    }

    func info(_ str: String) {
        logger.info("\(str)")
    }
}
