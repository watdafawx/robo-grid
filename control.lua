-- Robo Grid: grow the robot network on a square grid, and tidy roboports made redundant by upgraded ones.
--
-- Grid: roboports sit on a lattice anchored at an existing roboport, spaced by the logistic diameter of the
-- roboport placed (from settings), so their logistic squares tile exactly. A request (something built outside
-- coverage, or an area picked with the tool) is grown toward from the nearest covered cell, one cell at a time:
-- a roboport ghost is placed only where the network's construction area already reaches, so the bots can build
-- it; the next cell follows once it stands. Each new roboport gets a pole chain from the nearest pole and asks
-- the network for construction robots.
--
-- Tidy: a roboport may go when its logistic area stays covered by the others (actual radii: quality counts) and
-- the roboports overlapping it stay joined without it. Lowest quality / smallest area goes first.

local QUEUE_EVERY = 20         -- ticks between growth steps
local PER_STEP = 2             -- requests looked at per step (round-robin over the queue)
local function setting(name) return settings.global[name].value end
local function expire_ticks() return 60 * 60 * setting("robo-grid-request-minutes") end
local SEARCH = 4               -- tiles around a blocked spot to try
-- built things that never pull the network toward them (setting: entity types, comma separated)
local ignored_cache, ignored_src
local function ignored()
  local src = setting("robo-grid-ignore-types")
  if src ~= ignored_src then
    ignored_src, ignored_cache = src, {}
    for t in string.gmatch(src, "[^,%s]+") do ignored_cache[t] = true end
  end
  return ignored_cache
end

local function port_name()
  local n = setting("robo-grid-roboport")
  return prototypes.entity[n] and prototypes.entity[n].type == "roboport" and n or "roboport"
end

local function spacing()
  local p = prototypes.entity[port_name()]
  -- (spacing a little under the logistic diameter: neighbours overlap)
  return math.max(4, math.floor(2 * (p.logistic_radius or 25)) - setting("robo-grid-overlap"))
end

local function key(s, c) return s .. ":" .. c[1] .. "," .. c[2] end

--------------------------------------------------------------------------------
-- coverage
--------------------------------------------------------------------------------

-- answers within one growth step are remembered (the same cells are asked about again and again)
local memo = {}
local function remembered(tag, surface, pos, f)
  local k = tag .. surface.index .. ":" .. math.floor(pos.x) .. "," .. math.floor(pos.y)
  local v = memo[k]
  if v == nil then
    v = f()
    memo[k] = v
  end
  return v
end

local function covered(surface, force, pos)
  return remembered("c", surface, pos, function()
    return surface.find_logistic_network_by_position(pos, force) ~= nil
  end)
end

--- a roboport that works: on a power network (a fresh one has a full buffer, so energy alone says nothing) and
--- not drained (an unpowered one charges no bots, so nothing is grown from it)
local function working(rp)
  if not (rp.valid and rp.logistic_cell and rp.energy > 0) then return false end
  local ok, on = pcall(rp.is_connected_to_electric_network)
  return ok and on
end

--- the networks' own lookup first (its nearest cell), then the few roboports right around
local function any_cell(surface, force, pos, nets, test, radius)
  for _, net in pairs(nets) do
    local cell = net.find_cell_closest_to(pos)
    if cell and cell.valid and working(cell.owner) and test(cell) then return true end
  end
  for _, rp in pairs(surface.find_entities_filtered({ type = "roboport", force = force, position = pos, radius = radius })) do
    if working(rp) and test(rp.logistic_cell) then return true end
  end
  return false
end

--- can the bots of a working roboport build at pos? (inside its construction area)
local function reachable(surface, force, pos)
  return remembered("r", surface, pos, function()
    local ok, nets = pcall(surface.find_logistic_networks_by_construction_area, pos, force)
    nets = ok and nets or {}
    if #nets == 0 then return false end
    local r = prototypes.entity[port_name()].construction_radius or 55
    return any_cell(surface, force, pos, nets, function(c) return c.is_in_construction_range(pos) end, r + 2)
  end)
end

--- inside the logistic area of a working roboport?
local function covered_working(surface, force, pos)
  return remembered("w", surface, pos, function()
    local net = surface.find_logistic_network_by_position(pos, force)
    if not net then return false end
    local r = prototypes.entity[port_name()].logistic_radius or 25
    return any_cell(surface, force, pos, { net }, function(c) return c.is_in_logistic_range(pos) end, r + 2)
  end)
end

--------------------------------------------------------------------------------
-- the lattice
--------------------------------------------------------------------------------

local function anchor(surface, force, near)
  storage.anchor = storage.anchor or {}
  local a = storage.anchor[surface.index]
  if a then return a end
  local ports = surface.find_entities_filtered({ type = "roboport", force = force })
  if #ports == 0 then return nil end
  local best, bd
  for _, p in pairs(ports) do
    local d = (p.position.x - near.x) ^ 2 + (p.position.y - near.y) ^ 2
    if not bd or d < bd then best, bd = p, d end
  end
  a = { x = best.position.x, y = best.position.y }
  storage.anchor[surface.index] = a
  return a
end

local function cell_of(a, S, pos)
  return { math.floor((pos.x - a.x) / S + 0.5), math.floor((pos.y - a.y) / S + 0.5) }
end

local function center(a, S, c)
  return { x = a.x + c[1] * S, y = a.y + c[2] * S }
end

--- a roboport (or its ghost) at or near a grid point: within a quarter of the spacing, so one a player placed a few
--- tiles off the grid (or one nudged around an obstacle) counts, and no second one goes beside it
local function port_near(surface, force, pos)
  local name = port_name()
  local r = math.max(4, spacing() / 4)
  return surface.count_entities_filtered({ type = "roboport", force = force, position = pos, radius = r, limit = 1 }) > 0
      or surface.count_entities_filtered({ ghost_name = name, force = force, position = pos, radius = r, limit = 1 }) > 0
end

--- does the cell still need a roboport? (no roboport at its lattice point, and part of it uncovered)
local function needs(surface, force, a, S, c)
  local p = center(a, S, c)
  if port_near(surface, force, p) then return false end
  local h = S / 2 - 1
  for _, d in pairs({ { 0, 0 }, { -h, -h }, { h, -h }, { -h, h }, { h, h } }) do
    if not covered(surface, force, { x = p.x + d[1], y = p.y + d[2] }) then return true end
  end
  return false
end

--------------------------------------------------------------------------------
-- placing ghosts
--------------------------------------------------------------------------------

--- the nearest free spot for `name` around pos that the bots can reach (and isn't in `taken`), or nil
local function spot(surface, force, name, pos, taken)
  for r = 0, SEARCH do
    for dx = -r, r do
      for dy = -r, r do
        if math.max(math.abs(dx), math.abs(dy)) == r then
          local p = { x = pos.x + dx, y = pos.y + dy }
          local k = math.floor(p.x) .. "," .. math.floor(p.y)
          if not (taken and taken[k]) and surface.can_place_entity({ name = name, position = p, force = force,
              build_check_type = defines.build_check_type.manual_ghost }) and reachable(surface, force, p) then
            return p
          end
        end
      end
    end
  end
  return nil
end

local function ghost(surface, force, name, p)
  return surface.create_entity({ name = "entity-ghost", inner_name = name, position = p, force = force, expires = false })
end

local function is_hidden(pole) return string.find(pole.name, "invisible", 1, true) ~= nil end

--- the power networks of the working roboports near pos (a pole on one of them has power)
local function powered_nets(surface, force, pos)
  local nets = {}
  for _, rp in pairs(surface.find_entities_filtered({ type = "roboport", force = force, position = pos, radius = 200 })) do
    if working(rp) and rp.electric_network_id then nets[rp.electric_network_id] = true end
  end
  return nets
end

--- the pole positions from `start` to beside the roboport, every one placeable and in the bots' reach, or nil
local function chain(surface, force, pole, reach, stop, start, rp_pos)
  local out, taken, last = {}, {}, { x = start.x, y = start.y }
  for _ = 1, 40 do
    local dx, dy = rp_pos.x - last.x, rp_pos.y - last.y
    local d = math.sqrt(dx * dx + dy * dy)
    if d <= stop then return out end
    local step = math.min(reach, d - stop + 0.5)
    local want = { x = math.floor(last.x + dx / d * step) + 0.5, y = math.floor(last.y + dy / d * step) + 0.5 }
    local p = spot(surface, force, pole, want, taken)
    if not p then return nil end
    -- (a spot moved off the line must still be in wire reach of the last pole)
    if math.sqrt((p.x - last.x) ^ 2 + (p.y - last.y) ^ 2) > reach + 0.5 then return nil end
    taken[math.floor(p.x) .. "," .. math.floor(p.y)] = true
    out[#out + 1] = p
    last = p
  end
  return nil
end

--- poles from the nearest powered pole (or pole ghost) whose whole chain the bots can build
local function power(surface, force, rp_pos)
  local pole = setting("robo-grid-pole")
  local proto = prototypes.entity[pole]
  if not (proto and proto.type == "electric-pole") then return "the pole setting isn't a pole" end
  local reach = math.floor(proto.get_max_wire_distance() or 7.5) - 1
  local stop = (proto.get_supply_area_distance() or 2.5) + 1.5 -- this close to the roboport's centre powers it (4x4)
  local starts, nets = {}, powered_nets(surface, force, rp_pos)
  for _, p in pairs(surface.find_entities_filtered({ type = "electric-pole", force = force, position = rp_pos, radius = 120 })) do
    if not is_hidden(p) and p.electric_network_id and nets[p.electric_network_id] then starts[#starts + 1] = p end
  end
  for _, g in pairs(surface.find_entities_filtered({ ghost_type = "electric-pole", force = force, position = rp_pos, radius = 120 })) do
    starts[#starts + 1] = g
  end
  local function dist(p) return (p.position.x - rp_pos.x) ^ 2 + (p.position.y - rp_pos.y) ^ 2 end
  table.sort(starts, function(a, b) return dist(a) < dist(b) end)
  for i = 1, math.min(#starts, 8) do
    local c = chain(surface, force, pole, reach, stop, starts[i].position, rp_pos)
    if c then
      storage.ours = storage.ours or {}
      for _, p in pairs(c) do
        local g = ghost(surface, force, pole, p)
        if g then storage.ours[key(surface.index, { math.floor(g.position.x), math.floor(g.position.y) })] = true end
      end
      return nil
    end
  end
  return #starts == 0 and "no powered pole nearby to power it from" or "no pole chain the bots can build"
end

local function place_port(surface, force, pos, pinned)
  local p = spot(surface, force, port_name(), pos)
  if not p then return false end
  local g = ghost(surface, force, port_name(), p)
  if not g then return false end
  local problem = power(surface, force, g.position)
  storage.notes = storage.notes or {}
  if problem then storage.notes[#storage.notes + 1] = problem end
  storage.ours = storage.ours or {}
  -- (pinned: placed for an area picked with the tool, so never removed as covering nothing)
  storage.ours[key(surface.index, { math.floor(g.position.x), math.floor(g.position.y) })] = pinned and "pinned" or true
  return true
end

-- grid cells tidy removed a roboport from: not grown into again for a while (else grow and tidy take turns)
local BLOCK_TICKS = 60 * 60 * 60

local function cell_key_of(surface, pos)
  local a = storage.anchor and storage.anchor[surface.index]
  if not a then return nil end
  local S = spacing()
  return key(surface.index, { math.floor((pos.x - a.x) / S + 0.5), math.floor((pos.y - a.y) / S + 0.5) })
end

local function block(rp)
  local k = cell_key_of(rp.surface, rp.position)
  if k then
    storage.blocked = storage.blocked or {}
    storage.blocked[k] = game.tick
  end
end

local function blocked(surface, c)
  local t = storage.blocked and storage.blocked[key(surface.index, c)]
  return t ~= nil and game.tick - t < BLOCK_TICKS
end

--------------------------------------------------------------------------------
-- growing toward requests
--------------------------------------------------------------------------------

--- the nearest covered cell to c (rings out to max), or nil
local function nearest_covered(surface, force, a, S, c, max)
  for r = 0, max do
    local best, bd
    for dx = -r, r do
      for dy = -r, r do
        if math.max(math.abs(dx), math.abs(dy)) == r then
          local cc = { c[1] + dx, c[2] + dy }
          if covered_working(surface, force, center(a, S, cc)) then
            local d = dx * dx + dy * dy
            if not bd or d < bd then best, bd = cc, d end
          end
        end
      end
    end
    if best then return best end
  end
  return nil
end

--- an enemy nest or worm near pos?
local function enemies_near(surface, force, pos)
  return remembered("e", surface, pos, function()
    for _, e in pairs(surface.find_entities_filtered({ type = { "unit-spawner", "turret" }, position = pos,
        radius = setting("robo-grid-enemy-range"), limit = 20 })) do
      if force.is_enemy(e.force) then return true end
    end
    return false
  end)
end

--- one step toward a request -> "done" | "wait" | "drop"
local function grow(req)
  local surface = game.get_surface(req.surface)
  local force = game.forces[req.force]
  if not (surface and force) then return "drop" end
  local a = anchor(surface, force, req.pos)
  if not a then return "drop" end
  local S = spacing()
  local t = cell_of(a, S, req.pos)
  if covered(surface, force, req.pos) and not needs(surface, force, a, S, t) then return "done" end
  local c = nearest_covered(surface, force, a, S, t, setting("robo-grid-max-cells"))
  if not c then return "drop" end
  -- walk from the covered cell to the target, the longer axis first
  local cur = { c[1], c[2] }
  for _ = 1, 400 do
    if needs(surface, force, a, S, cur) then
      local p = center(a, S, cur)
      if enemies_near(surface, force, p) then return "drop" end -- (the bots and the roboport would be lost)
      if blocked(surface, cur) then return "drop" end -- (tidy just took a roboport out of this cell)
      if reachable(surface, force, p) then
        place_port(surface, force, p, req.pinned) -- (no reachable spot yet: try again later)
      end
      return "wait" -- placed, or the bots can't reach it yet
    end
    if cur[1] == t[1] and cur[2] == t[2] then
      return covered(surface, force, req.pos) and "done" or "wait"
    end
    local dx, dy = t[1] - cur[1], t[2] - cur[2]
    if math.abs(dx) >= math.abs(dy) then cur[1] = cur[1] + (dx > 0 and 1 or -1)
    else cur[2] = cur[2] + (dy > 0 and 1 or -1) end
  end
  return "drop"
end

local function request(surface, force, pos, pinned)
  storage.queue = storage.queue or {}
  local a = anchor(surface, force, pos)
  if not a then return false end
  local k = key(surface.index, cell_of(a, spacing(), pos))
  if storage.queue[k] then
    storage.queue[k].pinned = storage.queue[k].pinned or pinned
    return true
  end
  storage.queue[k] = { surface = surface.index, force = force.name, pos = { x = pos.x, y = pos.y }, tick = game.tick,
    pinned = pinned }
  return true
end

--- a few requests per step, round-robin, so a big area queued by the tool never costs a tick much
local function step_queue()
  memo = {}
  local queue = storage.queue or {}
  local k = storage.cursor
  if k ~= nil and queue[k] == nil then k = nil end
  local pick, n = {}, 0
  for _ = 1, PER_STEP * 20 do -- (skipping requests that wait for their next try)
    k = next(queue, k)
    if k == nil then k = next(queue) end -- wrap around
    if k == nil or pick[k] then break end
    if (queue[k].next or 0) <= game.tick then
      pick[k] = true
      n = n + 1
      if n >= PER_STEP then break end
    end
  end
  storage.cursor = k
  for key in pairs(pick) do
    local req = queue[key]
    local r = game.tick - req.tick > expire_ticks() and "drop" or grow(req)
    if r ~= "wait" then
      if storage.cursor == key then storage.cursor = nil end
      queue[key] = nil
    else
      -- waiting (bots building, or out of reach for now): look again later, less often each time
      req.wait = math.min((req.wait or 60) * 2, 60 * 10)
      req.next = game.tick + req.wait
    end
  end
  memo = {}
end

--------------------------------------------------------------------------------
-- new roboports: ask for bots
--------------------------------------------------------------------------------

local function ask_for_bots(rp)
  local n = setting("robo-grid-bots")
  if n <= 0 or not prototypes.item["construction-robot"] then return end
  local ok, sections = pcall(rp.get_logistic_sections)  -- (a roboport's robot / repair pack requests)
  if not (ok and sections) then return end
  local section = sections.add_section()
  if section then
    section.set_slot(1, { value = { type = "item", name = "construction-robot", quality = "normal" }, min = n })
  end
end

--------------------------------------------------------------------------------
-- tidy
--------------------------------------------------------------------------------

local function radius(rp)
  local cell = rp.logistic_cell
  return cell and cell.logistic_radius or (rp.prototype.logistic_radius or 25)
end

local function in_square(rp, r, p)
  return math.abs(p.x - rp.position.x) <= r and math.abs(p.y - rp.position.y) <= r
end

local function overlap(a, ra, b, rb)
  return math.abs(a.position.x - b.position.x) <= ra + rb and math.abs(a.position.y - b.position.y) <= ra + rb
end

--- every point of rp's logistic square covered by the others?
local function area_covered(rp, others, removed)
  local r = radius(rp)
  local x, y = rp.position.x, rp.position.y
  local list = {}
  for _, o in pairs(others) do
    if o ~= rp and o.valid and not removed[o.unit_number] and not o.to_be_deconstructed()
        and overlap(rp, r, o, radius(o)) then
      list[#list + 1] = { o, radius(o) }
    end
  end
  local stepn = math.max(2, math.floor(r / 6))
  for i = 0, stepn do
    for j = 0, stepn do
      local p = { x = x - r + 0.5 + (2 * r - 1) * i / stepn, y = y - r + 0.5 + (2 * r - 1) * j / stepn }
      local ok = false
      for _, e in pairs(list) do
        if in_square(e[1], e[2], p) then ok = true break end
      end
      if not ok then return false end
    end
  end
  return true
end

--- do the roboports overlapping rp stay joined without it?
local function stays_joined(rp, surface, removed)
  local r = radius(rp)
  local near = surface.find_entities_filtered({ type = "roboport", force = rp.force, position = rp.position, radius = 4 * r })
  local nbrs, all = {}, {}
  for _, o in pairs(near) do
    if o ~= rp and not removed[o.unit_number] and not o.to_be_deconstructed() then
      all[#all + 1] = o
      if overlap(rp, r, o, radius(o)) then nbrs[#nbrs + 1] = o end
    end
  end
  if #nbrs <= 1 then return true end
  local seen, todo, head = { [nbrs[1].unit_number] = true }, { nbrs[1] }, 1
  while todo[head] do
    local a = todo[head]
    head = head + 1
    for _, b in pairs(all) do
      if not seen[b.unit_number] and overlap(a, radius(a), b, radius(b)) then
        seen[b.unit_number] = true
        todo[#todo + 1] = b
      end
    end
  end
  for _, n in pairs(nbrs) do
    if not seen[n.unit_number] then return false end -- (only checks within 4 radii: a far detour counts as split)
  end
  return true
end

local function tidy_plan(ports)
  local removed, out, list = {}, {}, {}
  for _, p in pairs(ports) do
    if p.valid and p.type == "roboport" and not p.to_be_deconstructed() then list[#list + 1] = p end
  end
  local k = {}
  for _, p in pairs(list) do k[p.unit_number] = { p.quality.level, radius(p), p.unit_number } end
  table.sort(list, function(a, b)
    local ka, kb = k[a.unit_number], k[b.unit_number]
    for i = 1, 3 do if ka[i] ~= kb[i] then return ka[i] < kb[i] end end
    return false
  end)
  for _, p in pairs(list) do
    local surface = p.surface
    local others = surface.find_entities_filtered({ type = "roboport", force = p.force, position = p.position,
      radius = 3 * radius(p) })
    if area_covered(p, others, removed) and stays_joined(p, surface, removed) then
      removed[p.unit_number] = true
      out[#out + 1] = p
    end
  end
  return out
end

local function tidy(ports, player)
  local n = 0
  for _, p in pairs(tidy_plan(ports)) do
    if p.order_deconstruction(p.force, player) then
      n = n + 1
      block(p)
    end
  end
  return n
end

-- what a roboport's area may hold and still count as covering nothing: poles, roboports, robots, the player, and
-- the ignored types (turrets set up to clear a nest)
local NOT_WANTED = { "electric-pole", "roboport", "character", "construction-robot", "logistic-robot",
  "entity-ghost", "corpse", "character-corpse", "item-entity" }
local NOT_WANTED_SET = {}
for _, t in pairs(NOT_WANTED) do NOT_WANTED_SET[t] = true end

--- a roboport of ours whose logistic area has nothing in it that needs the network
local function covers_nothing(rp)
  local r = radius(rp)
  local x, y = rp.position.x, rp.position.y
  local area = { { x - r, y - r }, { x + r, y + r } }
  -- (a plain loop: count_entities_filtered's invert would invert the force filter too)
  local skip = ignored()
  for _, e in pairs(rp.surface.find_entities_filtered({ area = area, force = rp.force })) do
    local t = e.type
    if t == "entity-ghost" then
      t = e.ghost_type
      if t ~= "electric-pole" and t ~= "roboport" and not skip[t] then return false end -- a ghost the bots should build
    elseif not NOT_WANTED_SET[t] and not skip[t] then
      return false
    end
  end
  return true
end

--- remove roboports this mod built that cover nothing, from the network's edge in (never splitting it)
local function remove_empty(player)
  local n = 0
  -- the farthest from the grid's anchor first, so the straight way back is what stays
  local list, pinned = {}, storage.pinned_ports or {}
  for unit, rp in pairs(storage.our_ports or {}) do
    if not rp.valid then
      storage.our_ports[unit] = nil
      pinned[unit] = nil
    elseif not pinned[unit] and not rp.to_be_deconstructed() and covers_nothing(rp) then
      list[#list + 1] = rp -- (what's in an area doesn't change while this runs: looked at once)
    end
  end
  local function far(rp)
    local a = storage.anchor and storage.anchor[rp.surface.index] or { x = 0, y = 0 }
    return (rp.position.x - a.x) ^ 2 + (rp.position.y - a.y) ^ 2
  end
  table.sort(list, function(a, b) return far(a) > far(b) end)
  for _ = 1, 20 do -- a pass per ring from the edge
    local changed = false
    for _, rp in ipairs(list) do
      if rp.valid and not rp.to_be_deconstructed() and stays_joined(rp, rp.surface, {}) then
        if rp.order_deconstruction(rp.force, player) then
          n, changed = n + 1, true
          block(rp)
        end
      end
    end
    if not changed then break end
  end
  return n
end

local COPPER = defines.wire_connector_id.pole_copper

--- does the pole power anything (a building with electric power in its supply area)?
local function supplies(pole)
  local d = pole.prototype.get_supply_area_distance(pole.quality)
  local p = pole.position
  for _, e in pairs(pole.surface.find_entities_filtered({ area = { { p.x - d, p.y - d }, { p.x + d, p.y + d } },
      force = pole.force })) do
    if e.type ~= "electric-pole" and not e.to_be_deconstructed() then
      local proto = e.type == "entity-ghost" and e.ghost_prototype or e.prototype
      if proto.electric_energy_source_prototype and proto.type ~= "electric-pole" then return true end
    end
  end
  return false
end

--- a hidden pole's building (power-propagation puts one in every powered building): still there, not marked to go?
local function building_stays(hidden)
  for _, e in pairs(hidden.surface.find_entities_filtered({ position = hidden.position, force = hidden.force })) do
    if e.type ~= "electric-pole" and e.unit_number then return not e.to_be_deconstructed() end
  end
  return false
end

--- remove poles this mod built that power nothing and end a chain, peeling chains back from their ends
local function prune_poles(player)
  local n = 0
  for _ = 1, 60 do -- a pass per pole along the longest chain
    local changed = false
    for unit, pole in pairs(storage.our_poles or {}) do
      if not pole.valid then
        storage.our_poles[unit] = nil
      elseif not pole.to_be_deconstructed() then
        local real, linked_building = 0, false
        local c = pole.get_wire_connector(COPPER, false)
        for _, w in pairs(c and c.connections or {}) do
          local o = w.target.owner
          if o.valid and not o.to_be_deconstructed() then
            if not is_hidden(o) then
              real = real + 1
            elseif building_stays(o) then -- (power-propagation's pole in a building that isn't going)
              linked_building = true
            end
          end
        end
        if real <= 1 and not linked_building and not supplies(pole) then
          if pole.order_deconstruction(pole.force, player) then
            n, changed = n + 1, true
          end
        end
      end
    end
    if not changed then break end
  end
  return n
end

--- everything tidy does: redundant roboports (in `ports`), then empty ones of ours, then leftover poles of ours
local function tidy_all(ports, player)
  local n = tidy(ports, player)
  local e = setting("robo-grid-remove-empty") and remove_empty(player) or 0
  return n, e, prune_poles(player)
end

--------------------------------------------------------------------------------
-- events
--------------------------------------------------------------------------------

-- the toggles: buttons in the top-left mod button bar (mod-gui), lit while on
local mod_gui = require("mod-gui")
local BUTTONS = {
  robo_grid_auto = { sprite = "item/roboport", tooltip = { "robo-grid.auto-tooltip" }, flag = "auto" },
  robo_grid_tidy = { sprite = "utility/trash", tooltip = { "robo-grid.tidy-tooltip" }, flag = "tidy" },
}

local function sync_toggles()
  for _, p in pairs(game.players) do
    local flow = mod_gui.get_button_flow(p)
    for name, b in pairs(BUTTONS) do
      local el = flow[name] or flow.add({ type = "sprite-button", name = name, sprite = b.sprite,
        style = mod_gui.button_style, tooltip = b.tooltip })
      el.toggled = storage[b.flag] == true
    end
  end
end

script.on_event(defines.events.on_gui_click, function(e)
  local player = game.get_player(e.player_index)
  local name = e.element.valid and e.element.name
  if name == "robo_grid_auto" then
    storage.auto = not storage.auto
    player.print(storage.auto and "Robo Grid: the robot network grows to what you build outside it."
      or "Robo Grid: auto-grow off.")
  elseif name == "robo_grid_tidy" then
    storage.tidy = not storage.tidy
    player.print(storage.tidy and "Robo Grid: roboports made redundant by upgraded ones are removed."
      or "Robo Grid: auto-tidy off.")
  else
    return
  end
  sync_toggles()
end)

script.on_event(defines.events.on_player_selected_area, function(e)
  if e.item ~= "robo-grid-tool" then return end
  local player = game.get_player(e.player_index)
  local surface, force = e.surface, player.force
  local a = anchor(surface, force, { x = (e.area.left_top.x + e.area.right_bottom.x) / 2,
    y = (e.area.left_top.y + e.area.right_bottom.y) / 2 })
  if not a then
    player.create_local_flying_text({ create_at_cursor = true, text = "Place a roboport first: the grid grows from it" })
    return
  end
  local S = spacing()
  local c1, c2 = cell_of(a, S, e.area.left_top), cell_of(a, S, e.area.right_bottom)
  local n = 0
  for i = c1[1], c2[1] do
    for j = c1[2], c2[2] do
      if storage.blocked then storage.blocked[key(surface.index, { i, j })] = nil end -- (asked for explicitly)
      if n < 400 and request(surface, force, center(a, S, { i, j }), true) then n = n + 1 end
    end
  end
  step_queue()
  player.create_local_flying_text({ create_at_cursor = true, text = n .. " grid cell(s) queued; the network grows edge-first" })
end)

script.on_event(defines.events.on_player_alt_selected_area, function(e)
  if e.item ~= "robo-grid-tool" then return end
  local player = game.get_player(e.player_index)
  local n, empty, poles = tidy_all(e.entities, player)
  player.create_local_flying_text({ create_at_cursor = true,
    text = (n + empty + poles == 0) and "Nothing to tidy" or
      (n .. " redundant + " .. empty .. " empty roboport(s), " .. poles .. " leftover pole(s) marked for removal") })
end)

-- something built outside coverage: grow toward it
script.on_event(defines.events.on_built_entity, function(e)
  local ent = e.entity
  if not (storage.auto and ent and ent.valid) then return end
  local t = ent.type == "entity-ghost" and ent.ghost_type or ent.type
  if ignored()[t] then return end
  memo = {}
  if not covered(ent.surface, ent.force, ent.position) and not enemies_near(ent.surface, ent.force, ent.position) then
    request(ent.surface, ent.force, ent.position)
  end
end)

-- a roboport or pole built: one of ours is remembered (a roboport asks for bots); an upgraded roboport gets its
-- neighbourhood auto-tidied
local function on_port(e)
  local rp = e.entity
  if not (rp and rp.valid) then return end
  storage.ours = storage.ours or {}
  local k = key(rp.surface.index, { math.floor(rp.position.x), math.floor(rp.position.y) })
  if rp.type == "electric-pole" then
    if storage.ours[k] then
      storage.ours[k] = nil
      storage.our_poles = storage.our_poles or {}
      storage.our_poles[rp.unit_number] = rp
    end
    return
  end
  if rp.type ~= "roboport" then return end
  local ours = storage.ours[k]
  if ours then
    storage.ours[k] = nil
    storage.our_ports = storage.our_ports or {}
    storage.our_ports[rp.unit_number] = rp
    if ours == "pinned" then
      storage.pinned_ports = storage.pinned_ports or {}
      storage.pinned_ports[rp.unit_number] = true
    end
    ask_for_bots(rp)
    return -- (a roboport we just built is no upgrade: nothing to tidy)
  end
  if storage.tidy then
    storage.tidy_pending = storage.tidy_pending or {}
    storage.tidy_pending[#storage.tidy_pending + 1] = rp
  end
end
local port_filter = { { filter = "type", type = "roboport" }, { filter = "type", type = "electric-pole" } }
script.on_event(defines.events.on_robot_built_entity, on_port, port_filter)
script.on_event(defines.events.script_raised_built, on_port, port_filter)

script.on_nth_tick(QUEUE_EVERY, function(ev)
  step_queue()
  -- auto-tidy also looks over everything we built every few minutes (empty roboports, leftover poles)
  if storage.tidy and ev.tick % (60 * 60 * setting("robo-grid-tidy-minutes")) < QUEUE_EVERY then
    -- (our own roboports also get the redundancy check: one placed beside another goes)
    local ours = {}
    for _, rp in pairs(storage.our_ports or {}) do if rp.valid then ours[#ours + 1] = rp end end
    tidy_all(ours)
  end
  local pending = storage.tidy_pending
  if pending and #pending > 0 then
    storage.tidy_pending = {}
    for _, rp in pairs(pending) do
      if rp.valid then
        local r = 3 * radius(rp)
        tidy(rp.surface.find_entities_filtered({ type = "roboport", force = rp.force, position = rp.position, radius = r }))
      end
    end
  end
end)

script.on_init(function()
  storage.queue, storage.ours, storage.anchor, storage.tidy_pending = {}, {}, {}, {}
  sync_toggles()
end)
script.on_configuration_changed(sync_toggles)
script.on_event(defines.events.on_player_created, sync_toggles)
script.on_event(defines.events.on_player_joined_game, sync_toggles)

-- for automated tests
remote.add_interface("robo-grid", {
  request = function(surface, force, pos, pinned) return request(surface, force, pos, pinned) end,
  step = function() step_queue() end,
  queue_size = function() return table_size(storage.queue or {}) end,
  tidy = function(ports) return tidy(ports) end,
  tidy_all = function(ports) return tidy_all(ports or {}) end,
  tidy_count = function(ports) return #tidy_plan(ports) end,
  set = function(k, v) storage[k] = v end,
  notes = function() return storage.notes or {} end,
})
