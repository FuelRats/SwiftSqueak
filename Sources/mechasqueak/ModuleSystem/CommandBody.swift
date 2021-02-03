/*
 Copyright 2021 The Fuel Rats Mischief

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

enum CommandBody {
    case options([Character])
    case argument(String)
    case param(String, String = "", ParameterType = .standard, ParameterNullability = .required)
    
    enum ParameterType {
        case standard
        case continuous
        case multiple
    }
    
    enum ParameterNullability {
        case required
        case optional
    }
}


extension Array where Element == CommandBody {
    var requiredParameters: [CommandBody] {
        return self.filter({
            guard case .param(_, _, _, let nullability) = $0 else {
                return false
            }
            return nullability == .required
        })
    }
    
    var parameters: [CommandBody] {
        return self.filter({
            guard case .param(_, _, _, _) = $0 else {
                return false
            }
            return true
        })
    }
    
    var options: OrderedSet<Character> {
        let optionCase = self.compactMap({ (token: CommandBody) -> [Character]? in
            guard case .options(let options) = token else {
                return nil
            }
            return options
        })
        return OrderedSet(optionCase.first ?? [])
    }
    
    var namedOptions: OrderedSet<String> {
        return OrderedSet(self.compactMap({ (token: CommandBody) -> String? in
            guard case .argument(let option) = token else {
                return nil
            }
            return option
        }))
    }
    
    var paramText: String {
        return parameters.compactMap({ (token: CommandBody) -> String? in
            guard case .param(let description, _, let type, let nullability) = token else {
                return nil
            }
            switch type {
            case .standard:
                if nullability == .required {
                    return "<\(description)>"
                }
                return "[\(description)]"
                
            case .continuous:
                if nullability == .required {
                    return "<\(description)>..."
                }
                return "[\(description)]..."
                
            case .multiple:
                if nullability == .required {
                    return "...<\(description)>"
                }
                return "...[\(description)]"
            }
            
        }).joined(separator: " ")
    }
    
    var example: String {
        return parameters.compactMap({ (token: CommandBody) -> String? in
            guard case .param(_, let example, let type, _) = token else {
                return nil
            }
            
            switch type {
            case .standard:
                if example.components(separatedBy: " ").count > 1 {
                    return "\"\(example)\""
                }
                return example
                
            default:
                return example
            }
        }).joined(separator: " ")
    }
}
