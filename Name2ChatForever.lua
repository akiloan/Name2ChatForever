------------------------
---      Module      ---
------------------------

Name2ChatForever = LibStub("AceAddon-3.0"):NewAddon("Name2ChatForever",
											"AceConsole-3.0",
											"AceEvent-3.0",
											"AceHook-3.0")


----------------------------
--      Localization      --
----------------------------


local L = LibStub("AceLocale-3.0"):GetLocale("Name2ChatForever", true)

-- Options panel, organised in inline sections. Option keys are unchanged
-- (get/set use the leaf key), so existing saved settings keep working.
local function Toggle(key, order, width)
	return {
		order = order,
		type = "toggle",
		width = width or "full",
		name = L[key],
		desc = L[key .. "_desc"],
	}
end

local Options = {
	type = "group",
	get = function(item) return Name2ChatForever.db.profile[item[#item]] end,
	set = function(item, value) Name2ChatForever.db.profile[item[#item]] = value end,
	args = {
		general = {
			order = 1,
			type = "group",
			inline = true,
			name = L["group_general"],
			args = {
				enable = Toggle("enable", 1),
				name = {
					order = 2,
					type = "input",
					width = "double",
					name = L["name"],
					desc = L["name_desc"],
				},
			},
		},
		channels = {
			order = 2,
			type = "group",
			inline = true,
			name = L["group_channels"],
			args = {
				guild = Toggle("guild", 1, "normal"),
				party = Toggle("party", 2, "normal"),
				raid = Toggle("raid", 3, "normal"),
				instance_chat = Toggle("instance_chat", 4, "normal"),
				channel = {
					order = 5,
					type = "input",
					width = "double",
					name = L["channel"],
					desc = L["channel_desc"],
				},
			},
		},
		behaviour = {
			order = 3,
			type = "group",
			inline = true,
			name = L["group_behaviour"],
			args = {
				hideOnMatchingCharName = Toggle("hideOnMatchingCharName", 1),
				ignoreExclamationMark = Toggle("ignoreExclamationMark", 2),
				combat = Toggle("combat", 3),
			},
		},
		received = {
			order = 4,
			type = "group",
			inline = true,
			name = L["group_received"],
			args = {
				guildNote = Toggle("guildNote", 1),
			},
		},
		advanced = {
			order = 5,
			type = "group",
			inline = true,
			name = L["group_advanced"],
			args = {
				debug = Toggle("debug", 1),
			},
		},
	},
}

local Defaults = {
	profile = {
		enable = true,
		guild = true,
		party = false,
		raid = false,
		instance_chat = false,
		debug = false,
		channel = nil,
		hideOnMatchingCharName = false,
		ignoreExclamationMark = true,
		combat = true,
		guildNote = true,
	},
}

local SlashOptions = {
	type = "group",
	handler = Name2ChatForever,
	get = function(item) return Name2ChatForever.db.profile[item[#item]] end,
	set = function(item, value) Name2ChatForever.db.profile[item[#item]] = value end,
	args = {
		enable = {
			type = "toggle",
			name = L["enable"],
			desc = L["enable_desc"],
		},
		name = {
			type = "input",
			name = L["name"],
			desc = L["name_desc"],
		},
		config = {
			type = "execute",
			name = L["config"],
			desc = L["config_desc"],
			func = function()
				-- Use AceConfigDialog to open the options
				LibStub("AceConfigDialog-3.0"):Open("Name2ChatForever Options")
			end,
		},
	},
}

local SlashCmds = {
  "n2cf",
  "Name2ChatForever",
};

local character_name

-- Maximum length of a chat message accepted by the server (in bytes)
local MAX_CHAT_MESSAGE_BYTES = 255

-- WoW Forever / Midnight "secret values": some API results (e.g. unit names)
-- may be opaque values that error when compared or concatenated.
local function IsSecret(value)
	---@diagnostic disable-next-line: undefined-global
	return issecretvalue ~= nil and value ~= nil and issecretvalue(value) or false
end

-- Returns true if chat messaging is locked down (boss encounter etc.),
-- false if it is not, or nil if the client cannot tell us.
local function IsChatMessagingLockedDown()
	if C_ChatInfo and type(C_ChatInfo.InChatMessagingLockdown) == "function" then
		local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
		if ok and not IsSecret(locked) then
			return locked and true or false
		end
	end
	return nil
end

----------------------
---      Init      ---
----------------------

function Name2ChatForever:OnInitialize()
	-- Load our database.
	self.db = LibStub("AceDB-3.0"):New("Name2ChatForeverDB", Defaults, "Default")

	-- Set up our config options.
	local profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)

	local config = LibStub("AceConfig-3.0")
	config:RegisterOptionsTable("Name2ChatForever", SlashOptions, SlashCmds)

	local registry = LibStub("AceConfigRegistry-3.0")
	registry:RegisterOptionsTable("Name2ChatForever Options", Options)
	registry:RegisterOptionsTable("Name2ChatForever Profiles", profiles);

	local dialog = LibStub("AceConfigDialog-3.0");
	self.optionFrames = {
		main = dialog:AddToBlizOptions(	"Name2ChatForever Options", "Name2Chat Forever"),
		profiles = dialog:AddToBlizOptions(	"Name2ChatForever Profiles", "Profiles", "Name2Chat Forever");
	}

	-- Hook the chat send function to prepend the name before messages go out
	self:HookChatSendFunction()

	-- Same for the input box of the Guild & Communities window (J)
	self:SetupCommunitiesHook()

	-- Register event to get character name when available
	self:RegisterEvent("PLAYER_LOGIN", "OnPlayerLogin")
	
	-- Register event for addon chat restrictions (Patch 12.0.0+)
	if self.RegisterEvent then
		pcall(function()
			self:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED", "OnAddonRestrictionChanged")
		end)
	end

	-- Incoming guild messages: show the sender's guild note when they don't use the addon
	self:SetupGuildNoteFilter()

	self:Safe_Print(L["Loaded"])
end

--------------------------------
---      Event Handlers      ---
--------------------------------

function Name2ChatForever:OnPlayerLogin()
	-- Get current character name once player is fully loaded
	character_name = UnitName("player")
	self:UnregisterEvent("PLAYER_LOGIN")
	self:RequestGuildRoster()
end

------------------------------------------
---      Guild note on received chat    ---
------------------------------------------
-- Display-only feature: when a guild member's message does not already start
-- with a "(Name): " prefix (i.e. they don't use this addon), show their public
-- guild note in front of the message in OUR chat frame. Nothing is sent.

local guildNotes = {}          -- [ "Name-Realm" or "Name" ] = public note
local lastRosterRequest = 0
local ROSTER_REQUEST_INTERVAL = 60

function Name2ChatForever:RequestGuildRoster()
	if not IsInGuild() then return end
	lastRosterRequest = GetTime()
	if C_GuildInfo and C_GuildInfo.GuildRoster then
		C_GuildInfo.GuildRoster()
	elseif GuildRoster then
		GuildRoster()
	end
end

function Name2ChatForever:UpdateGuildNotes()
	wipe(guildNotes)
	if not IsInGuild() then return end
	for i = 1, GetNumGuildMembers() do
		local name, _, _, _, _, _, note = GetGuildRosterInfo(i)
		if name and note and not IsSecret(name) and not IsSecret(note) then
			note = strtrim(note)
			if note ~= "" then
				guildNotes[name] = note
				local short = strsplit("-", name)
				if guildNotes[short] == nil then
					guildNotes[short] = note
				end
			end
		end
	end
end

function Name2ChatForever:GetGuildNote(author)
	local note = guildNotes[author]
	if not note then
		note = guildNotes[(strsplit("-", author))]
	end
	return note
end

-- Removes leading spaces and color codes (|cAARRGGBB, |r) so a prefix check
-- isn't fooled by formatting added in front of the text.
local function StripLeadingCodes(s)
	local prev
	repeat
		prev = s
		s = s:gsub("^%s+", "")
		s = s:gsub("^|c%x%x%x%x%x%x%x%x", "")
		s = s:gsub("^|r", "")
	until s == prev
	return s
end

-- Is this chat event from the player? Uses the sender GUID (12th event
-- argument) rather than the name: on WoW Forever names may include a
-- surname / realm in a form that doesn't match UnitName("player").
local function IsFromPlayer(author, guid)
	if guid and not IsSecret(guid) then
		local playerGUID = UnitGUID("player")
		if playerGUID and not IsSecret(playerGUID) then
			return guid == playerGUID
		end
	end
	local charName = Name2ChatForever:GetCharacterName()
	local shortAuthor = strsplit("-", author)
	return charName ~= nil and strlower(shortAuthor) == strlower(charName)
end

local function GuildNoteFilter(frame, event, msg, author, ...)
	local addon = Name2ChatForever
	if not addon.db.profile.guildNote then
		return false
	end
	if type(msg) ~= "string" or type(author) ~= "string" or IsSecret(msg) or IsSecret(author) then
		return false
	end
	-- arg12 = sender GUID; "..." starts at arg3, so it is the 10th vararg
	local guid = select(10, ...)
	addon:Safe_Print(L["debug_guildnote"]:format(event, author, tostring(not IsSecret(guid) and guid or "?"), msg))

	local plainMsg = StripLeadingCodes(msg)
	-- Already prefixed by this addon (or a compatible one): leave it alone
	if plainMsg:find("^%(.-%): ") then
		return false
	end
	-- Addon commands like !keys
	if plainMsg:sub(1, 1) == "!" then
		return false
	end
	-- Our own messages: the send side already handles the prefix
	if IsFromPlayer(author, guid) then
		return false
	end
	local shortAuthor = strsplit("-", author)
	local note = addon:GetGuildNote(author)
	if not note then
		-- Unknown member (new recruit, note just changed...): refresh the roster now and then
		if GetTime() - lastRosterRequest > ROSTER_REQUEST_INTERVAL then
			addon:RequestGuildRoster()
		end
		return false
	end
	-- Same rule as for our own messages: if the note is just the sender's
	-- character name, adding it would only repeat the name shown by the chat.
	if addon.db.profile.hideOnMatchingCharName
		and strlower(strtrim(note)) == strlower(strtrim(shortAuthor)) then
		return false
	end
	-- Last safety net: never add a note that is already in the message
	local notePrefix = "(" .. note .. "): "
	if msg:find(notePrefix, 1, true) then
		return false
	end
	return false, notePrefix .. msg, author, ...
end

function Name2ChatForever:SetupGuildNoteFilter()
	---@diagnostic disable-next-line: undefined-global
	local addFilter = ChatFrame_AddMessageEventFilter
		or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
	if not addFilter then
		self:Safe_Print(L["debug_guildnote_no_filter"])
		return
	end
	addFilter("CHAT_MSG_GUILD", GuildNoteFilter)
	addFilter("CHAT_MSG_OFFICER", GuildNoteFilter)
	self:RegisterEvent("GUILD_ROSTER_UPDATE", "UpdateGuildNotes")
	self:RegisterEvent("PLAYER_GUILD_UPDATE", "RequestGuildRoster")
end

-- Handle addon restriction state changes (Patch 12.0.0+)
function Name2ChatForever:OnAddonRestrictionChanged()
	-- Log if addon chat restrictions are being enforced
	-- This CVar was added in Patch 12.0.0
	if GetCVarBool and C_CVar and C_CVar.GetCVarBool then
		local success, isForced = pcall(C_CVar.GetCVarBool, "addonChatRestrictionsForced")
		if success and isForced then
			self:Print(L["warn_restrictions_enforced"])
		elseif success then
			self:Safe_Print(L["warn_restrictions_lifted"])
		end
	elseif GetCVarBool then
		-- Fallback for older API
		local success, isForced = pcall(GetCVarBool, "addonChatRestrictionsForced")
		if success and isForced then
			self:Print(L["warn_restrictions_enforced"])
		elseif success then
			self:Safe_Print(L["warn_restrictions_lifted"])
		end
	end
end

-- Hook über den offiziellen Blizzard-Event für Addon-Textänderungen vor dem Senden.
-- Quelle: ChatFrameEditBoxMixin:OnPreSendText() in ChatFrameEditBox.lua (12.0.0)
-- Kommentar im Blizzard-Code: "Notification for user addons to perform any final
-- edits to chat text contents before sending."
-- Sequenz in SendText(): ParseText(1) → OnPreSendText() → GetText() → SendChatMessage()
-- D.h.: chatType ist bereits aufgelöst (z.B. /g → "GUILD"), SetText() beeinflusst noch den Send.
function Name2ChatForever:HookChatSendFunction()
	-- ChatFrame.OnEditBoxPreSendText was introduced in Retail Patch 12.0.0 (Midnight/TWW).
	-- Classic clients (e.g. 1.15.x) may have EventRegistry backported but do NOT fire
	-- this event, so upstream gated the EventRegistry path on interface >= 120000.
	--
	-- WoW Forever (interface 16001) runs the modern Mainline UI (based on 12.1.x)
	-- but reports a LOW interface number, so the version gate alone would wrongly
	-- send it to the Classic fallback. Instead we detect the feature itself: the
	-- event is fired by ChatFrameEditBoxMixin:OnPreSendText(), so if that method
	-- exists, the event exists.
	local _, _, _, tocVersion = GetBuildInfo()
	---@diagnostic disable-next-line: undefined-global
	local mixin = ChatFrameEditBoxMixin
	local hasPreSendEvent = type(mixin) == "table" and type(mixin.OnPreSendText) == "function"
	local isForever = tocVersion >= 16000 and tocVersion < 20000
	local useEventRegistry = hasPreSendEvent or isForever or tocVersion >= 120000

	---@diagnostic disable-next-line: undefined-global
	if useEventRegistry and EventRegistry then
		---@diagnostic disable-next-line: undefined-global
		EventRegistry:RegisterCallback("ChatFrame.OnEditBoxPreSendText", function(event, editBox)
			local success, err = pcall(function()
				Name2ChatForever:ModifyChatMessage(editBox)
			end)
			if not success then
				Name2ChatForever:Print(L["hook_error_modify"] .. tostring(err))
			end
		end, Name2ChatForever)
		self:Safe_Print(L["hook_active_eventregistry"])
	else
		-- Fallback for Classic clients and older Retail builds that do not support
		-- ChatFrame.OnEditBoxPreSendText.
		if mixin and mixin.SendText then
			local orig = mixin.SendText
			mixin.SendText = function(editBox, ...)
				local success, err = pcall(function()
					Name2ChatForever:ModifyChatMessage(editBox)
				end)
				if not success then
					Name2ChatForever:Print(L["hook_error_modify"] .. tostring(err))
				end
				orig(editBox, ...)
			end
			self:Safe_Print(L["hook_active_mixin"])
		else
			self:Print(L["hook_error_no_entry"])
		end
	end
end

-- Common checks before adding the name, shared by every input box
-- (main chat edit box and Guild & Communities window).
-- Returns true if the name may be added right now.
function Name2ChatForever:CanAddNameNow()
	-- Early exit if addon is disabled
	if not self.db.profile.enable then
		self:Safe_Print(L["debug_disabled"])
		return false
	end

	-- Don't modify messages during combat lockdown to avoid ADDON_ACTION_FORBIDDEN.
	-- WoW treats editBox:SetText() in this context as tainting the protected
	-- SendChatMessage() call that follows. The message will still be sent as-is.
	--
	-- Optional (experimental): when "combat" is enabled, the name is still added
	-- in combat as long as the client reports that chat messaging is NOT locked
	-- down (C_ChatInfo.InChatMessagingLockdown, Patch 12.0+: true during boss
	-- encounters and similar restricted content). If that API is missing or
	-- fails, we stay on the safe side and skip.
	if InCombatLockdown() then
		if not self.db.profile.combat then
			self:Safe_Print(L["debug_combat_lockdown"])
			return false
		end
		if IsChatMessagingLockedDown() ~= false then
			self:Safe_Print(L["debug_combat_chat_lockdown"])
			return false
		end
	end

	-- Check if we have a valid name configured
	if not self.db.profile.name or self.db.profile.name == "" then
		self:Safe_Print(L["debug_name_empty"])
		return false
	end

	-- Check if we should hide the name when it matches character name.
	-- On WoW Forever unit names can be "secret values" that cannot be compared;
	-- GetCharacterName() re-reads the name in that case (and if PLAYER_LOGIN was missed).
	if self.db.profile.hideOnMatchingCharName then
		self:Safe_Print(L["debug_name_compare"]:format(
			tostring(self.db.profile.name), tostring(self:GetCharacterName())))
		if self:NameMatchesCharacter() then
			self:Safe_Print(L["debug_name_matches_char"])
			return false
		end
	end

	return true
end

-- Returns the message with the name prefix, or nil if it must be sent unchanged.
function Name2ChatForever:BuildPrefixedText(msg)
	-- Ignore empty (or unreadable secret) messages
	if IsSecret(msg) or type(msg) ~= "string" or msg == "" then
		self:Safe_Print(L["debug_msg_empty"])
		return nil
	end
	if self.db.profile.ignoreExclamationMark and self:StartsWithExclamation(msg) then
		-- Don't add name for commands starting with !
		self:Safe_Print(L["debug_skip_exclamation"])
		return nil
	end
	if self:StartsWithPrefix(msg) then
		-- Message recalled from chat history (arrow up) already contains the
		-- prefix: send it as-is instead of producing "(Name): (Name): ..."
		self:Safe_Print(L["debug_skip_already_prefixed"])
		return nil
	end
	local newMsg = self:GetPrefix() .. msg
	if #newMsg > MAX_CHAT_MESSAGE_BYTES then
		-- Chat messages are limited to 255 bytes: adding the prefix would
		-- cut off the end of the message, so send it unchanged instead.
		self:Safe_Print(L["debug_skip_too_long"])
		return nil
	end
	return newMsg
end

------------------------------------------------
---      Guild & Communities window (J)      ---
------------------------------------------------
-- The Guild & Communities window has its own input box that does NOT go
-- through the main chat edit box: Enter calls CommunitiesFrame.Chat:SendMessage(text),
-- which then calls C_Club.SendMessage(clubId, streamId, text).
-- (Blizzard_Communities/CommunitiesChatFrame.lua, forever branch.)
-- Blizzard_Communities is load-on-demand, so we hook it once it is loaded.

function Name2ChatForever:SetupCommunitiesHook()
	---@diagnostic disable-next-line: undefined-global
	local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_Communities")
	if isLoaded then
		self:HookCommunitiesChat()
	else
		self:RegisterEvent("ADDON_LOADED", "OnAddonLoaded")
	end
end

function Name2ChatForever:OnAddonLoaded(event, addonName)
	if addonName == "Blizzard_Communities" then
		self:HookCommunitiesChat()
		self:UnregisterEvent("ADDON_LOADED")
	end
end

function Name2ChatForever:HookCommunitiesChat()
	if self.communitiesHooked then return end
	---@diagnostic disable-next-line: undefined-global
	local chat = CommunitiesFrame and CommunitiesFrame.Chat
	if not chat or type(chat.SendMessage) ~= "function" then
		self:Safe_Print(L["hook_error_communities"])
		return
	end
	self.communitiesHooked = true

	local orig = chat.SendMessage
	chat.SendMessage = function(chatFrame, text, ...)
		local ok, result = pcall(Name2ChatForever.ModifyCommunitiesMessage, Name2ChatForever, chatFrame, text)
		if not ok then
			Name2ChatForever:Print(L["hook_error_modify"] .. tostring(result))
		elseif result then
			text = result
		end
		return orig(chatFrame, text, ...)
	end
	self:Safe_Print(L["hook_active_communities"])
end

-- Returns the prefixed text for a message typed in the Guild & Communities
-- window, or nil to send it unchanged. Only guild and officer streams are
-- concerned (same "Guild" option as /g and /o); other communities are left alone.
function Name2ChatForever:ModifyCommunitiesMessage(chatFrame, text)
	self:Safe_Print(L["debug_hook_fired"])

	local communitiesFrame = chatFrame:GetCommunitiesFrame()
	local clubId = communitiesFrame and communitiesFrame:GetSelectedClubId()
	local streamId = communitiesFrame and communitiesFrame:GetSelectedStreamId()
	if not clubId or not streamId then
		return nil
	end
	local streamInfo = C_Club.GetStreamInfo(clubId, streamId)
	local streamType = streamInfo and streamInfo.streamType
	local isGuildStream = streamType ~= nil
		and (streamType == Enum.ClubStreamType.Guild or streamType == Enum.ClubStreamType.Officer)

	self:Safe_Print(L["debug_chattype"]:format("COMMUNITIES:" .. tostring(streamType), tostring(self.db.profile.name)))

	if not isGuildStream or not self.db.profile.guild then
		self:Safe_Print(L["debug_should_add"]:format("false"))
		return nil
	end
	if not self:CanAddNameNow() then
		return nil
	end

	local newMsg = self:BuildPrefixedText(text)
	if newMsg then
		self:Safe_Print(L["debug_modified"]:format(newMsg))
	end
	return newMsg
end

-- Modify the chat message in the main chat editBox before it's sent
function Name2ChatForever:ModifyChatMessage(editBox)
	self:Safe_Print(L["debug_hook_fired"])

	if not self:CanAddNameNow() then
		return
	end

	-- Get the message text
	local msg = editBox:GetText()

	-- Ignore empty (or unreadable secret) messages
	if IsSecret(msg) or not msg or msg == "" then
		self:Safe_Print(L["debug_msg_empty"])
		return
	end
	
	-- Determine chat type from edit box
	local chatType = editBox:GetAttribute("chatType")
	if not chatType and editBox.chatType then
		chatType = editBox.chatType
	end
	if not chatType then
		chatType = "SAY"
	end
	
	self:Safe_Print(L["debug_chattype"]:format(tostring(chatType), tostring(self.db.profile.name)))

	local shouldAddName = false
	
	-- Check based on chat type
	if chatType == "GUILD" and self.db.profile.guild then
		shouldAddName = true
	elseif chatType == "OFFICER" and self.db.profile.guild then
		shouldAddName = true
	elseif chatType == "PARTY" and self.db.profile.party then
		shouldAddName = true
	elseif chatType == "RAID" and self.db.profile.raid then
		shouldAddName = true
	elseif chatType == "INSTANCE_CHAT" and (self.db.profile.instance_chat or self.db.profile.raid) then
		-- In instances (raids, LFR, battlegrounds) WoW routes raid chat as INSTANCE_CHAT
		shouldAddName = true
	elseif (self.db.profile.channel ~= nil) and (self.db.profile.channel ~= "") and chatType == "CHANNEL" then
		-- Special handling for custom channels
		local channelNum = editBox:GetAttribute("channelTarget")
		if not channelNum and editBox.channelTarget then
			channelNum = editBox.channelTarget
		end
		if channelNum then
			local id, chname = GetChannelName(channelNum)
			if chname and not IsSecret(chname) and strupper(self.db.profile.channel) == strupper(chname) then
				shouldAddName = true
			end
		end
	end

	self:Safe_Print(L["debug_should_add"]:format(tostring(shouldAddName)))

	-- Add name unless it's a special command and ignore option is enabled
	if shouldAddName then
		local newMsg = self:BuildPrefixedText(msg)
		if newMsg then
			-- Modify the text in the editbox BEFORE it is sent
			editBox:SetText(newMsg)
			self:Safe_Print(L["debug_modified"]:format(newMsg))
		end
	else
		self:Safe_Print(L["debug_chattype_not_active"]:format(
			tostring(chatType),
			tostring(self.db.profile.guild),
			tostring(self.db.profile.party),
			tostring(self.db.profile.raid),
			tostring(self.db.profile.instance_chat)
		))
	end
end

---------------------------
---      Functions      ---
---------------------------

function Name2ChatForever:Safe_Print(msg)
	if self.db.profile.debug then
		self:Print(msg)
	end
end

-- Local helper function to check if message starts with exclamation mark
function Name2ChatForever:StartsWithExclamation(msg)
	if not msg or msg == "" then
		return false
	end
	return string.sub(msg, 1, 1) == "!"
end

-- Prefix added in front of messages, e.g. "(Ely): "
function Name2ChatForever:GetPrefix()
	return "(" .. self.db.profile.name .. "): "
end

-- True if the message already starts with our prefix (plain comparison, no patterns)
function Name2ChatForever:StartsWithPrefix(msg)
	local prefix = self:GetPrefix()
	return string.sub(msg, 1, #prefix) == prefix
end

-- Utility function to safely get character name.
-- Returns nil if the name is not available (or is a secret value right now).
-- If the cached name is missing or was stored as a secret value, it is read
-- again so a bad value captured at login doesn't stick for the whole session.
function Name2ChatForever:GetCharacterName()
	if not character_name or IsSecret(character_name) then
		local name = UnitName("player")
		if name and not IsSecret(name) then
			character_name = name
		end
	end
	if not character_name or IsSecret(character_name) then
		return nil
	end
	return character_name
end

-- True if the configured name matches the current character's name
-- (case-insensitive, surrounding spaces ignored).
function Name2ChatForever:NameMatchesCharacter()
	local charName = self:GetCharacterName()
	local name = self.db.profile.name
	if not charName or not name then
		return false
	end
	return strlower(strtrim(name)) == strlower(strtrim(charName))
end
