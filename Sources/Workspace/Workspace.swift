// Sources/Workspace/Workspace.swift — extrait
public struct Diagnostic: Sendable {
	public enum Severity: String, Sendable { case info, warning, error, hint, unknown }
	public var message: String
	public var line: Int
	public var column: Int
	public var severity: Severity
	
	public init(message: String, line: Int = 1, column: Int = 1, severity: Severity = .error) {
		self.message = message
		self.line = line
		self.column = column
		self.severity = severity
	}
}
