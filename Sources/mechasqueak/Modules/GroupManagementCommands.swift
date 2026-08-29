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

import AsyncHTTPClient
import Foundation
import IRCKit
import NIO

/// Commands for managing a permission group's *definition* — its IRC channel access,
/// granted OAuth scopes, vhost/priority/prefix, and group creation/deletion. Every write
/// acts on behalf of the calling user (`x-representing`), so the API authorises it against
/// their real `groups.write`; the `permission:` gate here is only a fast pre-check. Group
/// members are resynced automatically by the API (groupsync fan-out) after a channel change.
class GroupManagementCommands: IRCBotModule {
    var name: String = "GroupManagementCommands"

    required init(_ moduleManager: IRCBotModuleManager) {
        moduleManager.register(module: self)
    }

    // MARK: - Helpers

    /// Resolve a group by name (case-insensitive). Replies `nogroup` (unknown) or `error`
    /// (lookup failed) and returns nil on failure.
    static func resolveGroup(named name: String, command: IRCBotCommand) async -> Group? {
        do {
            let groupSearch = try await Group.getList()
            guard
                let group = groupSearch.body.data?.primary.values.first(where: {
                    $0.attributes.name.value.lowercased() == name.lowercased()
                })
            else {
                command.message.reply(
                    key: "groupchannel.nogroup", fromCommand: command, map: ["param": name])
                return nil
            }
            return group
        } catch {
            command.message.error(key: "groupchannel.error", fromCommand: command)
            return nil
        }
    }

    /// A write must be attributable to a real user (the API authorises the caller via
    /// `x-representing`, which is only sent for an identified caller). Blocks otherwise.
    static func requireIdentifiedCaller(_ command: IRCBotCommand) -> Bool {
        if command.message.user.associatedAPIData?.user == nil {
            command.message.error(key: "groupchannel.notloggedin", fromCommand: command)
            return false
        }
        return true
    }

    /// Refresh the bot's cached group list after a successful edit.
    static func refreshGroups() async {
        if let groups = try? await Group.getList().body.data?.primary.values {
            mecha.groups = groups
        }
    }

    static func channelSummary(_ group: Group) -> String {
        let channels = group.attributes.channels.value
        if channels.isEmpty {
            return "(none)"
        }
        return channels.sorted(by: { $0.key < $1.key })
            .map({ "#\($0.key): \($0.value)" }).joined(separator: ", ")
    }

    static func permissionSummary(_ group: Group) -> String {
        let permissions = group.attributes.permissions.value
            .map({ $0.rawValue }).filter({ $0.isEmpty == false }).sorted()
        return permissions.isEmpty ? "(none)" : permissions.joined(separator: ", ")
    }

    /// Map an API write failure to a localised reply: 403 → not allowed (caller lacks
    /// `groups.write`), 422 → the supplied `badValueKey`, otherwise a generic error.
    static func replyWriteError(
        _ error: Error, command: IRCBotCommand, badValueKey: String, value: String = ""
    ) {
        if let response = error as? HTTPClient.Response {
            switch Int(response.status.code) {
                case 403:
                    command.message.error(key: "groupchannel.notallowed", fromCommand: command)
                    return
                case 422:
                    // The offending value under every placeholder the badValue keys use,
                    // so whichever key is passed interpolates correctly.
                    command.message.error(
                        key: badValueKey, fromCommand: command,
                        map: ["value": value, "name": value, "flags": value, "scope": value])
                    return
                default:
                    break
            }
        }
        command.message.error(key: "groupchannel.error", fromCommand: command)
    }

    // MARK: - View

    @BotCommand(
        ["groupinfo", "chans"],
        [.param("permission group", "overseer")],
        category: .management,
        description: "Show a permission group's channels, granted scopes, vhost and priority.",
        tags: ["group", "channel", "permission"],
        permission: .GroupRead,
        helpExtra: {
            return ManagementCommands.generateGroupList()
        }
    )
    var didReceiveGroupInfoCommand = { command in
        guard let group = await GroupManagementCommands.resolveGroup(
            named: command.parameters[0], command: command)
        else {
            return
        }

        command.message.reply(
            key: "groupchannel.info", fromCommand: command,
            map: [
                "group": group.ircRepresentation,
                "channels": GroupManagementCommands.channelSummary(group),
                "permissions": GroupManagementCommands.permissionSummary(group),
                "vhost": group.attributes.vhost.value ?? "(none)",
                "priority": String(group.attributes.priority.value)
            ])
    }

    // MARK: - Channels

    @BotCommand(
        ["addchan"],
        [
            .param("permission group", "overseer"), .param("channel", "#ops"),
            .param("flags", "OV")
        ],
        category: .management,
        description: "Grant a channel's access flags to a permission group.",
        tags: ["group", "channel", "flags"],
        permission: .GroupWrite,
        helpExtra: {
            return ManagementCommands.generateGroupList()
        }
    )
    var didReceiveAddChanCommand = { command in
        guard GroupManagementCommands.requireIdentifiedCaller(command) else {
            return
        }

        let flags = command.parameters[2]
        guard flags.isEmpty == false, flags.allSatisfy({ validGroupFlagLetters.contains($0) }) else {
            command.message.error(
                key: "groupchannel.badflags", fromCommand: command, map: ["flags": flags])
            return
        }

        guard let group = await GroupManagementCommands.resolveGroup(
            named: command.parameters[0], command: command)
        else {
            return
        }

        let channel = command.parameters[1]
        do {
            let updated = try await group.setChannel(channel, flags: flags, command: command)
            await GroupManagementCommands.refreshGroups()
            command.message.reply(
                key: "groupchannel.setsuccess", fromCommand: command,
                map: [
                    "channel": "#\(Group.bareChannel(channel))",
                    "flags": flags,
                    "group": updated.ircRepresentation,
                    "channels": GroupManagementCommands.channelSummary(updated)
                ])
        } catch {
            GroupManagementCommands.replyWriteError(
                error, command: command, badValueKey: "groupchannel.badflags", value: flags)
        }
    }

    @BotCommand(
        ["delchan"],
        [.param("permission group", "overseer"), .param("channel", "#ops")],
        category: .management,
        description: "Remove a channel's access from a permission group.",
        tags: ["group", "channel", "delete"],
        permission: .GroupWrite,
        helpExtra: {
            return ManagementCommands.generateGroupList()
        }
    )
    var didReceiveDelChanCommand = { command in
        guard GroupManagementCommands.requireIdentifiedCaller(command) else {
            return
        }

        guard let group = await GroupManagementCommands.resolveGroup(
            named: command.parameters[0], command: command)
        else {
            return
        }

        let channel = command.parameters[1]
        do {
            let updated = try await group.removeChannel(channel, command: command)
            await GroupManagementCommands.refreshGroups()
            command.message.reply(
                key: "groupchannel.delsuccess", fromCommand: command,
                map: [
                    "channel": "#\(Group.bareChannel(channel))",
                    "group": updated.ircRepresentation,
                    "channels": GroupManagementCommands.channelSummary(updated)
                ])
        } catch {
            GroupManagementCommands.replyWriteError(
                error, command: command, badValueKey: "groupchannel.badchannel", value: channel)
        }
    }

    // MARK: - Permissions (guarded by re-post confirmation)

    @BotCommand(
        ["addperm"],
        [.options(["f"]), .param("permission group", "overseer"), .param("scope", "rescues.read")],
        category: .management,
        description: "Grant an OAuth permission scope to a permission group. Re-post within 30s (or -f) to confirm.",
        tags: ["group", "permission", "scope"],
        permission: .GroupWrite,
        helpExtra: {
            return ManagementCommands.generateGroupList()
        }
    )
    var didReceiveAddPermCommand = { command in
        guard GroupManagementCommands.requireIdentifiedCaller(command) else {
            return
        }

        guard let group = await GroupManagementCommands.resolveGroup(
            named: command.parameters[0], command: command)
        else {
            return
        }

        let scope = command.parameters[1]
        guard command.forceOverride else {
            command.message.reply(
                key: "groupchannel.confirmperm", fromCommand: command,
                map: [
                    "action": "grant", "scope": scope, "group": group.ircRepresentation
                ])
            return
        }

        do {
            let updated = try await group.setPermission(scope, command: command)
            await GroupManagementCommands.refreshGroups()
            command.message.reply(
                key: "groupchannel.permadded", fromCommand: command,
                map: [
                    "scope": scope,
                    "group": updated.ircRepresentation,
                    "permissions": GroupManagementCommands.permissionSummary(updated)
                ])
        } catch {
            GroupManagementCommands.replyWriteError(
                error, command: command, badValueKey: "groupchannel.badscope", value: scope)
        }
    }

    @BotCommand(
        ["delperm"],
        [.options(["f"]), .param("permission group", "overseer"), .param("scope", "rescues.read")],
        category: .management,
        description: "Revoke an OAuth permission scope from a permission group. Re-post within 30s (or -f) to confirm.",
        tags: ["group", "permission", "scope", "delete"],
        permission: .GroupWrite,
        helpExtra: {
            return ManagementCommands.generateGroupList()
        }
    )
    var didReceiveDelPermCommand = { command in
        guard GroupManagementCommands.requireIdentifiedCaller(command) else {
            return
        }

        guard let group = await GroupManagementCommands.resolveGroup(
            named: command.parameters[0], command: command)
        else {
            return
        }

        let scope = command.parameters[1]
        guard command.forceOverride else {
            command.message.reply(
                key: "groupchannel.confirmperm", fromCommand: command,
                map: [
                    "action": "revoke", "scope": scope, "group": group.ircRepresentation
                ])
            return
        }

        do {
            let updated = try await group.removePermission(scope, command: command)
            await GroupManagementCommands.refreshGroups()
            command.message.reply(
                key: "groupchannel.permremoved", fromCommand: command,
                map: [
                    "scope": scope,
                    "group": updated.ircRepresentation,
                    "permissions": GroupManagementCommands.permissionSummary(updated)
                ])
        } catch {
            GroupManagementCommands.replyWriteError(
                error, command: command, badValueKey: "groupchannel.badscope", value: scope)
        }
    }

    // MARK: - Scalar attributes

    @BotCommand(
        ["setvhost"],
        [.param("permission group", "overseer"), .param("vhost (or - to clear)", "overseer.fuelrats.com")],
        category: .management,
        description: "Set (or clear with -) a permission group's IRC vhost suffix.",
        tags: ["group", "vhost"],
        permission: .GroupWrite,
        helpExtra: {
            return ManagementCommands.generateGroupList()
        }
    )
    var didReceiveSetVhostCommand = { command in
        guard GroupManagementCommands.requireIdentifiedCaller(command) else {
            return
        }

        guard let group = await GroupManagementCommands.resolveGroup(
            named: command.parameters[0], command: command)
        else {
            return
        }

        let raw = command.parameters[1]
        let vhost: String? = raw == "-" ? nil : raw
        do {
            let updated = try await group.setVhost(vhost, command: command)
            await GroupManagementCommands.refreshGroups()
            command.message.reply(
                key: "groupchannel.attrset", fromCommand: command,
                map: [
                    "group": updated.ircRepresentation,
                    "attr": "vhost",
                    "value": updated.attributes.vhost.value ?? "(none)"
                ])
        } catch {
            GroupManagementCommands.replyWriteError(
                error, command: command, badValueKey: "groupchannel.badvalue", value: raw)
        }
    }

    @BotCommand(
        ["setprio"],
        [.param("permission group", "overseer"), .param("priority", "60")],
        category: .management,
        description: "Set a permission group's priority (higher wins for vhost/permission ordering).",
        tags: ["group", "priority"],
        permission: .GroupWrite,
        helpExtra: {
            return ManagementCommands.generateGroupList()
        }
    )
    var didReceiveSetPrioCommand = { command in
        guard GroupManagementCommands.requireIdentifiedCaller(command) else {
            return
        }

        guard let priority = Int(command.parameters[1]) else {
            command.message.error(
                key: "groupchannel.badvalue", fromCommand: command, map: ["value": command.parameters[1]])
            return
        }

        guard let group = await GroupManagementCommands.resolveGroup(
            named: command.parameters[0], command: command)
        else {
            return
        }

        do {
            let updated = try await group.setPriority(priority, command: command)
            await GroupManagementCommands.refreshGroups()
            command.message.reply(
                key: "groupchannel.attrset", fromCommand: command,
                map: [
                    "group": updated.ircRepresentation,
                    "attr": "priority",
                    "value": String(updated.attributes.priority.value)
                ])
        } catch {
            GroupManagementCommands.replyWriteError(
                error, command: command, badValueKey: "groupchannel.badvalue", value: command.parameters[1])
        }
    }

    @BotCommand(
        ["setprefix"],
        [.param("permission group", "overseer"), .param("on/off", "on")],
        category: .management,
        description: "Whether the group's vhost uses the rat-name prefix (on = prefixed, off = bare vhost).",
        tags: ["group", "vhost", "prefix"],
        permission: .GroupWrite,
        helpExtra: {
            return ManagementCommands.generateGroupList()
        }
    )
    var didReceiveSetPrefixCommand = { command in
        guard GroupManagementCommands.requireIdentifiedCaller(command) else {
            return
        }

        let arg = command.parameters[1].lowercased()
        let prefixOn: Bool
        switch arg {
            case "on", "yes", "true":
                prefixOn = true
            case "off", "no", "false":
                prefixOn = false
            default:
                command.message.error(
                    key: "groupchannel.badvalue", fromCommand: command,
                    map: ["value": command.parameters[1]])
                return
        }

        guard let group = await GroupManagementCommands.resolveGroup(
            named: command.parameters[0], command: command)
        else {
            return
        }

        do {
            // "prefix on" means the rat-name prefix is used → withoutPrefix is false.
            let updated = try await group.setWithoutPrefix(prefixOn == false, command: command)
            await GroupManagementCommands.refreshGroups()
            command.message.reply(
                key: "groupchannel.attrset", fromCommand: command,
                map: [
                    "group": updated.ircRepresentation,
                    "attr": "name prefix",
                    "value": updated.attributes.withoutPrefix.value ? "off" : "on"
                ])
        } catch {
            GroupManagementCommands.replyWriteError(
                error, command: command, badValueKey: "groupchannel.badvalue", value: command.parameters[1])
        }
    }

    // MARK: - Create / delete

    @BotCommand(
        ["newgroup"],
        [.param("name", "overseer")],
        category: .management,
        description: "Create a new (empty) permission group.",
        tags: ["group", "create"],
        permission: .GroupWrite
    )
    var didReceiveNewGroupCommand = { command in
        guard GroupManagementCommands.requireIdentifiedCaller(command) else {
            return
        }

        let name = command.parameters[0]
        guard name.isEmpty == false, name.allSatisfy({ $0.isLetter || $0.isNumber }) else {
            command.message.error(
                key: "groupchannel.badname", fromCommand: command, map: ["name": name])
            return
        }

        do {
            let created = try await Group.create(name: name, command: command)
            await GroupManagementCommands.refreshGroups()
            command.message.reply(
                key: "groupchannel.groupcreated", fromCommand: command,
                map: ["group": created.ircRepresentation])
        } catch let error as HTTPClient.Response where error.status == .conflict {
            command.message.error(
                key: "groupchannel.groupexists", fromCommand: command, map: ["name": name])
        } catch {
            GroupManagementCommands.replyWriteError(
                error, command: command, badValueKey: "groupchannel.badname", value: name)
        }
    }

    @BotCommand(
        ["rmgroup"],
        [.options(["f"]), .param("name", "overseer")],
        category: .management,
        description: "Delete a permission group (members lose its access). Re-post within 30s (or -f) to confirm.",
        tags: ["group", "delete"],
        permission: .GroupWrite,
        helpExtra: {
            return ManagementCommands.generateGroupList()
        }
    )
    var didReceiveRmGroupCommand = { command in
        guard GroupManagementCommands.requireIdentifiedCaller(command) else {
            return
        }

        guard let group = await GroupManagementCommands.resolveGroup(
            named: command.parameters[0], command: command)
        else {
            return
        }

        guard command.forceOverride else {
            command.message.reply(
                key: "groupchannel.confirmdelete", fromCommand: command,
                map: ["group": group.ircRepresentation])
            return
        }

        do {
            try await group.delete(command: command)
            await GroupManagementCommands.refreshGroups()
            command.message.reply(
                key: "groupchannel.groupdeleted", fromCommand: command,
                map: ["group": group.attributes.name.value])
        } catch {
            GroupManagementCommands.replyWriteError(
                error, command: command, badValueKey: "groupchannel.error")
        }
    }
}
