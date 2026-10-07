local out = {}
local function log(s) out[#out + 1] = s end
local R = "robo-grid"

local function counts(s, f)
  return "roboports " .. s.count_entities_filtered({ name = "roboport", force = f, to_be_deconstructed = false }) ..
    ", ghosts " .. s.count_entities_filtered({ ghost_name = "roboport", force = f }) ..
    ", marked " .. s.count_entities_filtered({ name = "roboport", force = f, to_be_deconstructed = true })
end

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
  chest.insert({ name = "roboport", count = 20 })
  chest.insert({ name = "medium-electric-pole", count = 100 })
  remote.call(R, "request", s, f, { x = 150, y = 2 })  -- as auto-grow does (not pinned)
end)

-- the bots' removals, done at once
local function remove_marked(s, f)
  for _, e in pairs(s.find_entities_filtered({ force = f, to_be_deconstructed = true })) do e.destroy() end
end

script.on_nth_tick(1500, function(ev)
  local s, f = game.surfaces.nauvis, game.forces.player
  local t = ev.tick
  if t == 7500 then
    log("grown: " .. counts(s, f))
    local a, b, c = remote.call(R, "tidy_all")
    log("tidy over empty ground: empty " .. b .. ", poles " .. c .. " -> " .. counts(s, f))
    remove_marked(s, f)
    remote.call(R, "request", s, f, { x = 150, y = 2 })  -- the same request again (the loop's trigger)
  elseif t == 12000 then
    log("after re-request (should not regrow): " .. counts(s, f) .. ", queue " .. remote.call(R, "queue_size"))
    remote.call(R, "set", "blocked", {})                   -- the tool clears blocks in its area
    remote.call(R, "request", s, f, { x = 150, y = 2 }, true)
  elseif t == 18000 then
    log("tool-style request: " .. counts(s, f))
    local a, b, c = remote.call(R, "tidy_all")
    log("tidy again (pinned stay): empty " .. b .. " -> " .. counts(s, f))
    helpers.write_file("rg-loop.txt", table.concat(out, "\n") .. "\n")
  end
end)
