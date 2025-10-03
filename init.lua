-- npc_mod/init.lua

local npc_list = {}
local npc_counter = 0
local player_editing = {}

-- ========== Priv ==========
minetest.register_privilege("npc", {
    description = "Can control and program NPCs",
    give_to_singleplayer = true,
})

-- ========== ID ==========
local function generate_id()
    npc_counter = npc_counter + 1
    return "npc" .. npc_counter
end

-- ========== Safety ==========
local function can_stand_at(pos)
    local node = minetest.get_node_or_nil(pos)
    if not node then return false end
    local def = minetest.registered_nodes[node.name]
    if def and def.walkable then return false end
    return true
end

-- ========== NPC ENTITY ==========
minetest.register_entity("npc_mod:npc", {
    initial_properties = {
        hp_max = 20,
        physical = true,
        collide_with_objects = true,
        collisionbox = {-0.3, -1.0, -0.3, 0.3, 0.8, 0.3},
        visual = "mesh",
        mesh = "character.b3d",
        textures = {"character.png"},
    },

    npc_id = nil,
    program = {},
    program_index = 1,
    spawn_pos = nil,
    loop_count = 0,
    current_loop = 0,
    resetting = false,
    moving = nil,
    anim = "stand",

    set_anim = function(self, anim)
        if self.anim == anim then return end
        self.anim = anim
        if anim == "stand" then
            self.object:set_animation({x=0, y=79}, 30, 0)
        elseif anim == "walk" then
            self.object:set_animation({x=168, y=187}, 30, 0)
        end
    end,

    on_activate = function(self, staticdata)
        if not self.spawn_pos then
            self.spawn_pos = self.object:get_pos()
        end
        if staticdata and staticdata ~= "" then
            local data = minetest.deserialize(staticdata)
            if data then
                self.npc_id = data.npc_id
                self.program = data.program or {}
                self.program_index = data.program_index or 1
                self.loop_count = data.loop_count or 0
                self.current_loop = data.current_loop or 0
                if data.texture then
                    self.object:set_properties({textures = {data.texture}})
                end
            end
        end
        self:set_anim("stand")
    end,

    get_staticdata = function(self)
        return minetest.serialize({
            npc_id = self.npc_id,
            program = self.program,
            program_index = self.program_index,
            texture = self.object:get_properties().textures[1],
            loop_count = self.loop_count,
            current_loop = self.current_loop,
        })
    end,

    on_step = function(self, dtime)
        if not self.program then self.program = {} end

        -- Reset behavior
        if self.resetting and self.spawn_pos then
            local pos = self.object:get_pos()
            local target = self.spawn_pos
            if vector.equals(vector.round(pos), vector.round(target)) then
                self.object:set_pos(target)
                self.object:set_velocity({x=0,y=0,z=0})
                self:set_anim("stand")
                self.resetting = false
                self.program_index = 1
                self.current_loop = 0
                return
            else
                local vel = vector.direction(pos, target)
                self.object:set_velocity(vector.multiply(vel, 2))
                self:set_anim("walk")
                return
            end
        end

        -- Smooth move
        if self.moving then
            self.moving.timer = self.moving.timer + dtime
            if self.moving.timer >= self.moving.duration then
                self.object:set_velocity({x=0,y=0,z=0})
                self.object:set_pos(self.moving.target)
                self:set_anim("stand")
                self.moving = nil
                self.program_index = self.program_index + 1
            end
            return
        end

        -- Execute program
        if #self.program == 0 then return end
        local cmd = self.program[self.program_index]
        if not cmd then return end

        if cmd == "forward" or cmd == "back" or cmd == "left" or cmd == "right" then
            local dir = {x=0,y=0,z=0}
            local pos = vector.round(self.object:get_pos())
            if cmd == "forward" then dir = {x=0,z=1,y=0}
            elseif cmd == "back" then dir = {x=0,z=-1,y=0}
            elseif cmd == "left" then dir = {x=1,z=0,y=0}
            elseif cmd == "right" then dir = {x=-1,z=0,y=0} end
            local target = vector.add(pos, dir)
            if can_stand_at(target) then
                self.object:set_velocity(vector.multiply(dir, 2))
                self.moving = {target=target, timer=0, duration=0.5}
                self:set_anim("walk")
            else
                self.program_index = self.program_index + 1
            end
        elseif cmd:sub(1,3) == "say" then
            minetest.chat_send_all("<NPC "..self.npc_id.."> "..cmd:sub(5))
            self.program_index = self.program_index + 1
        elseif cmd:sub(1,7) == "texture" then
            local tex = cmd:sub(9)
            self.object:set_properties({textures = {tex}})
            self.program_index = self.program_index + 1
        elseif cmd == "reset" then
            self.resetting = true
        elseif cmd:sub(1,4) == "loop" then
            local times = tonumber(cmd:sub(6)) or 1
            if self.current_loop < times then
                self.program_index = 1
                self.current_loop = self.current_loop + 1
            else
                self.program_index = self.program_index + 1
                self.current_loop = 0
            end
        else
            self.program_index = self.program_index + 1
        end
    end,
})

-- ========== FORMS ==========
local function get_formspec(npc)
    local program_str = table.concat(npc.program, "\n")
    return "size[8,9]" ..
           "textarea[0.5,0.5;7.5,6;program;Program;" .. minetest.formspec_escape(program_str) .. "]" ..
           "button_exit[0.5,7;2,1;save;Save]" ..
           "button[3,7;2,1;help;Help]" ..
           "button[5.5,7;2,1;reset_prog;Reset Program]" ..
           "button_exit[3,8;2,1;close;Close]"
end

minetest.register_on_player_receive_fields(function(player, formname, fields)
    if formname ~= "npc_mod:editor" then return end
    local name = player:get_player_name()
    local npc_id = player_editing[name]
    if not npc_id then return end
    local npc = npc_list[npc_id]
    if not npc or not npc:get_luaentity() then return end
    local ent = npc:get_luaentity()

    if fields.save and fields.program then
        ent.program = {}
        for line in fields.program:gmatch("[^\r\n]+") do
            table.insert(ent.program, line)
        end
        ent.program_index = 1
        ent.current_loop = 0
        minetest.chat_send_player(name, "[NPC] Program saved for " .. npc_id)
    elseif fields.help then
        minetest.show_formspec(name, "npc_mod:editor",
            "size[8,9]textarea[0.5,0.5;7.5,7;help;Commands;" ..
            "forward, back, left, right\nsay <msg>\ntexture <skin.png>\nreset\nloop <times>" .. "]" ..
            "button_exit[3,8;2,1;close;Close]")
    elseif fields.reset_prog then
        ent.program = {}
        ent.program_index = 1
        ent.current_loop = 0
        minetest.chat_send_player(name, "[NPC] Program reset for " .. npc_id)
    end
end)

-- ========== CHAT COMMANDS ==========
minetest.register_chatcommand("spawn_npc", {
    privs = {npc=true},
    func = function(name)
        local player = minetest.get_player_by_name(name)
        if not player then return end
        local pos = vector.add(player:get_pos(), {x=2,y=0,z=0})
        local obj = minetest.add_entity(pos, "npc_mod:npc")
        local ent = obj:get_luaentity()
        ent.npc_id = generate_id()
        npc_list[ent.npc_id] = obj
        minetest.chat_send_player(name, "[NPC] Spawned NPC with ID " .. ent.npc_id)
    end,
})

minetest.register_chatcommand("npc_edit", {
    params = "<id>",
    privs = {npc=true},
    func = function(name, param)
        local obj = npc_list[param]
        if not obj or not obj:get_luaentity() then
            return false, "No NPC with ID " .. param
        end
        player_editing[name] = param
        minetest.show_formspec(name, "npc_mod:editor", get_formspec(obj:get_luaentity()))
    end,
})

minetest.register_chatcommand("npc_reset", {
    params = "<id>",
    privs = {npc=true},
    func = function(name, param)
        local obj = npc_list[param]
        if obj and obj:get_luaentity() then
            obj:get_luaentity().resetting = true
            return true, "[NPC] Resetting " .. param
        end
        return false, "No NPC with ID " .. param
    end,
})

minetest.register_chatcommand("npc_loop", {
    params = "<id> <times>",
    privs = {npc=true},
    func = function(name, param)
        local id, times = param:match("^(%S+)%s+(%d+)$")
        if not id or not times then return false, "Usage: /npc_loop <id> <times>" end
        local obj = npc_list[id]
        if obj and obj:get_luaentity() then
            obj:get_luaentity().loop_count = tonumber(times)
            return true, "[NPC] Looping program of " .. id .. " for " .. times .. " times"
        end
        return false, "No NPC with ID " .. id
    end,
})

minetest.register_chatcommand("npc_setskin", {
    params = "<id> <texture.png>",
    privs = {npc=true},
    func = function(name, param)
        local id, tex = param:match("^(%S+)%s+(%S+)$")
        if not id or not tex then return false, "Usage: /npc_setskin <id> <texture.png>" end
        local obj = npc_list[id]
        if obj and obj:get_luaentity() then
            obj:set_properties({textures={tex}})
            return true, "[NPC] Set skin of " .. id .. " to " .. tex
        end
        return false, "No NPC with ID " .. id
    end,
})
