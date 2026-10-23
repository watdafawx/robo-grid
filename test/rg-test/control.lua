local out = {}
local function log(s) out[#out + 1] = s end

script.on_nth_tick(5, function(ev)
  if ev.tick ~= 5 then return end
  local s, f = game.surfaces.nauvis, game.forces.player
  s.always_day = true
  local area = { { -60, -120 }, { 260, 120 } }
  for _, e in pairs(s.find_entities_filtered({ area = area })) do if e.valid and e.type ~= "character" then e.destroy() end end
  local tiles = {}
  for x = -60, 260 do for y = -120, 120 do tiles[#tiles + 1] = { name = "lab-dark-1", position = { x, y } } end end
  s.set_tiles(tiles)
  s.create_entity({ name = "electric-energy-interface", position = { -6, -6 }, force = f })
  s.create_entity({ name = "substation", position = { -3, -3 }, force = f })
  local rp = s.create_entity({ name = "roboport", position = { 2, 2 }, force = f })
  rp.insert({ name = "construction-robot", count = 50 })
  local chest = s.create_entity({ name = "storage-chest", position = { 6.5, -3.5 }, force = f })
  chest.insert({ name = "roboport", count = 10 })
  chest.insert({ name = "medium-electric-pole", count = 50 })
  chest.insert({ name = "construction-robot", count = 50 })
  -- quality: does it change a roboport's area here?
  local q = s.create_entity({ name = "roboport", position = { 200, 100 }, force = f, quality = "legendary" })
  log("roboport logistic radius normal " .. rp.logistic_cell.logistic_radius .. ", legendary " .. q.logistic_cell.logistic_radius)
  q.destroy()
  local ok, pt = pcall(rp.get_requester_point)
  log("requester point: " .. tostring(ok) .. " " .. tostring(pt) .. " sections " .. tostring(ok and pt and #pt.sections))
  local ok2, ls = pcall(rp.get_logistic_sections)
  log("logistic sections: " .. tostring(ok2) .. " " .. tostring(ls))
  local ok3, pts = pcall(rp.get_logistic_point)
  if ok3 then for i, p in pairs(pts or {}) do log("  point " .. i .. " mode " .. tostring(p.mode) .. " sections " .. tostring(p.sections and #p.sections)) end end
  local sub = s.find_entities_filtered({ name = "substation" })[1]
  local ok, v = pcall(sub.is_connected_to_electric_network)
  log("substation connected: " .. tostring(ok) .. " " .. tostring(v) .. " net " .. tostring(sub.electric_network_id))
  local dead0 = s.create_entity({ name = "roboport", position = { 200, 60 }, force = f })
  log("fresh unpowered roboport: energy " .. dead0.energy .. " status " .. tostring(dead0.status) .. " connected " .. tostring(dead0.is_connected_to_electric_network()))
  log("powered roboport: energy " .. rp.energy .. " status " .. tostring(rp.status) .. " connected " .. tostring(rp.is_connected_to_electric_network()))
  dead0.destroy()
  remote.call("robo-grid", "request", s, f, { x = 150, y = 2 })
  -- a biter nest: a request 20 tiles from it is dropped, nothing is built there
  local nest = s.create_entity({ name = "biter-spawner", position = { 230, 100 }, force = "enemy" })
  nest.disabled_by_script = true
  remote.call("robo-grid", "request", s, f, { x = 210, y = 100 })
  -- a roboport without power, with bots: nothing may grow from it (its bots couldn't charge)
  local dead = s.create_entity({ name = "roboport", position = { 2, -80 }, force = f })
  dead.insert({ name = "construction-robot", count = 20 })
  remote.call("robo-grid", "request", s, f, { x = 150, y = -80 })
  storage.t0 = game.tick
  helpers.write_file("rg-test.txt", table.concat(out, "\n") .. "\n")
end)

script.on_nth_tick(600, function(ev)
  local s, f = game.surfaces.nauvis, game.forces.player
  if ev.tick % 3000 == 0 or ev.tick == 18000 then
    local ports = s.count_entities_filtered({ name = "roboport", force = f })
    local ghosts = s.count_entities_filtered({ ghost_name = "roboport", force = f })
    local poles = s.count_entities_filtered({ name = "medium-electric-pole", force = f })
    log("t=" .. ev.tick .. ": roboports " .. ports .. ", roboport ghosts " .. ghosts .. ", poles " .. poles ..
      ", target covered " .. tostring(s.find_logistic_network_by_position({ x = 150, y = 2 }, f) ~= nil) ..
      ", queue " .. remote.call("robo-grid", "queue_size"))
  end
  if ev.tick == 18000 then
    local net = s.find_logistic_network_by_position({ x = 2, y = 2 }, f)
    log("near the unpowered roboport: roboports " .. s.count_entities_filtered({ name = "roboport", area = { { 20, -110 }, { 200, -50 } } })
      .. ", ghosts " .. s.count_entities_filtered({ ghost_name = "roboport", area = { { 20, -110 }, { 200, -50 } } }))
    log("near the nest: roboports " .. s.count_entities_filtered({ name = "roboport", position = { 230, 100 }, radius = 64 })
      .. ", ghosts " .. s.count_entities_filtered({ ghost_name = "roboport", position = { 230, 100 }, radius = 64 }))
    log("one network: " .. tostring(net == s.find_logistic_network_by_position({ x = 150, y = 2 }, f)))
    for _, rp in pairs(s.find_entities_filtered({ name = "roboport", force = f })) do
      local ls = rp.get_logistic_sections()
      local sec
      for _, x in pairs(ls and ls.sections or {}) do if x.filters_count > 0 then sec = x end end
      log("  roboport at " .. rp.position.x .. "," .. rp.position.y .. " powered " .. tostring(rp.energy > 0) ..
        " bots " .. rp.get_inventory(defines.inventory.roboport_robot).get_item_count() ..
        " request " .. tostring(sec and sec.filters[1] and sec.filters[1].min))
    end
    log("notes: " .. table.concat(remote.call("robo-grid", "notes"), "; "))
    -- the tool over a big area: 400 cells queued, then one growth step timed
    local n = 0
    for i = -10, 9 do for j = -10, 9 do
      if remote.call("robo-grid", "request", s, f, { x = 2 + i * 48, y = 2 + j * 48 }) then n = n + 1 end
    end end
    local prof = helpers.create_profiler()
    remote.call("robo-grid", "step")
    prof.stop()
    helpers.write_file("rg-prof.txt", { "", "queued " .. n .. ", queue " .. remote.call("robo-grid", "queue_size") .. ", one step: ", prof, "\n" })
    -- tidy: an extra roboport inside the grid's coverage goes, the grid stays
    local extra = s.create_entity({ name = "roboport", position = { 30, 2 }, force = f })
    local all = s.find_entities_filtered({ name = "roboport", force = f })
    log("tidy would remove " .. remote.call("robo-grid", "tidy_count", all) .. " (expect the extra at 30)")
    remote.call("robo-grid", "tidy", all)
    local gone = {}
    for _, rp in pairs(s.find_entities_filtered({ name = "roboport", force = f, to_be_deconstructed = true })) do
      gone[#gone + 1] = rp.position.x .. "," .. rp.position.y
    end
    log("marked: " .. table.concat(gone, " "))
    -- full tidy: a machine under the grid roboport at 146,2 keeps it and the way back; the grid roboports over
    -- empty ground go, with their pole chains
    for _, rp in pairs(s.find_entities_filtered({ name = "roboport", force = f, to_be_deconstructed = true })) do rp.destroy() end
    local m = s.create_entity({ name = "assembling-machine-1", position = { 150.5, 10.5 }, force = f })
    local poles0 = s.count_entities_filtered({ name = "medium-electric-pole", force = f })
    local r1, r2, r3 = remote.call("robo-grid", "tidy_all", {})
    log("tidy_all: redundant " .. r1 .. ", empty " .. r2 .. ", poles " .. r3 .. " (of " .. poles0 .. ")")
    local kept = {}
    for _, rp in pairs(s.find_entities_filtered({ name = "roboport", force = f, to_be_deconstructed = false })) do
      kept[#kept + 1] = rp.position.x .. "," .. rp.position.y
    end
    log("roboports kept: " .. table.concat(kept, " "))
    -- the bots' work, done at once
    for _, e in pairs(s.find_entities_filtered({ force = f, to_be_deconstructed = true })) do e.destroy() end
    local base = s.find_logistic_network_by_position({ x = 2, y = 2 }, f)
    log("after removal: machine covered by the base network " .. tostring(base ~= nil and base == s.find_logistic_network_by_position(m.position, f))
      .. ", every kept roboport connected " .. tostring((function()
        for _, rp in pairs(s.find_entities_filtered({ name = "roboport", force = f })) do
          if rp.position.y ~= -80 and not rp.is_connected_to_electric_network() then return false end
        end
        return true end)()))
    helpers.write_file("rg-test.txt", table.concat(out, "\n") .. "\n")
  end
end)
