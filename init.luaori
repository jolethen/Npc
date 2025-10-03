-- npc_mod/init.lua

local npc_storage = minetest.get_mod_storage()
local npc_list = {}
local player_editing = {}
local npc_counter = 0

-- =========================
-- Simple ID generator
-- =========================
local function generate_id()
    npc_counter = npc_counter + 1
    return "npc" .. npc_counter
end

-- =========================
-- Commands reference
-- =========================
local command_help = {
    forward      = "Move forward continuously. Usage: forward <speed> <duration>",
    turn_left    = "Turn left (90°). Usage: turn_left",
    turn_right   = "Turn right (90°). Usage: turn_right",
    stop         = "Stop moving. Usage: stop <duration>",
    texture      = "Change texture. Usage: texture <filename.png>",
    chat         = "Send a chat message. Usage: chat \"message\"",
    move_forward = "Step forward one block slowly",
    move_back    = "Step back one block slowly",
    move_left    = "Step left one block slowly",
    move_right   = "Step right one block slowly",
    move_up      = "Step up one block slowly",
    move_down    = "Step down one block slowly",
    reset        = "Reset NPC to its spawn position",
    loop         = "Loop program n times. Usage: loop <times>",
}

-- =========================
-- Helper: safe position check
-- =========================
local function can_stand_at(pos)
    local node = minetest.get_node_or_nil(pos)
    if not node then return false end
    local def = minetest.registered_nodes[node.name]
    if def and def.walkable then return false end
    return true
end

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

        -- Handle reset
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

        local pos = vector.round(self.object:get_pos())
        local dir = self.object:get_yaw()

        if self.timer >= (step.duration or 2) then
            if step.action == "forward" then
                local vel = vector.new(math.cos(dir), 0, math.sin(dir))
                self.object:set_velocity(vector.multiply(vel, step.speed or 2))
                self:set_anim("walk")

            elseif step.action == "turn_left" then
                self.object:set_yaw(dir + math.rad(90))
            elseif step.action == "turn_right" then
                self.object:set_yaw(dir - math.rad(90))
            elseif step.action == "stop" then
                self.object:set_velocity({x=0, y=0, z=0})
                self:set_anim("stand")
            elseif step.action == "texture" then
                self.object:set_properties({textures = {step.name}})
            elseif step.action == "chat" then
                minetest.chat_send_all("[NPC-"..(self.npc_id or "?").."] " .. step.msg)

            elseif step.action == "reset" then
                self.resetting = true

            elseif step.action == "loop" then
                local times = tonumber(step.times) or 1
                self.loop_count = times
                self.current_loop = 0
                self.program_index = 1
                self.resetting = false

            -- Smooth step movements with obstacle check
            elseif step.action:find("move_") then
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
                    self.moving = {target = target, duration = 0.5, timer = 0}
                    self.object:set_velocity(vector.multiply(vel, 2))
                    self:set_anim("walk")
                else
                    self.program_index = self.program_index + 1
                end
            end

            self.timer = 0
            if not self.moving then
                self.program_index = self.program_index + 1
            end

            if self.program_index > #self.program and self.loop_count > 0 then
                self.current_loop = self.current_loop + 1
                if self.current_loop < self.loop_count then
                    self.program_index = 1
                else
                    self.loop_count = 0
                    self.current_loop = 0
                    self.program_index = 1
                end
            end
        end
    end,
})

-- =========================
-- Chat Commands
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
    description = "Reset NPC to its spawn position",
    func = function(name, param)
        local npc = npc_list[param]
        if npc then
            npc.resetting = true
            minetest.chat_send_player(name, "NPC "..param.." is resetting.")
        else
            return false, "No NPC with ID "..param
        end
    end,
})

minetest.register_chatcommand("npc_loop", {
    params = "<id> <times>",
    description = "Loop NPC program n times",
    func = function(name, param)
        local id, times = param:match("^(%S+)%s+(%d+)$")
        local npc = npc_list[id]
        times = tonumber(times)
        if npc and times and times > 0 then
            npc.loop_count = times
            npc.current_loop = 0
            npc.program_index = 1
            npc.resetting = false
            minetest.chat_send_player(name, "NPC "..id.." will loop "..times.." times.")
        else
            return false, "Invalid NPC ID or times."
        end
    end,
})

-- Editor remains optional; you can keep formspec code if you want, or just use the chat commands.

