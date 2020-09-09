/*
 Copyright 2020 The Fuel Rats Mischief

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
import Regex

class Autocorrect {
    private static let proceduralSystemExpression =
        "([\\w\\s'.()/-]+) ([A-Za-z])([A-Za-z])-([A-Za-z]) ([A-Za-z])(?:(\\d+)-)?(\\d+)".r!
    private static let numberSubstitutions: [Character: Character] = [
        "1": "L",
        "4": "A",
        "5": "S",
        "8": "B",
        "0": "O"
    ]
    private static let letterSubstitutions: [Character: Character] = [
        "L": "1",
        "S": "5",
        "B": "8",
        "O": "0",
        "4": "A"
    ]

    static func check (system: String, search: SystemsAPISearchDocument) -> String? {
        let system = system.uppercased()

        // If the system name is less than 3 words, it is probably a special named system not a procedural one
        if system.split(separator: " ").count < 3 {
            /* Non-procedural systems are likely to exist in the Systems API, so we will suggest the one that is
             closest in edit distance */
            if search.data[0].distance ?? Int.max < 2 {
                return search.data[0].name
            }
        }

        guard system.contains(" SECTOR ") else {
            // Not a special system, and not a sector system, nothing we can do with this input
            return nil
        }

        let components = system.components(separatedBy: " SECTOR ")
        guard components.count == 2 else {
            // Only the sector itself was entered nothing after it, there is nothing we can do here, exit
            return nil
        }
 
        var sector = components[0]
        var fragments = components[1].components(separatedBy: " ")
        if sectors.contains(sector) == false {
            // If the sector is not in the known sector list attempt to replace it with a close match from the list
            let searchString = "\(sector)"
            let sectorResults = sectors.map({
                ($0, searchString.levenshtein($0))
                }).sorted(by: {
                    $0.1 < $1.1
            })
            if sectorResults[0].1 < 3 {
                sector = sectorResults[0].0
            }
        }

        let sectorCorrectedSystem = "\(sector) SECTOR \(fragments.joined(separator: " "))"
        if proceduralSystemExpression.findFirst(in: system) != nil && system != sectorCorrectedSystem {
            // If the last part of the system name looks correct, return it with corrected sector name
            return sectorCorrectedSystem
        }

        /* This section of procedural system names do never contain digits, if there are one, replace them with letters
         that are commonly mistaken for these numbers. */
        if fragments[0].rangeOfCharacter(from: .decimalDigits) != nil {
            fragments[0] = Autocorrect.performNumberSubstitution(value: fragments[0])
        }
        var secondFragment = fragments[1]
        if secondFragment.first!.isNumber {
            /*  The first character of the second fragment of a procedural system name is never a letter.
             If it is a letter in the input, replace it with numbers that are commonly mistaken for numbers.  */
            secondFragment = secondFragment.replacingCharacters(
                in: ...secondFragment.startIndex,
                with: Autocorrect.performNumberSubstitution(value: String(secondFragment.first!))
            )
        }

        let correctedSystem = "\(sector) SECTOR \(fragments.joined(separator: " "))"

        // Check that our corrected name now passes the check for valid procedural system
        if proceduralSystemExpression.findFirst(in: correctedSystem) != nil && system != correctedSystem {
            return correctedSystem
        }

        // We were not able to correct this
        return nil
    }

    static func performNumberSubstitution (value: String) -> String {
        return String(value.map({ (char: Character) -> Character in
            if let substitution = numberSubstitutions[char] {
                return substitution
            }
            return char
        }))
    }

    static func performLetterrSubstitution (value: String) -> String {
        return String(value.map({ (char: Character) -> Character in
            if let substitution = letterSubstitutions[char] {
                return substitution
            }
            return char
        }))
    }
}

let sectors = [
    "TRIANGULI",
    "CRUCIS",
    "TASCHETER",
    "HYDRAE",
    "COL 285",
    "SCORPII",
    "SHUI WEI",
    "SHUDUN",
    "YIN",
    "JASTREB",
    "PEGASI",
    "CEPHEI",
    "BEI DOU",
    "PUPPIS",
    "SHARRU",
    "ALRAI",
    "LYNCIS",
    "TUCANAE",
    "PISCIUM",
    "HERCULIS",
    "ANTLIAE",
    "ARIETIS",
    "CAPRICORNI",
    "CETI",
    "CORE SYS",
    "BLANCO 1",
    "NGC 129",
    "NGC 225",
    "NGC 188",
    "IC 1590",
    "NGC 457",
    "M103",
    "NGC 654",
    "NGC 659",
    "NGC 663",
    "COL 463",
    "NGC 752",
    "NGC 744",
    "STOCK 2",
    "H PERSEI",
    "CHI PERSEI",
    "IC 1805",
    "NGC 957",
    "TR 2",
    "M34",
    "NGC 1027",
    "IC 1848",
    "NGC 1245",
    "NGC 1342",
    "IC 348",
    "MEL 22",
    "NGC 1444",
    "NGC 1502",
    "NGC 1528",
    "NGC 1545",
    "HYADES",
    "NGC 1647",
    "NGC 1662",
    "NGC 1664",
    "NGC 1746",
    "NGC 1778",
    "NGC 1817",
    "NGC 1857",
    "NGC 1893",
    "M38",
    "COL 69",
    "NGC 1981",
    "TRAPEZIUM",
    "COL 70",
    "M36",
    "M37",
    "NGC 2129",
    "NGC 2169",
    "M35",
    "NGC 2175",
    "COL 89",
    "NGC 2232",
    "COL 97",
    "NGC 2244",
    "NGC 2251",
    "COL 107",
    "NGC 2264",
    "M41",
    "NGC 2286",
    "NGC 2281",
    "NGC 2301",
    "COL 121",
    "M50",
    "NGC 2324",
    "NGC 2335",
    "NGC 2345",
    "NGC 2343",
    "NGC 2354",
    "NGC 2353",
    "COL 132",
    "COL 135",
    "NGC 2360",
    "NGC 2362",
    "NGC 2367",
    "COL 140",
    "NGC 2374",
    "NGC 2384",
    "NGC 2395",
    "NGC 2414",
    "M47",
    "NGC 2423",
    "MEL 71",
    "NGC 2439",
    "M46",
    "M93",
    "NGC 2451A",
    "NGC 2477",
    "NGC 2467",
    "NGC 2482",
    "NGC 2483",
    "NGC 2489",
    "NGC 2516",
    "NGC 2506",
    "COL 173",
    "NGC 2527",
    "NGC 2533",
    "NGC 2539",
    "NGC 2547",
    "NGC 2546",
    "M48",
    "NGC 2567",
    "NGC 2571",
    "NGC 2579",
    "PISMIS 4",
    "NGC 2627",
    "NGC 2645",
    "NGC 2632",
    "IC 2391",
    "IC 2395",
    "NGC 2669",
    "NGC 2670",
    "TR 10",
    "M67",
    "IC 2488",
    "NGC 2910",
    "NGC 2925",
    "NGC 3114",
    "NGC 3228",
    "NGC 3247",
    "IC 2581",
    "NGC 3293",
    "NGC 3324",
    "NGC 3330",
    "COL 228",
    "IC 2602",
    "TR 14",
    "TR 16",
    "NGC 3519",
    "FE 1",
    "NGC 3532",
    "NGC 3572",
    "COL 240",
    "NGC 3590",
    "NGC 3680",
    "NGC 3766",
    "IC 2944",
    "STOCK 14",
    "NGC 4103",
    "NGC 4349",
    "MEL 111",
    "NGC 4463",
    "NGC 5281",
    "NGC 4609",
    "JEWEL BOX",
    "NGC 5138",
    "NGC 5316",
    "NGC 5460",
    "NGC 5606",
    "NGC 5617",
    "NGC 5662",
    "NGC 5822",
    "NGC 5823",
    "NGC 6025",
    "NGC 6067",
    "NGC 6087",
    "NGC 6124",
    "NGC 6134",
    "NGC 6152",
    "NGC 6169",
    "NGC 6167",
    "NGC 6178",
    "NGC 6193",
    "NGC 6200",
    "NGC 6208",
    "NGC 6231",
    "NGC 6242",
    "TR 24",
    "NGC 6250",
    "NGC 6259",
    "NGC 6281",
    "NGC 6322",
    "IC 4651",
    "NGC 6383",
    "M6",
    "NGC 6416",
    "IC 4665",
    "NGC 6425",
    "M7",
    "M23",
    "M20",
    "NGC 6520",
    "M21",
    "NGC 6530",
    "NGC 6546",
    "NGC 6604",
    "M16",
    "M18",
    "M17",
    "NGC 6633",
    "M25",
    "NGC 6664",
    "IC 4756",
    "M26",
    "NGC 6705",
    "NGC 6709",
    "COL 394",
    "STEPH 1",
    "NGC 6716",
    "NGC 6755",
    "STOCK 1",
    "NGC 6811",
    "NGC 6819",
    "NGC 6823",
    "NGC 6830",
    "NGC 6834",
    "NGC 6866",
    "NGC 6871",
    "NGC 6885",
    "IC 4996",
    "MEL 227",
    "NGC 6910",
    "M29",
    "NGC 6939",
    "NGC 6940",
    "NGC 7039",
    "NGC 7063",
    "NGC 7082",
    "M39",
    "IC 1396",
    "IC 5146",
    "NGC 7160",
    "NGC 7209",
    "NGC 7235",
    "NGC 7243",
    "NGC 7380",
    "NGC 7510",
    "M52",
    "NGC 7686",
    "NGC 7789",
    "NGC 7790",
    "IC 410",
    "NGC 3603",
    "NGC 7822",
    "NGC 281",
    "LBN 623",
    "HEART",
    "SOUL",
    "PLEIADES",
    "PERSEUS DARK REGION",
    "NGC 1333",
    "CALIFORNIA",
    "NGC 1491",
    "HIND",
    "TRIFID OF THE NORTH",
    "FLAMING STAR",
    "NGC 1931",
    "CRAB",
    "RUNNING MAN",
    "ORION",
    "COL 359",
    "SPIROGRAPH",
    "NGC 1999",
    "FLAME",
    "HORSEHEAD",
    "WITCH HEAD",
    "MONKEY HEAD",
    "JELLYFISH",
    "ROSETTE",
    "HUBBLE'S VARIABLE",
    "CONE",
    "SEAGULL",
    "THOR'S HELMET",
    "SKULL AND CROSSBONES NEB.",
    "PENCIL",
    "NGC 3199",
    "ETA CARINA",
    "STATUE OF LIBERTY",
    "NGC 5367",
    "NGC 6188",
    "CAT'S PAW",
    "NGC 6357",
    "TRIFID",
    "LAGOON",
    "EAGLE",
    "OMEGA",
    "B133",
    "IC 1287",
    "R CRA",
    "NGC 6820",
    "CRESCENT",
    "SADR REGION",
    "VEIL WEST",
    "NORTH AMERICA",
    "B352",
    "PELICAN",
    "VEIL EAST",
    "IRIS",
    "ELEPHANT'S TRUNK",
    "COCOON",
    "CAVE",
    "NGC 7538",
    "BUBBLE",
    "ARIES DARK REGION",
    "TAURUS DARK REGION",
    "ORION DARK REGION",
    "MESSIER 78",
    "BARNARD'S LOOP",
    "PUPPIS DARK REGION",
    "PUPPIS DARK REGION B",
    "VELA DARK REGION",
    "MUSCA DARK REGION",
    "COALSACK",
    "CHAMAELEON",
    "COALSACK DARK REGION",
    "LUPUS DARK REGION B",
    "LUPUS DARK REGION",
    "SCORPIUS DARK REGION",
    "IC 4604",
    "PIPE (STEM)",
    "OPHIUCHUS DARK REGION B",
    "SCUTUM DARK REGION",
    "B92",
    "SNAKE",
    "PIPE (BOWL)",
    "OPHIUCHUS DARK REGION C",
    "RHO OPHIUCHI",
    "OPHIUCHUS DARK REGION",
    "CORONA AUSTR. DARK REGION",
    "AQUILA DARK REGION",
    "VULPECULA DARK REGION",
    "CEPHEUS DARK REGION",
    "CEPHEUS DARK REGION B",
    "HORSEHEAD DARK REGION",
    "PARROT'S HEAD",
    "STRUVE'S LOST",
    "BOW-TIE",
    "SKULL",
    "LITTLE DUMBBELL",
    "IC 289",
    "NGC 1360",
    "NGC 1501",
    "NGC 1514",
    "NGC 1535",
    "NGC 2022",
    "IC 2149",
    "IC 2165",
    "BUTTERFLY",
    "NGC 2371/2",
    "ESKIMO",
    "NGC 2438",
    "NGC 2440",
    "NGC 2452",
    "IC 2448",
    "NGC 2792",
    "NGC 2818",
    "NGC 2867",
    "NGC 2899",
    "IC 2501",
    "EIGHT BURST",
    "IC 2553",
    "NGC 3195",
    "NGC 3211",
    "GHOST OF JUPITER",
    "IC 2621",
    "OWL",
    "NGC 3699",
    "BLUE PLANETARY",
    "NGC 4361",
    "LEMON SLICE",
    "IC 4191",
    "SPIRAL PLANETARY",
    "NGC 5307",
    "NGC 5315",
    "RETINA",
    "NGC 5873",
    "NGC 5882",
    "NGC 5979",
    "FINE RING",
    "NGC 6058",
    "WHITE EYED PEA",
    "NGC 6153",
    "NGC 6210",
    "IC 4634",
    "BUG",
    "BOX",
    "NGC 6326",
    "NGC 6337",
    "LITTLE GHOST",
    "IC 4663",
    "NGC 6445",
    "CAT'S EYE",
    "IC 4673",
    "RED SPIDER",
    "NGC 6565",
    "NGC 6563",
    "NGC 6572",
    "NGC 6567",
    "IC 4699",
    "NGC 6629",
    "NGC 6644",
    "IC 4776",
    "RING",
    "PHANTOM STREAK",
    "NGC 6751",
    "IC 4846",
    "IC 1297",
    "NGC 6781",
    "NGC 6790",
    "NGC 6803",
    "NGC 6804",
    "LITTLE GEM",
    "BLINKING",
    "NGC 6842",
    "DUMBBELL",
    "NGC 6852",
    "NGC 6884",
    "NGC 6879",
    "NGC 6886",
    "NGC 6891",
    "IC 4997",
    "BLUE FLASH",
    "FETUS",
    "SATURN",
    "NGC 7026",
    "NGC 7027",
    "NGC 7048",
    "IC 5117",
    "IC 5148",
    "IC 5217",
    "HELIX",
    "NGC 7354",
    "BLUE SNOWBALL",
    "G2 DUST CLOUD",
    "REGOR"
].map({ $0.uppercased() })
