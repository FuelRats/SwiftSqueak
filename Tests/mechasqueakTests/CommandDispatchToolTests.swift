import XCTest

@testable import mechasqueak

final class CommandDispatchToolTests: XCTestCase {
    private func declaration(
        _ names: [String],
        category: HelpCategory?,
        permission: AccountPermission? = nil,
        allowTool: Bool
    ) -> IRCBotCommandDeclaration {
        IRCBotCommandDeclaration(
            commands: names,
            parameters: [],
            category: category,
            description: "test",
            permission: permission,
            cooldownOverride: nil,
            allowTool: allowTool)
    }

    // MARK: - Gate

    func testAllowToolReadOnlyCommandIsDispatchable() {
        let commands = [declaration(["unfiled", "npw"], category: .rescues, allowTool: true)]
        XCTAssertTrue(CommandDispatchTool.isDispatchable("unfiled", in: commands))
        XCTAssertTrue(CommandDispatchTool.isDispatchable("npw", in: commands), "aliases resolve too")
    }

    func testUnflaggedCommandIsRejected() {
        let commands = [declaration(["system"], category: .board, permission: .RescueWrite, allowTool: false)]
        XCTAssertFalse(CommandDispatchTool.isDispatchable("system", in: commands))
    }

    func testDispatchingCommandIsRejectedEvenIfMistaggedAllowTool() {
        // A rescue-writing board command is a dispatching command; the backstop rejects it even if
        // someone mistakenly set allowTool.
        let commands = [declaration(["clear"], category: .board, permission: .RescueWrite, allowTool: true)]
        XCTAssertFalse(CommandDispatchTool.isDispatchable("clear", in: commands))
    }

    func testUnknownCommandIsRejected() {
        let commands = [declaration(["unfiled"], category: .rescues, allowTool: true)]
        XCTAssertFalse(CommandDispatchTool.isDispatchable("bcancel", in: commands))
    }

    // MARK: - Permission parity

    func testNoPermissionCommandIsOpenToAnyone() {
        let command = declaration(["landmark"], category: .utility, allowTool: true)
        XCTAssertTrue(
            CommandDispatchTool.isPermitted(command, hasPermission: { _ in false }),
            "a command with no permission is dispatchable regardless of the user's permissions")
    }

    func testPermissionedCommandRequiresTheUserToHoldIt() {
        let command = declaration(
            ["unfiled"], category: .rescues, permission: .RescueWriteOwn, allowTool: true)
        XCTAssertTrue(
            CommandDispatchTool.isPermitted(command, hasPermission: { $0 == .RescueWriteOwn }),
            "a user holding the command's permission may dispatch it")
        XCTAssertFalse(
            CommandDispatchTool.isPermitted(command, hasPermission: { _ in false }),
            "a user lacking the command's permission is refused")
    }

    // MARK: - Argument sanitization

    func testLooksUnsafeRejectsFlagsAndSigils() {
        for arg in ["-f", "--force", "-p", "a;rm", "$(x)", "a|b", "\"quoted\"", "`x`"] {
            XCTAssertTrue(CommandDispatchTool.looksUnsafe(arg), "should reject: \(arg)")
        }
    }

    func testLooksUnsafeAllowsPlainPositionalValues() {
        for arg in ["Sol", "Sagittarius A*", "NLTT 48288", "42", "Colonia"] {
            XCTAssertFalse(CommandDispatchTool.looksUnsafe(arg), "should allow: \(arg)")
        }
    }

    // MARK: - Tool wiring

    func testRunCommandToolSchema() throws {
        let tool = CommandDispatchTool.tool
        XCTAssertEqual(tool.name, "run_command")
        guard case let .object(pairs) = tool.inputSchema else {
            return XCTFail("schema must be an object")
        }
        let keyed = Dictionary(pairs, uniquingKeysWith: { first, _ in first })
        XCTAssertEqual(keyed["required"], .array([.string("command")]))
        XCTAssertEqual(keyed["additionalProperties"], .bool(false))
    }
}
