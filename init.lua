-- npc_mod/init.lua

local npc_storage = minetest.get_mod_storage()
local npc_list = {}
local npc_counter = 0
local player_editing = {}

-- =========================
-- ID generator
-- =========================
local function generate_id()
    npc_counter = npc_counter + 1
    return "npc" .. npc_counter
end

-- =========================
-- Default commands reference
-- =========================
local command_help = {
    forward = "Move forward for <duration> seconds. Usage: forward <speed> <duration>",
    turn_left = "Turn left (90°). Usage: turn_left",
    turn_right = "Turn right (90°). Usage: turn_right",
    stop = "Stop moving. Usage: stop <duration>",
    texture = "Change texture. Usage: texture <filename.png>"
}

-- =========================
-- NPC entity
-- =========================
minetest.register_entity("npc_mod:npc", {
    initial_properties = {
        hp_max = 20,
        physical = true,
        collide_with_objects = true,
        collisionbox = {-0.3, -1.0, -0.3, 0.3, 0.8, 0.3},
        visual = "mesh",
        mesh = "character.b3d",
        textures = {"Steve_(classic_texture)_JE6.png"},
    },

    npc_id = nil,
    program = {},
    program_index = 1,
    timer = 0,

    on_activate = function(self, staticdata)
        if staticdata and staticdata ~= "" then
            local data = minetest.deserialize(staticdata)
            if data then
                self.npc_id = data.npc_id
                self.program = data.program or {}
                self.program_index = data.program_index or 1
                if data.texture then
                    self.object:set_properties({textures = {data.texture}})
                end
                -- Re-add to npc_list after restart
                npc_list[self.npc_id] = self
            end
        end
    end,

    get_staticdata = function(self)
        return minetest.serialize({
            npc_id = self.npc_id,
            program = self.program,
            program_index = self.program_index,
            texture = self.object:get_properties().textures[1],
        })
    end,

    on_step = function(self, dtime)
        if not self.program or #self.program == 0 then return end

        self.timer = self.timer + dtime
        local step = self.program[self.program_index]
        if not step then return end

        if self.timer >= (step.duration or 2) then
            if step.action == "forward" then
                local dir = self.object:get_yaw()
                local vel = vector.new(math.cos(dir), 0, math.sin(dir))
                self.object:set_velocity(vector.multiply(vel, step.speed or 2))
            elseif step.action == "turn_left" then
                self.object:set_yaw(self.object:get_yaw() + math.rad(90))
            elseif step.action == "turn_right" then
                self.object:set_yaw(self.object:get_yaw() - math.rad(90))
            elseif step.action == "stop" then
                self.object:set_velocity({x=0, y=0, z=0})
            elseif step.action == "texture" and step.name then
                self.object:set_properties({textures = {step.name}})
            end

            self.timer = 0
            self.program_index = self.program_index + 1
            if self.program_index > #self.program then
                self.program_index = 1
            end
        end
    end,
})

-- =========================
-- Spawn command
-- =========================
minetest.register_chatcommand("spawn_npc", {
    description = "Spawn a programmable NPC",
    func = function(name)
        local player = minetest.get_player_by_name(name)
        if not player then return end
        local pos = vector.add(player:get_pos(), {x=0, y=1, z=0})
        local obj = minetest.add_entity(pos, "npc_mod:npc")
        local lua = obj:get_luaentity()
        local id = generate_id()
        lua.npc_id = id
        npc_list[id] = lua
        minetest.chat_send_player(name, "Spawned NPC with ID: " .. id)
    end,
})

-- =========================
-- Helper: safe string split
-- =========================
local function split_words(line)
    local t = {}
    for word in line:gmatch("%S+") do
        table.insert(t, word)
    end
    return t
end

-- =========================
-- Editor formspec
-- =========================
local function get_editor_formspec(id, program_text, texture)
    return table.concat({
        "formspec_version[4]",
        "size[10,10]",
        "label[0.5,0.2;Editing NPC: ", id, "]",
        "textarea[0.5,0.7;9,4;program;Program (line by line):;", minetest.formspec_escape(program_text or ""), "]",
        "field[0.5,5.2;5,1;texture;Texture filename:;", minetest.formspec_escape(texture or "Steve_(classic_texture)_JE6.png"), "]",
        "button[0.5,6;3,1;save;Save Program]",
        "button[4,6;3,1;help;Show Help]",
        "label[0.5,7;Move NPC 1 block:]",
        "button[0.5,7.5;2,1;move_forward;Forward]",
        "button[2.5,7.5;2,1;move_back;Back]",
        "button[5,7.5;2,1;move_left;Left]",
        "button[7.5,7.5;2,1;move_right;Right]",
    })
end

-- Help formspec
local function get_help_formspec()
    local text = ""
    for cmd, desc in pairs(command_help) do
        text = text .. cmd .. " - " .. desc .. "\n"
    end
    return "formspec_version[4]size[10,8]textarea[0.5,0.5;9,7;help;Available Commands:;"..
        minetest.formspec_escape(text)..
        "]button[3,7.5;3,1;back;Back]"
end

-- =========================
-- Edit command
-- =========================
minetest.register_chatcommand("npc_edit", {
    params = "<id>",
    description = "Edit NPC program",
    func = function(name, param)
        if npc_list[param] then
            local npc = npc_list[param]
            player_editing[name] = param
            local program_text = ""
            for _, step in ipairs(npc.program) do
                if step.action == "forward" then
                    program_text = program_text .. "forward " .. (step.speed or 2) .. " " .. (step.duration or 2) .. "\n"
                elseif step.action == "stop" then
                    program_text = program_text .. "stop " .. (step.duration or 2) .. "\n"
                elseif step.action == "turn_left" or step.action == "turn_right" then
                    program_text = program_text .. step.action .. "\n"
                elseif step.action == "texture" then
                    program_text = program_text .. "texture " .. (step.name or "") .. "\n"
                end
            end
            minetest.show_formspec(name, "npc_mod:editor_"..param,
                get_editor_formspec(param, program_text, npc.object:get_properties().textures[1]))
        else
            return false, "No NPC with that ID."
        end
    end,
})

-- =========================
-- Handle formspec buttons
-- =========================
minetest.register_on_player_receive_fields(function(player, formname, fields)
    local pname = player:get_player_name()
    local id = formname:match("npc_mod:editor_(.+)")
    if id and npc_list[id] then
        local npc = npc_list[id]

        if fields.save and fields.program then
            local program = {}
            for line in fields.program:gmatch("[^\r\n]+") do
                local args = split_words(line)
                local cmd = args[1]
                if cmd == "forward" then
                    table.insert(program, {action="forward", speed=tonumber(args[2]) or 2, duration=tonumber(args[3]) or 2})
                elseif cmd == "turn_left" then
                    table.insert(program, {action="turn_left", duration=1})
                elseif cmd == "turn_right" then
                    table.insert(program, {action="turn_right", duration=1})
                elseif cmd == "stop" then
                    table.insert(program, {action="stop", duration=tonumber(args[2]) or 2})
                elseif cmd == "texture" then
                    table.insert(program, {action="texture", name=args[2]})
                end
            end
            npc.program = program
            if fields.texture and fields.texture ~= "" then
                npc.object:set_properties({textures = {fields.texture}})
            end
            minetest.chat_send_player(pname, "Program saved for NPC "..id)

        elseif fields.help then
            minetest.show_formspec(pname, "npc_mod:help", get_help_formspec())

        elseif fields.back then
            local edit_id = player_editing[pname]
            if edit_id and npc_list[edit_id] then
                local npc = npc_list[edit_id]
                local program_text = ""
                for _, step in ipairs(npc.program) do
                    if step.action == "forward" then
                        program_text = program_text .. "forward " .. (step.speed or 2) .. " " .. (step.duration or 2) .. "\n"
                    elseif step.action == "stop" then
                        program_text = program_text .. "stop " .. (step.duration or 2) .. "\n"
                    elseif step.action == "turn_left" or step.action == "turn_right" then
                        program_text = program_text .. step.action .. "\n"
                    elseif step.action == "texture" then
                        program_text = program_text .. "texture " .. (step.name or "") .. "\n"
                    end
                end
                minetest.show_formspec(pname, "npc_mod:editor_"..edit_id,
                    get_editor_formspec(edit_id, program_text, npc.object:get_properties().textures[1]))
            end

        elseif fields.move_forward or fields.move_back or fields.move_left or fields.move_right then
            local dir = npc.object:get_yaw()
            local offset = {x=0, y=0, z=0}

            if fields.move_forward then
                offset = {x=math.cos(dir), y=0, z=math.sin(dir)}
            elseif fields.move_back then
                offset = {x=-math.cos(dir), y=0, z=-math.sin(dir)}
            elseif fields.move_left then
                offset = {x=math.cos(dir + math.pi/2), y=0, z=math.sin(dir + math.pi/2)}
            elseif fields.move_right then
                offset = {x=math.cos(dir - math.pi/2), y=0, z=math.sin(dir - math.pi/2)}
            end

            local pos = npc.object:get_pos()
            npc.object:set_pos(vector.add(pos, offset))
        end
    end
end)
