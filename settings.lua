data:extend({
  { type = "string-setting", name = "robo-grid-roboport", setting_type = "runtime-global", default_value = "roboport", order = "a" },
  { type = "string-setting", name = "robo-grid-pole", setting_type = "runtime-global", default_value = "medium-electric-pole", order = "b" },
  { type = "int-setting", name = "robo-grid-bots", setting_type = "runtime-global", default_value = 10, minimum_value = 0, maximum_value = 1000, order = "c" },
  { type = "int-setting", name = "robo-grid-max-cells", setting_type = "runtime-global", default_value = 12, minimum_value = 1, maximum_value = 100, order = "d" },
  { type = "int-setting", name = "robo-grid-enemy-range", setting_type = "runtime-global", default_value = 64, minimum_value = 0, maximum_value = 1000, order = "e" },
  { type = "string-setting", name = "robo-grid-ignore-types", setting_type = "runtime-global", allow_blank = true, order = "f",
    default_value = "ammo-turret,electric-turret,fluid-turret,artillery-turret,land-mine,car,spider-vehicle,locomotive,cargo-wagon,fluid-wagon,artillery-wagon" },
  { type = "int-setting", name = "robo-grid-overlap", setting_type = "runtime-global", default_value = 2, minimum_value = 0, maximum_value = 20, order = "g" },
  { type = "int-setting", name = "robo-grid-request-minutes", setting_type = "runtime-global", default_value = 30, minimum_value = 1, maximum_value = 600, order = "h" },
  { type = "bool-setting", name = "robo-grid-remove-empty", setting_type = "runtime-global", default_value = true, order = "i" },
  { type = "int-setting", name = "robo-grid-tidy-minutes", setting_type = "runtime-global", default_value = 5, minimum_value = 1, maximum_value = 600, order = "j" },
})
