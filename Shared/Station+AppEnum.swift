import AppIntents

@available(macOS 14.0, *)
extension Station: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Station")
    }

    static var caseDisplayRepresentations: [Station: DisplayRepresentation] {
        // Must be a dictionary literal: the App Intents metadata extractor
        // rejects computed values.
        [
            .nts1: DisplayRepresentation(title: "NTS 1"),
            .nts2: DisplayRepresentation(title: "NTS 2"),
            .poolside: DisplayRepresentation(title: "Poolside"),
            .slowFocus: DisplayRepresentation(title: "Slow Focus"),
            .lowKey: DisplayRepresentation(title: "Low Key"),
            .memoryLane: DisplayRepresentation(title: "Memory Lane"),
            .fourToTheFloor: DisplayRepresentation(title: "4 To The Floor"),
            .islandTime: DisplayRepresentation(title: "Island Time"),
            .theTube: DisplayRepresentation(title: "The Tube"),
            .sheetMusic: DisplayRepresentation(title: "Sheet Music"),
            .feelings: DisplayRepresentation(title: "Feelings"),
            .expansions: DisplayRepresentation(title: "Expansions"),
            .rapHouse: DisplayRepresentation(title: "Rap House"),
            .labyrinth: DisplayRepresentation(title: "Labyrinth"),
            .sweat: DisplayRepresentation(title: "Sweat"),
            .otaku: DisplayRepresentation(title: "Otaku"),
            .thePit: DisplayRepresentation(title: "The Pit"),
            .fieldRecordings: DisplayRepresentation(title: "Field Recordings")
        ]
    }
}
