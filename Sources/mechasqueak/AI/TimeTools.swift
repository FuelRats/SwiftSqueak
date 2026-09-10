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

import Foundation

/// Timezone conversion, exposed both as a model-callable tool (`timezone_convert`) and as the engine
/// behind the `!tz` command. The language understanding (parsing "3pm in London" into a time and IANA
/// zones) is the model's job; the actual clock arithmetic here is deterministic and DST-correct via
/// Foundation, so no offsets are ever hallucinated.
enum TimeTools {
    static func all() -> [AITool] {
        [timezoneConvert]
    }

    // MARK: - timezone_convert tool

    static let timezoneConvert = AITool(
        name: "timezone_convert",
        description: """
        Convert a clock time from one timezone to one or more others, DST-correct. Resolve place or \
        zone names to IANA identifiers before calling (e.g. London -> Europe/London, EST -> \
        America/New_York, CET -> Europe/Paris). Pass `time` as 24-hour "HH:mm". Use for "what is 3pm \
        London in New York" style questions.
        """,
        inputSchema: .objectSchema(
            properties: [
                ("time", .stringSchema("The clock time to convert, 24-hour \"HH:mm\"")),
                ("date", .stringSchema("Optional date \"YYYY-MM-DD\"; defaults to today in the source zone")),
                ("from_zone", .stringSchema("IANA identifier of the zone the time is in, e.g. Europe/London")),
                ("to_zones", .arraySchema("IANA identifiers to convert to, e.g. [\"America/New_York\",\"UTC\"]"))
            ],
            required: ["time", "from_zone", "to_zones"])
    ) { input, _ in
        guard let args = parseArguments(input) else {
            return ToolOutput.error("missing 'time', 'from_zone', or 'to_zones'")
        }
        guard let result = convert(
            time: args.time, date: args.date, fromZone: args.fromZone, toZones: args.toZones) else {
            return ToolOutput.error("could not parse the time or resolve the timezone(s)")
        }
        return ToolOutput.json(result)
    }

    /// The arguments the model supplies for a conversion.
    struct ConversionArgs {
        let time: String
        let date: String?
        let fromZone: String
        let toZones: [String]
    }

    /// Extracts the tool arguments from a model tool-call payload (shared by the tool and `!tz`).
    static func parseArguments(_ input: JSONValue) -> ConversionArgs? {
        guard let time = input["time"]?.stringValue, time.isEmpty == false,
              let fromZone = input["from_zone"]?.stringValue, fromZone.isEmpty == false else {
            return nil
        }
        let toZones = (input["to_zones"]?.arrayValue ?? []).compactMap { $0.stringValue }
        guard toZones.isEmpty == false else { return nil }
        let date = input["date"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 }
        return ConversionArgs(time: time, date: date, fromZone: fromZone, toZones: toZones)
    }

    // MARK: - `!tz` command entry

    /// Interprets a plain-English request ("3pm in London", "9am EST to CET tomorrow") by asking the
    /// model to extract the time and IANA zones, then performs the deterministic conversion. Returns a
    /// single formatted line, or nil if there is no provider, the model declines, or nothing parses.
    static func interpret(
        _ text: String, provider: LLMProvider? = nil, reference: Date = Date()
    ) async throws -> String? {
        // Cheap guard: the tool call is forced, so the model would fabricate a conversion for input
        // with no time in it ("banana"). Skip the round-trip entirely unless the text plausibly
        // contains a clock time.
        guard containsPlausibleTime(text) else { return nil }

        let llm: LLMProvider
        if let provider = provider {
            llm = provider
        } else if let token = configuration.anthropicToken, token.isEmpty == false {
            llm = Anthropic(token: token)
        } else {
            return nil
        }

        let request = LLMRequest(
            model: Anthropic.timezoneModel,
            maxTokens: 512,
            system: systemPrompt(reference: reference),
            messages: [.text(.user, text)],
            tools: [timezoneConvert.llmTool],
            toolChoice: .tool("timezone_convert"),
            temperature: 0)

        let response: LLMResponse
        do {
            response = try await llm.complete(request)
        } catch LLMError.refused {
            return nil
        }
        guard let input = response.toolCalls.first(where: { $0.name == "timezone_convert" })?.input,
              let args = parseArguments(input) else {
            return nil
        }
        return convert(
            time: args.time, date: args.date, fromZone: args.fromZone, toZones: args.toZones,
            reference: reference)?.formatted
    }

    static func systemPrompt(reference: Date) -> String {
        let today = DateFormatter.cache("yyyy-MM-dd", zone: "UTC").string(from: reference)
        return """
        Extract the timezone conversion the user is asking for and call timezone_convert. Rules:
        - `time`: the clock time, as 24-hour "HH:mm" (convert any am/pm; noon is 12:00, midnight is 00:00).
        - `date`: only if the user states or implies one (e.g. "tomorrow", "on Friday"); format "YYYY-MM-DD". \
        Today's UTC date is \(today). Omit for "now"/unspecified.
        - `from_zone`: the IANA identifier of the zone the stated time is IN. "3pm in London" means the source is \
        London (Europe/London). "3pm EST" means the source is EST (America/New_York).
        - `to_zones`: IANA identifiers to convert to. Use the targets the user names ("to CET", "in New York"). \
        If the user names only a source and no target, use ["UTC"].
        Resolve every place or abbreviation to a real IANA identifier (London->Europe/London, EST->America/New_York, \
        CET->Europe/Paris, PST->America/Los_Angeles, JST->Asia/Tokyo, AEST->Australia/Sydney).
        """
    }

    // MARK: - Deterministic conversion

    struct ZoneTime: Encodable {
        let zone: String
        let name: String
        let time: String
        let abbreviation: String
        let utcOffset: String
    }

    struct ConversionResult: Encodable {
        let source: ZoneTime
        let weekday: String
        let targets: [ZoneTime]
        let formatted: String
    }

    /// Converts `time` (in `fromZone`, on `date` or today) into each of `toZones`. DST-correct: the
    /// instant is built from calendar components interpreted in the source zone, and every offset is
    /// read from Foundation for that exact instant. Returns nil if the time or source zone won't parse.
    static func convert(
        time: String, date: String?, fromZone: String, toZones: [String], reference: Date = Date()
    ) -> ConversionResult? {
        guard let parsed = parseTime(time), let from = resolveZone(fromZone) else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = from
        var components = DateComponents()
        if let date = date, let ymd = parseDate(date) {
            components.year = ymd.year
            components.month = ymd.month
            components.day = ymd.day
        } else {
            let today = calendar.dateComponents([.year, .month, .day], from: reference)
            components.year = today.year
            components.month = today.month
            components.day = today.day
        }
        components.hour = parsed.hour
        components.minute = parsed.minute
        guard let instant = calendar.date(from: components) else { return nil }

        let resolvedTargets = toZones.compactMap { resolveZone($0) }
        let targets = (resolvedTargets.isEmpty ? [TimeZone(identifier: "UTC")!] : resolvedTargets)
            .map { zoneTime($0, at: instant) }
        let source = zoneTime(from, at: instant)
        let weekday = DateFormatter.cache("EEE", zone: from.identifier).string(from: instant)

        let targetText = targets.map { "\($0.name) \($0.time) (\($0.abbreviation))" }
            .joined(separator: ", ")
        let formatted = "\(source.time) \(weekday) in \(source.name) (\(source.abbreviation)) is \(targetText)"

        return ConversionResult(source: source, weekday: weekday, targets: targets, formatted: formatted)
    }

    static func zoneTime(_ zone: TimeZone, at instant: Date) -> ZoneTime {
        let seconds = zone.secondsFromGMT(for: instant)
        let sign = seconds < 0 ? "-" : "+"
        let magnitude = abs(seconds)
        let offset = String(format: "%@%02d:%02d", sign, magnitude / 3600, (magnitude % 3600) / 60)
        let name = displayName(zone)
        return ZoneTime(
            zone: zone.identifier,
            name: name,
            time: DateFormatter.cache("HH:mm", zone: zone.identifier).string(from: instant),
            abbreviation: name == "UTC" ? "UTC" : (zone.abbreviation(for: instant) ?? zone.identifier),
            utcOffset: offset)
    }

    /// A short, human-friendly zone label: the city portion of an IANA id ("Europe/London" -> "London"),
    /// with the various UTC/GMT spellings collapsed to "UTC" (some platforms normalise the "UTC"
    /// identifier to "GMT", which reads as a confusing offset next to the converted time).
    static func displayName(_ zone: TimeZone) -> String {
        if ["UTC", "GMT", "Etc/UTC", "Etc/GMT"].contains(zone.identifier) { return "UTC" }
        guard let city = zone.identifier.split(separator: "/").last else { return zone.identifier }
        return city.replacingOccurrences(of: "_", with: " ")
    }

    // MARK: - Parsing helpers

    /// Parses "HH:mm", "H:mm", "3pm", "3:30 pm", or "15:00" into 24-hour components.
    static func parseTime(_ raw: String) -> (hour: Int, minute: Int)? {
        var text = raw.lowercased().trimmingCharacters(in: .whitespaces)
        var meridiem: String?
        if text.hasSuffix("pm") { meridiem = "pm"; text.removeLast(2) } else if text.hasSuffix("am") {
            meridiem = "am"; text.removeLast(2)
        }
        text = text.trimmingCharacters(in: .whitespaces)
        let parts = text.split(separator: ":", maxSplits: 1)
        guard let first = parts.first, var hour = Int(first) else { return nil }
        let minute = parts.count > 1 ? (Int(parts[1]) ?? -1) : 0
        if meridiem == "pm", hour < 12 { hour += 12 }
        if meridiem == "am", hour == 12 { hour = 0 }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return (hour, minute)
    }

    /// Whether the text plausibly contains a clock time worth sending to the model: a digit, or a
    /// bare-word time like noon/midnight/midday.
    static func containsPlausibleTime(_ text: String) -> Bool {
        text.range(of: #"[0-9]|(?i)\b(noon|midnight|midday)\b"#, options: .regularExpression) != nil
    }

    static func parseDate(_ raw: String) -> (year: Int, month: Int, day: Int)? {
        let parts = raw.split(separator: "-")
        guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]),
              let day = Int(parts[2]), (1...12).contains(month), (1...31).contains(day) else {
            return nil
        }
        return (year, month, day)
    }

    /// Resolves an IANA identifier, a standard abbreviation, or a fixed-offset abbreviation from the
    /// bundled table. The model is asked for IANA identifiers; the fallbacks tolerate the rest.
    static func resolveZone(_ raw: String) -> TimeZone? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if let zone = TimeZone(identifier: trimmed) { return zone }
        let upper = trimmed.uppercased()
        return TimeZone(abbreviation: upper) ?? timeZoneAbbreviations[upper]
    }
}

extension DateFormatter {
    /// A configured formatter for the given format + IANA zone. Not cached (name kept for call-site
    /// brevity); creating a `DateFormatter` is cheap relative to the surrounding LLM round-trip.
    static func cache(_ format: String, zone: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        formatter.timeZone = TimeZone(identifier: zone) ?? TimeZone(identifier: "UTC")
        return formatter
    }
}
