import HTMLKit

struct CommandPermissionGroupView: View {
    let group: Group
    
    var body: Content {
        Span {
            group.groupDescription
        }.class("command-permission-group command-permission-group-\(group.name)")
    }
}
