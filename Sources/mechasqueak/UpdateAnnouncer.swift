/*
 Copyright 2024 The Fuel Rats Mischief

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

/// Decides whether MechaSqueak should post an "update complete" announcement on start-up.
///
/// The build version is baked into `version.txt` in the image. The last version we actually
/// announced is remembered on the persistent data volume, so an ordinary restart — or a
/// reconnect that re-joins the reporting channel within a single run — does not re-post the
/// announcement. Only a genuine version change (i.e. the bot was restarted onto a new build)
/// produces one.
enum UpdateAnnouncer {
    /// Persisted on the `/data` volume (the same volume as the token caches) so it survives
    /// container restarts and re-creations.
    static let stateFile = "/data/announced-version.txt"

    /// The current build version, but only when it differs from the version last announced —
    /// in which case it is recorded as announced. Returns `nil` when there is nothing new to
    /// announce: no/unknown version, or the same version as last time (an ordinary restart).
    static func versionToAnnounce(
        sourcePath: String, stateFile: String = UpdateAnnouncer.stateFile
    ) -> String? {
        guard let current = readTrimmed("\(sourcePath)/version.txt"),
            current.isEmpty == false, current != "unknown"
        else {
            return nil
        }

        guard current != readTrimmed(stateFile) else {
            return nil
        }

        try? current.write(toFile: stateFile, atomically: true, encoding: .utf8)
        return current
    }

    private static func readTrimmed(_ path: String) -> String? {
        try? String(contentsOfFile: path, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
