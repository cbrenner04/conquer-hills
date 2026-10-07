import Foundation
import os

/// Decodes and validates course files.
public enum CourseLoader {
    /// Course files are named `<id>.course.json`.
    public static let fileSuffix = ".course.json"

    private static let logger = Logger(subsystem: "com.hills-app.conquerhills", category: "CourseLoader")

    /// Decodes and validates one course file, reporting every problem found.
    public static func load(_ data: Data, fileName: String) -> Result<Course, CourseValidationFailure> {
        func failure(_ problems: [CourseProblem]) -> Result<Course, CourseValidationFailure> {
            .failure(CourseValidationFailure(fileName: fileName, problems: problems))
        }

        // Check the version first: a file from a newer schema may not decode as this one.
        let version: Int
        do {
            version = try JSONDecoder().decode(SchemaVersionProbe.self, from: data).schemaVersion
        } catch {
            return failure([problem(for: error)])
        }
        guard version == CourseFile.supportedSchemaVersion else {
            return failure([.unsupportedSchemaVersion(version)])
        }

        let file: CourseFile
        do {
            file = try JSONDecoder().decode(CourseFile.self, from: data)
        } catch {
            return failure([problem(for: error)])
        }

        let problems = file.problems(fileName: fileName)
        return problems.isEmpty ? .success(Course(validated: file)) : failure(problems)
    }

    /// Loads every `*.course.json` file in `directory`, sorted by file name. Invalid files are left out, logged,
    /// and returned as failures rather than thrown.
    public static func loadAll(in directory: URL) -> (courses: [Course], failures: [CourseValidationFailure]) {
        let fileNames: [String]
        do {
            fileNames = try FileManager.default.contentsOfDirectory(atPath: directory.path)
                .filter { $0.hasSuffix(fileSuffix) }
                .sorted()
        } catch {
            let failure = CourseValidationFailure(
                fileName: directory.lastPathComponent, problems: [.unreadable(error.localizedDescription)])
            logger.error("Could not list courses: \(failure.description, privacy: .public)")
            return ([], [failure])
        }

        var courses: [Course] = []
        var failures: [CourseValidationFailure] = []
        for fileName in fileNames {
            let result: Result<Course, CourseValidationFailure>
            do {
                result = load(try Data(contentsOf: directory.appending(path: fileName)), fileName: fileName)
            } catch {
                result = .failure(
                    CourseValidationFailure(fileName: fileName, problems: [.unreadable(error.localizedDescription)]))
            }
            switch result {
            case .success(let course):
                courses.append(course)
            case .failure(let failure):
                logger.error("Skipping invalid course: \(failure.description, privacy: .public)")
                failures.append(failure)
            }
        }
        return (courses, failures)
    }

    private struct SchemaVersionProbe: Decodable {
        let schemaVersion: Int
    }

    private static func problem(for error: any Error) -> CourseProblem {
        switch error {
        case let error as UnknownFieldError:
            return .unknownField(path: path(error.codingPath))
        case DecodingError.keyNotFound(let key, let context):
            return .missingField(path: path(context.codingPath + [key]))
        case DecodingError.valueNotFound(_, let context):
            return .missingField(path: path(context.codingPath))
        case DecodingError.typeMismatch(_, let context), DecodingError.dataCorrupted(let context):
            let location = context.codingPath.isEmpty ? "" : " at \(path(context.codingPath))"
            return .unreadable(context.debugDescription + location)
        default:
            return .unreadable(String(describing: error))
        }
    }

    /// Formats a coding path like `source.route.name` or `inclineChanges[2].atMeters`.
    private static func path(_ codingPath: [any CodingKey]) -> String {
        codingPath.reduce(into: "") { result, key in
            if let index = key.intValue {
                result += "[\(index)]"
            } else {
                result += result.isEmpty ? key.stringValue : ".\(key.stringValue)"
            }
        }
    }
}
