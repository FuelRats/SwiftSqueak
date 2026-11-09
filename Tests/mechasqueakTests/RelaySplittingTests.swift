/*
 Copyright 2026 The Fuel Rats Mischief

 Redistribution and use in source and binary forms, with or without modification,
 are permitted provided that the following conditions are met:

 1. Redistributions of source code must retain the above copyright notice,
 this list of conditions and the following disclaimer.

 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following
 disclaimer in the documentation and/or other materials provided with the distribution.

 3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote
 products derived from this software without specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES,
 INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

import IRCKit
import XCTest
@testable import mechasqueak

final class RelaySplittingTests: XCTestCase {
    private let source = "arckoor!arckoor@arckoor.rat.fuelrats.com"
    private let translation = "Щоб запросити когось до своєї команди, перейдіть на панель комунікацій "
        + "(клавіша за замовчуванням 2), натисніть ESC, щоб вийти з чату, і перейдіть на третю панель "
        + "(клавіша за замовчуванням E). Потім виберіть свого Крисаня (Крисанів) і виберіть Запросити до команди"

    private func deliveredLine(_ text: String, command: String = "PRIVMSG", source: String? = nil) -> String {
        return ":\(source ?? self.source) \(command) #fuelrats :\(text)\r\n"
    }

    func testLongCyrillicTranslationIsSplitIntoWholeLinesWithinTheLimit() {
        let lines = IRCClient.relayLines(
            translation, command: "MSGAS", nick: "arckoor", channel: "#fuelrats", source: source,
            relayedCommand: "PRIVMSG", linePrefix: "Guser102: ")

        XCTAssertGreaterThan(lines.count, 1, "the 2026-11-09 translation does not fit one delivered line")
        for line in lines {
            XCTAssertTrue(line.hasPrefix("Guser102: "), "every line highlights the client")
            XCTAssertLessThanOrEqual(deliveredLine(line).utf8.count, 512)
            XCTAssertLessThanOrEqual("MSGAS arckoor #fuelrats :\(line)\r\n".utf8.count, 512)
        }
        let rejoined = lines.map({ String($0.dropFirst("Guser102: ".count)) }).joined(separator: " ")
        XCTAssertEqual(rejoined, translation, "no text is lost at split points")
    }

    func testShortTranslationIsSentAsOneLine() {
        let lines = IRCClient.relayLines(
            "Вибачте, наш перекладач знову дає збої", command: "MSGAS", nick: "arckoor", channel: "#fuelrats",
            source: source, relayedCommand: "PRIVMSG", linePrefix: "Guser102: ")
        XCTAssertEqual(lines, ["Guser102: Вибачте, наш перекладач знову дає збої"])
    }

    func testUnknownSourceAssumesTheLongestPossibleSource() {
        let longestSource = String(repeating: "n", count: 30) + "!" + String(repeating: "u", count: 10) + "@"
            + String(repeating: "h", count: 63)
        let lines = IRCClient.relayLines(
            translation, command: "MSGAS", nick: "arckoor", channel: "#fuelrats", source: nil,
            relayedCommand: "PRIVMSG")
        for line in lines {
            XCTAssertLessThanOrEqual(deliveredLine(line, source: longestSource).utf8.count, 512)
        }
    }

    func testChannelNoticeFitsTheBotSource() {
        let botSource = "MechaSqueak[BOT]!mecha@bot.fuelrats.com"
        let lines = IRCClient.relayLines(
            translation + " " + translation, command: "CNOTICE", nick: "SuperManifolds", channel: "#fuelrats",
            source: botSource, relayedCommand: "NOTICE")
        XCTAssertGreaterThan(lines.count, 1)
        for line in lines {
            XCTAssertLessThanOrEqual(deliveredLine(line, command: "NOTICE", source: botSource).utf8.count, 512)
            XCTAssertLessThanOrEqual("CNOTICE SuperManifolds #fuelrats :\(line)\r\n".utf8.count, 512)
        }
    }
}
