# Name2Chat Forever

A **World of Warcraft: Forever** port of [Name2Chat](https://github.com/gOOvER/Name2Chat) by **gOOvER**.

Name2Chat Forever adds your name in front of your chat messages. It can be enabled for guild (and officer), party, raid, instance and a custom channel.

E.g.:
[Guild] [Yourchar]: Some chat message
becomes
[Guild] [Yourchar]: (Yourname): Some chat message

## Credits & license

- Original addon: **Name2Chat** by gOOvER — https://github.com/gOOvER/Name2Chat (itself a fork of *Incognito*).
- Forever port: akiloan.
- This project is a fork distributed under the **GNU General Public License v3.0**, like the original (see `LICENSE.md`). All original copyrights are retained.
- The original author was contacted before publishing this port: https://github.com/gOOvER/Name2Chat/issues/40
- This is **not** an official release of Name2Chat. Please report Forever-specific issues here, not on the original project.

### Changes compared to the original
See `CHANGELOG.md` (section "Name2Chat Forever"). In short:
- Targets WoW Forever only (`## Interface: 16001`).
- Renamed addon, folder, saved variables (`Name2ChatForeverDB`) and slash commands so it can't collide with the original.
- Chat hook detection is feature-based so the Forever client (modern UI, low interface number) uses the `ChatFrame.OnEditBoxPreSendText` hook.
- Guards against "secret values" (unit / channel names) introduced with the Midnight-era API.

## Usage
You can use the GUI config dialog (Options > AddOns > Name2Chat Forever) or the slash commands `/n2cf` or `/name2chatforever`.

### Slash options
 - config - Open configuration dialog
 - enable - Enable or disable adding your name to chat messages
 - name - The name that should be displayed in your chat messages

### GUI options
 - Enable - Enable adding your name to chat messages.
 - Name - The name that should be displayed in your chat messages
 - Guild - Add name to guild (and officer) chat messages
 - Party - Add name to party chat messages
 - Raid - Add name to raid chat messages
 - Instance - Add name to instance chat messages
 - Channel - Add name to chat messages in a custom channel
 - Hide name if it matches your character name
 - Ignore messages starting with `!`
 - Add name in combat (on by default)
 - Show guild note for players without the addon (on by default)
 - Debug - Enable debugging messages output. You probably don't want to enable this

### Guild & Communities window
Messages typed directly in the Guild & Communities window (default key `J`) also get the name, in the guild and officer channels, with the same rules as the main chat. Other communities are left unchanged.

### Combat
Without the "Add name in combat" option, the name is not added while in combat: modifying the chat text during combat lockdown can taint the protected send call (Blizzard restriction, same as the original addon).

The option **Add name in combat** (on by default, tested on WoW Forever) keeps adding the name in combat as long as the game reports that chat messaging is not locked down (`C_ChatInfo.InChatMessagingLockdown`, e.g. outside boss encounters). If a message ever gets blocked in combat with this option on, disable it.

### Guild note for players without the addon
When a guild (or officer) message you receive does not start with a `(Name): ` prefix, the sender's **public guild note** is shown in front of it, e.g.:

[Guild] [Haldorchar]: Hi all
becomes, in your chat window only
[Guild] [Haldorchar]: (Haldor): Hi all

This is display-only: nothing is sent and other players don't see it. Members without a public note are shown unchanged.

## Installation
Extract the `Name2ChatForever` folder into `World of Warcraft\_forever_\Interface\AddOns\` (or the beta folder `_classic_beta_\Interface\AddOns\`).
