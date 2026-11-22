-- tropiii v1.0.0

local max, min, flr, rnd = math.max, math.min, math.floor, math.random
local function clamp(v, lo, hi) return max(lo, min(hi, v)) end

local act_pg = 0
local midi_out = 1
local vel = 5
local vel_human = false
local velocity = {18, 36, 54, 72, 91, 109, 127}
local show_wheels = false

local base_oct = 4
local oct_shift = 0
local oct_up_h, oct_dn_h = false, false
local br_map = {[0]=2, [1]=6, [2]=10, [3]=15}

local sustain_pressed = false
local sustain_latched = false
local sustain_active = false
local last_sustain_time = 0
local sys_t = 0

local pls_v, pls_d = 2, 1

local pb_pos = 5
local pb_vals = {
  [2] = 16383,
  [3] = 9557,
  [4] = 8874,
  [5] = 8192,
  [6] = 7509,
  [7] = 6826,
  [8] = 0
}

local mod_val = 0
local mod_last_sent = 0
local mod_target = nil
local mod_held_y = nil
local mod_press_t = 0
local mod_slewing = false
local mod_hold_thresh = 0.2
local mod_slew_speed = 100
local mod_vals = {
  [2] = 127,
  [3] = 106,
  [4] = 85,
  [5] = 64,
  [6] = 42,
  [7] = 21,
  [8] = 0
}

local root_note = 0
local scale_mode = 1
local my_scale = {}
local notes_in_scale = {}
local held = {}

local SCALES = {
  { name = "CHRM", intervals = { 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 } },
  { name = "ION",  intervals = { 2, 2, 1, 2, 2, 2, 1 } },
  { name = "AEOL", intervals = { 2, 1, 2, 2, 1, 2, 2 } },
  { name = "DOR",  intervals = { 2, 1, 2, 2, 2, 1, 2 } },
  { name = "PHRY", intervals = { 1, 2, 2, 2, 1, 2, 2 } },
  { name = "LYD",  intervals = { 2, 2, 2, 1, 2, 2, 1 } },
  { name = "MIXO", intervals = { 2, 2, 1, 2, 2, 1, 2 } },
  { name = "LOCR", intervals = { 1, 2, 2, 1, 2, 2, 2 } },
  { name = "HMIN", intervals = { 2, 1, 2, 2, 1, 3, 1 } },
  { name = "MMIN", intervals = { 2, 1, 2, 2, 2, 2, 1 } },
  { name = "MAJP", intervals = { 2, 2, 3, 2, 3 } },
  { name = "MINP", intervals = { 3, 2, 2, 3, 2 } },
  { name = "BLUE", intervals = { 3, 2, 1, 1, 3, 2 } },
  { name = "WHOL", intervals = { 2, 2, 2, 2, 2, 2 } },
  { name = "DIM",  intervals = { 2, 1, 2, 1, 2, 1, 2, 1 } },
  { name = "AUG",  intervals = { 3, 1, 3, 1, 3, 1 } }
}

local BLACK_KEYS = {
  [1] = true, [3] = true, [6] = true, [8] = true, [10] = true
}

local ROOT_UI = {
  [0] = {x=1, y=3}, [1] = {x=2, y=2}, [2] = {x=2, y=3}, [3] = {x=3, y=2},
  [4] = {x=3, y=3}, [5] = {x=4, y=3}, [6] = {x=5, y=2}, [7] = {x=5, y=3},
  [8] = {x=6, y=2}, [9] = {x=6, y=3}, [10]= {x=7, y=2}, [11]= {x=7, y=3}
}

local font = {
  [48]="011101101101110", [49]="010110010010111", [50]="110001111100111", [51]="110001111001111", [52]="101101111001001",
  [53]="111100111001110", [54]="011100111101111", [55]="111001010010010", [56]="011101111101110", [57]="111101111001110",
  [65]="011101111101101", [66]="110101110101110", [67]="011101100101110", [68]="110101101101110", [69]="111100110100111",
  [70]="111100111100100", [71]="011100101101111", [72]="101101111101101", [73]="111010010010111", [74]="001001001101010",
  [76]="100100100100111", [77]="101111101101101", [78]="110101101101101", [79]="011101101101110", [80]="011101111100100",
  [82]="011101110101101", [85]="101101101101011", [87]="101101101111101", [88]="101101010101101", [89]="101101111001110"
}

local ch_strs = {[-1]="OFF", [0]="ALL"}
for i = 1, 16 do ch_strs[i] = tostring(i) end

local grid_dirty = true
local function redraw() grid_dirty = true end

local function draw_text(str, st_x, st_y)
  for c = 1, #str do
    local p = font[string.byte(str, c)]
    if p then
      for i = 1, 15 do
        if string.byte(p, i) == 49 then
          grid_led(st_x + (c - 1) * 4 + ((i - 1) % 3), st_y + flr((i - 1) / 3), 10)
        end
      end
    end
  end
end

local function draw_inc_b(c)
  grid_led(c, 4, 12); grid_led(c, 5, 6)
  grid_led(c, 7, 12); grid_led(c, 8, 6)
end

local function tx_midi(n, v, on)
  if midi_out == -1 then return end
  if midi_out == 0 then
    for c = 1, 16 do
      if on then midi_note_on(n, v, c) else midi_note_off(n, v, c) end
    end
  else
    if on then midi_note_on(n, v, midi_out) else midi_note_off(n, v, midi_out) end
  end
end

local function tx_cc(cc, val)
  if midi_out == -1 then return end
  if midi_out == 0 then
    for c = 1, 16 do midi_cc(cc, val, c) end
  else
    midi_cc(cc, val, midi_out)
  end
end

local function tx_pitchbend(val)
  if midi_out == -1 then return end
  local lsb = val & 0x7F
  local msb = (val >> 7) & 0x7F
  if midi_out == 0 then
    for c = 1, 16 do
      if _G.midi_tx then _G.midi_tx(0xE0 + (c - 1), lsb, msb) end
    end
  else
    if _G.midi_tx then _G.midi_tx(0xE0 + (midi_out - 1), lsb, msb) end
  end
end

local function build_scale()
  my_scale = {}
  notes_in_scale = {}
  for i = 0, 11 do notes_in_scale[i] = false end

  local intervals = SCALES[scale_mode].intervals
  local current_note = root_note
  table.insert(my_scale, current_note)
  notes_in_scale[current_note % 12] = true

  local i = 1
  while current_note < 127 do
    current_note = current_note + intervals[i]
    if current_note <= 127 then
      table.insert(my_scale, current_note)
      notes_in_scale[current_note % 12] = true
    end
    i = (i % #intervals) + 1
  end
end

build_scale()

local function note(x, y)
  local scale_length = #SCALES[scale_mode].intervals
  local cur_oct = clamp(base_oct + oct_shift, 0, 8)
  local x_start = show_wheels and 3 or 1
  local note_index = (x - x_start + 1) + 3 * (y - 1) + (cur_oct * scale_length)
  if note_index >= 1 and note_index <= #my_scale then
    return my_scale[note_index]
  end
  return nil
end

function event_grid(x, y, z)
  if z == 0 then
    local k = x + y * 16
    if held[k] then
      tx_midi(held[k], 0, false)
      held[k] = nil
      redraw()
    end
    if x == 2 and y == mod_held_y then
      if not mod_slewing and mod_target ~= nil then
        mod_val = mod_target
        local cc_v = flr(mod_val + 0.5)
        if cc_v ~= mod_last_sent then
          mod_last_sent = cc_v
          tx_cc(1, cc_v)
        end
        redraw()
      end
      mod_held_y = nil
      mod_target = nil
      mod_slewing = false
    end
  end

  if y == 1 then
    if x == 1 then
      if z == 1 then
        if (sys_t - last_sustain_time) < 0.3 then
          sustain_latched = not sustain_latched
          sustain_pressed = false
        else
          if sustain_latched then
            sustain_latched = false
            sustain_pressed = true
          else
            sustain_pressed = true
          end
        end
        last_sustain_time = sys_t
      else
        sustain_pressed = false
      end

      local is_sustain = (sustain_pressed or sustain_latched)
      if is_sustain ~= sustain_active then
        sustain_active = is_sustain
        tx_cc(64, sustain_active and 127 or 0)
      end
      redraw()

    elseif x == 3 then
      oct_dn_h = (z == 1)
      if z == 1 then
        oct_shift = oct_up_h and 0 or max(-3, oct_shift - 1)
        redraw()
      end

    elseif x == 4 then
      oct_up_h = (z == 1)
      if z == 1 then
        oct_shift = oct_dn_h and 0 or min(3, oct_shift + 1)
        redraw()
      end

    elseif x >= 6 and x <= 12 and z == 1 then
      local nv = x - 5
      if vel == nv then
        vel_human = not vel_human
      else
        vel = nv
        vel_human = false
      end
      redraw()

    elseif z == 1 then
      if x == 14 then
        show_wheels = not show_wheels
        if not show_wheels then
          if pb_pos ~= 5 then pb_pos = 5; tx_pitchbend(pb_vals[5]) end
          mod_held_y, mod_target, mod_slewing = nil, nil, false
        end
        redraw()
      elseif x == 15 then
        act_pg = (act_pg == 2) and 0 or 2
        redraw()
      elseif x == 16 then
        act_pg = (act_pg == 1) and 0 or 1
        redraw()
      end
    end
    return
  end

  if act_pg == 1 then
    if z == 1 and (y == 2 or y == 3) then
      if x >= 9 and x <= 16 then
        scale_mode = (y == 2) and (x - 8) or x
        build_scale()
        redraw()
      else
        for i = 0, 11 do
          if ROOT_UI[i].x == x and ROOT_UI[i].y == y then
            root_note = i
            build_scale()
            redraw()
            break
          end
        end
      end
    end
    return
  end

  if act_pg == 2 then
    if z == 1 and x == 13 then
      local d = (y == 4 and 1) or (y == 5 and -1) or (y == 7 and 5) or (y == 8 and -5)
      if d then
        midi_out = clamp(midi_out + d, -1, 16)
        redraw()
      end
    end
    return
  end

  if show_wheels and x == 1 then
    if z == 1 then
      pb_pos = y
      tx_pitchbend(pb_vals[pb_pos])
      redraw()
    elseif y == pb_pos then
      pb_pos = 5
      tx_pitchbend(pb_vals[5])
      redraw()
    end

  elseif show_wheels and x == 2 then
    if z == 1 then
      mod_held_y = y
      mod_target = mod_vals[y]
      mod_press_t = sys_t
      mod_slewing = false
    end

  else
    if z > 0 then
      local n = note(x, 9 - y)
      if n ~= nil then
        local k = x + y * 16
        local v = velocity[vel]
        if vel_human then v = clamp(v + rnd(-5, 5), 1, 127) end
        tx_midi(n, v, true)
        held[k] = n
        redraw()
      end
    end
  end
end

local function hw_redraw()
  grid_led_all(0)

  grid_led(1, 1, sustain_active and 15 or 4)
  grid_led(3, 1, (oct_shift < 0) and br_map[math.abs(oct_shift)] or 2)
  grid_led(4, 1, (oct_shift > 0) and br_map[oct_shift] or 2)

  for i = 1, 7 do
    local dim_val = i + 1
    local br = (vel == i) and (vel_human and pls_v or 15) or dim_val
    grid_led(5 + i, 1, br)
  end

  grid_led(14, 1, show_wheels and 15 or 4)
  grid_led(15, 1, act_pg == 2 and 15 or 4)
  grid_led(16, 1, act_pg == 1 and 15 or 4)

  if act_pg == 1 then
    for i = 0, 11 do
      local pos = ROOT_UI[i]
      local br = 1
      if root_note == i then br = 15
      elseif notes_in_scale[i] then br = 5 end
      grid_led(pos.x, pos.y, br)
    end

    for i = 1, #SCALES do
      local sx = ((i - 1) % 8) + 9
      local sy = (i <= 8) and 2 or 3
      grid_led(sx, sy, scale_mode == i and 15 or 4)
    end

    draw_text(SCALES[scale_mode].name, 1, 4)

  elseif act_pg == 2 then
    draw_inc_b(13)
    draw_text(ch_strs[midi_out], 1, 4)

  else
    if show_wheels then
      for y = 2, 8 do
        local br = (y == 5) and 4 or 1
        if y == pb_pos then br = 15 end
        grid_led(1, y, br)
      end

      local scaled = (mod_val / 127) * 7
      for y = 2, 8 do
        local row_idx = 8 - y
        local fill = clamp(scaled - row_idx, 0, 1)
        local br = flr(1 + fill * 14 + 0.5)
        grid_led(2, y, br)
      end
    end

    local x_start = show_wheels and 3 or 1
    for y = 2, 8 do
      for x = x_start, 16 do
        local n = note(x, 9 - y)
        if n ~= nil then
          local n_mod = n % 12
          if not BLACK_KEYS[n_mod] then
            local is_root = (n_mod == root_note)
            grid_led(x, y, is_root and 12 or 4)
          elseif n_mod == root_note then
            grid_led(x, y, 2)
          end
        end
      end
    end

    for k, _ in pairs(held) do
      grid_led(k % 16, k // 16, 15)
    end
  end

  grid_refresh()
end

local pls_m = metro.init(function()
  pls_v = pls_v + pls_d
  if pls_v >= 10 then pls_d = -1 elseif pls_v <= 2 then pls_d = 1 end
  if vel_human then redraw() end
end, 0.1)
pls_m:start()

local rndr_m = metro.init(function()
  local dt = 1 / 30
  sys_t = sys_t + dt

  if mod_held_y ~= nil and mod_target ~= nil then
    if not mod_slewing and (sys_t - mod_press_t) >= mod_hold_thresh then
      mod_slewing = true
    end

    if mod_slewing then
      local step = mod_slew_speed * dt
      if mod_val < mod_target then
        mod_val = min(mod_target, mod_val + step)
      elseif mod_val > mod_target then
        mod_val = max(mod_target, mod_val - step)
      end

      local cc_v = flr(mod_val + 0.5)
      if cc_v ~= mod_last_sent then
        mod_last_sent = cc_v
        tx_cc(1, cc_v)
      end
      grid_dirty = true

      if mod_val == mod_target then
        mod_target = nil
      end
    end
  end

  if grid_dirty then
    hw_redraw()
    grid_dirty = false
  end
end, 1 / 30)
rndr_m:start()