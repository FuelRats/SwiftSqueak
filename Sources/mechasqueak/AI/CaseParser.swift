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

/// Turns a dispatcher's plain-English note about a stranded client into structured rescue fields, via
/// a forced `emit_case` tool call (same pattern as `Translate`/`TimeTools`). Returns nil when the AI is
/// unavailable (no token), times out, refuses, or flags the note as not-a-rescue — callers fall back to
/// the deterministic `SignalScanner`. The model only proposes a system *name*; it is validated/corrected
/// downstream by `Rescue.validateSystem()`, never here.
enum CaseParser {
    /// Tight deadline: add-case is latency-sensitive (a dispatcher is watching for the case to appear),
    /// so fall back to the regex parser quickly rather than stalling a code red.
    static let deadline: Double = 4

    static let emitCaseTool = LLMTool(
        name: "emit_case",
        description: "Return the structured rescue details extracted from the dispatcher's note.",
        inputSchema: .objectSchema(
            properties: [
                ("cmdr_name", .stringSchema(
                    "Only an explicitly-labelled in-game commander name (after \"cmdr\"/\"commander\"/\"client is\"/"
                    + "\"name is\"); otherwise \"\". A bare proper noun is the system, never this.")),
                ("platform", .stringSchema(
                    "The platform, normalised to \"pc\", \"xbox\", or \"ps\". Recognise abbreviations: "
                    + "xbox/xb/xb1/xbone → \"xbox\"; ps/ps4/ps5/playstation/psn → \"ps\"; pc → \"pc\". "
                    + "\"\" if not stated. A platform token is never part of the system name.")),
                ("system", .stringSchema(
                    "The full star system name exactly as written (may be several words); \"\" if not stated. "
                    + "Do not correct or invent it.")),
                ("code_red", .boolSchema(
                    "True when the client is out of oxygen / on emergency life support: \"cr\", \"code red\", "
                    + "an oxygen status of \"not ok\" (with or without \"o2\"), or ANY stated remaining-oxygen "
                    + "time / countdown (\"o2 6 mins\", \":24 minutes of o2\", \"3:00 o2\"). \"o2 ok\" is NOT.")),
                ("expansion", .stringSchema(
                    "PC game version: \"legacy\", \"horizons\", or \"odyssey\"; \"\" if not stated")),
                ("language", .stringSchema("ISO 639 code if a non-English client language is stated; otherwise \"\"")),
                ("error", .stringSchema("Short reason if the note is not rescue information; otherwise \"\""))
            ],
            required: ["cmdr_name", "platform", "system", "code_red", "expansion", "language", "error"]))

    static let systemPrompt = """
    You extract structured rescue details from a Fuel Rats dispatcher's short note about a client who is \
    stranded in Elite Dangerous, and return them by calling emit_case. The dispatcher has ALREADY \
    identified the client by their IRC nick; the note contains only the case ATTRIBUTES. Fill only the \
    fields the note states and leave the rest as empty strings. Never invent or correct a system name; \
    copy it exactly as written. code_red is true when the client is out of oxygen or on emergency life \
    support: the shorthand "cr"/"code red", an oxygen status of "not ok" (with or without the word "o2"), \
    or ANY stated remaining-oxygen time or life-support countdown (e.g. "o2 6 mins", ":24 minutes of o2", \
    "3:00 o2") — a client reporting how much air is left is on emergency oxygen. In contrast "o2 ok" or \
    "oxygen ok" is NOT a code red. Notes are terse shorthand with tokens in any \
    order, e.g. "xbox MATET cr", "Koa Entraha PC", "pc cr NLTT 48288". Recognise the platform token — pc; \
    xbox/xb/xb1/xbone; ps/ps4/ps5/playstation/psn — normalise it to "pc", "xbox" or "ps", and NEVER treat \
    it as part of the system name (in "Colonia XB" the system is "Colonia", not "Colonia XB"). Recognise \
    the expansion word and "cr", and ignore signal noise tokens like "RATSIGNAL", "PC_SIGNAL", "PS_SIGNAL". \
    EVERYTHING ELSE — any leftover word or multi-word phrase, whether a single real-looking word ("Khun", \
    "Lauma", "Antani"), a two-word name ("Koa Entraha", "Exo Rialo"), or an alphanumeric designation \
    ("NLTT 48288", "Col 285 Sector AB-O A6-2") — is the SYSTEM name; put the whole remainder in system. \
    Leave cmdr_name as "" UNLESS the note explicitly introduces an in-game commander with a label such as \
    "cmdr", "commander", "client is", or "name is" (e.g. "cmdr Space Dawg"). A lone proper noun is NEVER \
    the cmdr. Set error only when the note is clearly not about a rescue.
    """

    struct CaseFields: Sendable {
        let cmdrName: String?
        let platform: GamePlatform?
        let system: String?
        let codeRed: Bool
        let expansion: GameMode?
        let language: Locale?
    }

    /// Naming the already-known client nick lets the model positively exclude any nick from the note, so
    /// it stops mistaking a leading system word (e.g. the region prefix after a "RATSIGNAL" paste) for a
    /// commander and dropping it. The nick itself is never in the note; this only tells the model there is
    /// no other person's name to find.
    static func clientContext(nick: String) -> String {
        """
         The client's IRC nick is "\(nick)". This nick is already recorded and is NOT repeated in the \
        note; the note names no other person. Do not treat ANY word as a nick or discard it as a name — \
        the only name you may extract is an explicitly-labelled commander (see cmdr_name). In particular, \
        the word immediately after a noise token like "RATSIGNAL" is the start of the SYSTEM name, not a nick.
        """
    }

    /// Parses `text` into `CaseFields`, or nil to signal "fall back to SignalScanner" (unavailable,
    /// timed out, refused, or flagged not-a-rescue). For this trusted dispatcher-only command the
    /// not-a-rescue case intentionally falls back rather than refusing — the dispatcher still wants a case.
    /// `clientNick`, when supplied, is the already-identified client (the command's first token); it is
    /// added to the prompt as context so the model never re-derives a nick from the note.
    static func parse(
        _ text: String, clientNick: String? = nil, provider: LLMProvider? = nil
    ) async -> CaseFields? {
        let llm: LLMProvider
        if let provider = provider {
            llm = provider
        } else if let token = configuration.anthropicToken, token.isEmpty == false {
            llm = Anthropic(token: token)
        } else {
            return nil
        }

        let system = clientNick.map { systemPrompt + clientContext(nick: $0) } ?? systemPrompt
        let request = LLMRequest(
            model: Anthropic.caseModel,
            maxTokens: 512,
            system: system,
            messages: [.text(.user, text)],
            tools: [emitCaseTool],
            toolChoice: .tool("emit_case"),
            temperature: 0)

        let response: LLMResponse
        do {
            response = try await AIService.withTimeout(seconds: deadline) {
                try await llm.complete(request)
            }
        } catch {
            aiLogger.info("Case parse unavailable, falling back to SignalScanner: \(error)")
            return nil
        }

        guard let input = response.toolCalls.first(where: { $0.name == "emit_case" })?.input else {
            return nil
        }
        let error = input["error"]?.stringValue ?? ""
        guard error.isEmpty else {
            aiLogger.info("Case parse: model flagged non-rescue note '\(error)', falling back")
            return nil
        }

        func field(_ key: String) -> String? {
            guard let value = input[key]?.stringValue, value.isEmpty == false else { return nil }
            return value
        }

        return CaseFields(
            cmdrName: field("cmdr_name"),
            platform: field("platform").flatMap { GamePlatform.parsedFromText(text: $0) },
            system: field("system"),
            codeRed: input["code_red"]?.boolValue ?? false,
            expansion: field("expansion").flatMap { GameMode.parsedFromText(text: $0) },
            language: field("language").flatMap { validatedLocale(from: $0) })
    }

    /// The model is asked for an ISO 639 language code, but its output is untrusted — a stray word like
    /// "russian" would otherwise be persisted verbatim as a bogus `clientLanguage`. Accept only a
    /// recognised language code (optionally region-qualified, e.g. "pt-BR"); drop anything else to nil.
    static func validatedLocale(from code: String) -> Locale? {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        // Split keeping empty subtags so a malformed identifier is rejected rather than silently
        // reinterpreted: "-BR" would otherwise become language "BR"->Breton, and "pt-" a bogus
        // Locale("pt-"). Require the first subtag to be the language and every subtag non-empty.
        let subtags = trimmed.split(separator: "-", omittingEmptySubsequences: false)
        guard let languageSubtag = subtags.first, subtags.allSatisfy({ $0.isEmpty == false }) else {
            return nil
        }
        let language = languageSubtag.lowercased()
        // "und" (undetermined) and "zxx" (no linguistic content) are valid ISO codes but not a real
        // client language — treat them as unspecified.
        guard language != "und", language != "zxx",
            Locale.LanguageCode.isoLanguageCodes.contains(Locale.LanguageCode(language))
        else {
            return nil
        }
        return Locale(identifier: trimmed)
    }
}
