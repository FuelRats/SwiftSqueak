import HTMLKit

struct CommandParameterComponent: View {
    let token: CommandBody
    
    var body: Content {
        if case .param(let description, _, let type, let nullability) = token {
            switch type {
            case .standard:
                Span { description }.class(parameterClasses(description: description, type: type, nullability: nullability))
                
            case .continuous:
                Span { "\(description)..." }.class(parameterClasses(description: description, type: type, nullability: nullability))
                
            case .multiple:
                Span { "\(description)1" }.class(parameterClasses(description: description, type: type, nullability: nullability))
                Span { "\(description)2" }.class(parameterClasses(description: description, type: type, nullability: nullability))
            }
        }
    }
}
    

func parameterClasses(description: String, type: CommandBody.ParameterType, nullability: CommandBody.ParameterNullability) -> String {
    var classes = ["command-parameter"]
    if nullability == .optional {
        classes.append("command-parameter-optional")
    }
    classes.append("command-parameter-" + type.rawValue)
    return classes.joined(separator: " ")
}
