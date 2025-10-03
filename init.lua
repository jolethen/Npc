-- npc_mod/init.lua

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
-- Safe position check
-- =========================
local function can_stand_at(pos)
    local node = minetest.get_node_or_nil(pos)
    if not node then return false end
    local def = minetest.registered_nodes[node.name]
    if def and def.walkable then return false end
    return true
end

-- =========================
-- Command reference
-- =========================
local command_help = {
    forward      = "Move forward continuously. Usage: forward <speed> <duration>",
    turn_left    = "Turn left (90°). Usage: turn_left",
    turn_right   = "Turn right (90°). Usage: turn_right",
    stop         = "Stop moving. Usage: stop <duration>",
    texture      = "Change texture. Usage: texture <filename.png>",
    chat         = "Send a chat message. Usage: chat \"message\"",
    move_forward = "Step forward one block",
    move_back    = "Step back one block",
    move_left    = "Step left one block",
    move_right   = "Step right one block",
    move_up      = "Step up one block",
    move_down    = "Step down one block",
    reset        = "Return to spawn position. Usage: reset",
    loop         = "Repeat program. Usage: loop <times>",
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
        textures = {"character.png"},
    },

    npc_id = nil,
    program = {},
    program_index = 1,
    timer = 0,
    moving = nil,
    anim = "stand",
    spawn_pos = nil,
    loop_count = 0,
    current_loop = 0,
    resetting = false,

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
            current_loop = self.current_loop
        })
    end,

    on_step = function(self, dtime)
        if not self.program then self.program = {} end

        -- Reset
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

        -- Smooth movement
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

        if #self.program == 0 then return end
        self.timer = self.timer + dtime
        local step = self.program[self.program_index]
        if not step then return end

        if self.timer >= (step.duration or 1) then
            if step.action == "forward" then
                local dir = self.object:get_yaw()
                local vel = vector.new(math.cos(dir), 0, math.sin(dir))
                self.object:set_velocity(vector.multiply(vel, step.speed or 2))
                self:set_anim("walk")

            elseif step.action == "turn_left" then
                self.object:set_yaw(self.object:get_yaw() + math.rad(90))

            elseif step.action == "turn_right" then
                self.object:set_yaw(self.object:get_yaw() - math.rad(90))

            elseif step.action == "stop" then
                self.object:set_velocity({x=0,y=0,z=0})
                self:set_anim("stand")

            elseif step.action == "texture" then
                self.object:set_properties({textures = {step.name}})

            elseif step.action == "chat" then
                minetest.chat_send_all("[NPC-"..(self.npc_id or "?").."] " .. step.msg)

            elseif step.action == "reset" then
                self.resetting = true
                self.timer = 0
                return

            elseif step.action == "loop" then
                self.loop_count = tonumber(step.times) or 0
                self.current_loop = self.current_loop + 1
                if self.loop_count == 0 or self.current_loop < self.loop_count then
                    self.program_index = 1
                end

            -- Step movement
            elseif step.action:find("move_") then
                local dir = self.object:get_yaw()
                local pos = vector.round(self.object:get_pos())
                local target
                if step.action == "move_forward" then
                    target = vector.add(pos, {x=math.cos(dir), y=0, z=math.sin(dir)})
                elseif step.action == "move_back" then
                    target = vector.add(pos, {x=-math.cos(dir), y=0, z=-math.sin(dir)})
                elseif step.action == "move_left" then
                    target = vector.add(pos, {x=math.cos(dir + math.pi/2), y=0, z=math.sin(dir + math.pi/2)})
                elseif step.action == "move_right" then
                    target = vector.add(pos, {x=math.cos(dir - math.pi/2), y=0, z=math.sin(dir - math.pi/2)})
                elseif step.action == "move_up" then
                    target = vector.add(pos, {x=0, y=1, z=0})
                elseif step.action == "move_down" then
                    target = vector.add(pos, {x=0, y=-1, z=0})
                end

                if target and can_stand_at(target) then
                    local vel = vector.direction(pos, target)
                    self.moving = { target=target, duration=0.5, timer=0 }
                    self.object:set_velocity(vector.multiply(vel, 2))
                    self:set_anim("walk")
                else
                    self.program_index = self.program_index + 1
                end
            end

            self.timer = 0
            if not self.moving and not self.resetting then
                self.program_index = self.program_index + 1
            end
            if self.program_index > #self.program then
                if self.loop_count == 0 or self.current_loop < self.loop_count then
                    self.program_index = 1
                else
                    self.program_index = #self.program
                end
            end
        end
    end,
})

-- =========================
-- Chat commands
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
        lua.spawn_pos = pos
        npc_list[id] = lua
        minetest.chat_send_player(name, "Spawned NPC with ID: " .. id)
    end,
})

minetest.register_chatcommand("npc_reset", {
    params = "<id>",
    description = "Reset an NPC to its spawn position",
    func = function(name, param)
        local npc = npc_list[param]
        if npc then
            npc.resetting = true
            minetest.chat_send_player(name, "NPC " .. param .. " reset.")
        else
            return false, "No NPC with that ID."
        end
    end,
})

minetest.register_chatcommand("npc_loop", {
    params = "<id> <times>",
    description = "Loop an NPC's program",
    func = function(name, param)
        local id, times = param:match("^(%S+)%s+(%d+)$")
        if not id then return false, "Usage: /npc_loop <id> <times>" end
        local npc = npc_list[id]
        if npc then
            npc.loop_count = tonumber(times)
            npc.current_loop = 0
            npc.program_index = 1
            minetest.chat_send_player(name, "NPC " .. id .. " will loop " .. times .. " times.")
        else
            return false, "No NPC with that ID."
        end
    end,
})

minetest.register_chatcommand("npc_setskin", {
    params = "<id> <skin.png>",
    description = "Set NPC skin",
    func = function(name, param)
        local id, skin = param:match("^(%S+)%s+(%S+)$")
        if not id or not skin then
            return false, "Usage: /npc_setskin <id> <skin.png>"
        end
        local npc = npc_list[id]
        if npc then
            npc.object:set_properties({textures = {skin}})
            minetest.chat_send_player(name, "NPC " .. id .. " skin set to " .. skin)
        else
            return false, "No NPC with that ID."
        end
    end,
})

minetest.register_chatcommand("npc_help", {
    description = "Show NPC programming commands",
    func = function(name)
        local text = "__ NPC Commands __\n"
        for cmd, desc in pairs(command_help) do
            text = text .. cmd .. " - " .. desc .. "\n"
        end
        minetest.chat_send_player(name, text)
    end,
})
