-- AshSynth v1.3.8 — classic mono synth (norns)
--
-- Encoders
--   E1  page
--   E2  parameter (LFO1/LFO2 pages: scroll destinations incl. FEnv A/D/S/R)
--   E3  adjust
--
-- Keys
--   K2      previous page (hold = fast scroll)
--   K3      next page     (hold = fast scroll)
--   K1 + K2  factory reset (INIT)
--   K1 + K3  random patch  (RAND)
--
-- Pages (10)
--   OSC1 · OSC2 · MIX · FILTER · FENV · AENV · LFO1 · LFO2 · DELAY · REVERB
--
-- MIDI / grid
--   MIDI in (PARAMETERS > input), pitch bend, velocity
--   Program Change on ch 5 → preset ashsynth-NN.pset
--   Grid 5×8 keyboard (optional; TouchOSC via toga)

local MusicUtil = require "musicutil"
local Ash = include("lib/ash_engine")
if not Ash or not Ash.add_params then
  Ash = include("ashsynth/lib/ash_engine")
end

engine.name = "Ash"

local SCREEN_FRAMERATE = 15
local screen_refresh_metro

local midi_in_device
local grid_device
local grid = util.file_exists(_path.code.."toga") and include "toga/lib/togagrid" or grid

local page_index = 1
local param_index = 1
local page_param_index = {}

-- layout (128x64) — label / bar / value share one baseline per row
local LBL_X = 2
local LBL_W = 22
local BAR_X = 39
local BAR_W = 52
local ENV_W = BAR_W
local NOTE_LED_X = 19
local NOTE_LED_Y = 5  
local BAR_H = 3
local RATE_LED_X = 34  -- between "Rate" label and level bar
local RATE_LED_SIZE = 2
local ROW_H = 10
local HEADER_LINE_Y = 12
local TOP_Y = 21
local ENV_H = 22
local ENV_ROW_GAP = 6
local VAL_X = 127
local alt = false
local flash_text = nil
local flash_until = 0
local FLASH_BOX_X = 76
local FLASH_BOX_Y = 2
local FLASH_BOX_W = 44
local FLASH_BOX_H = 7
local FLASH_TEXT_X = 88  -- 글자 왼쪽 (screen.move x)
local FLASH_TEXT_Y = 8   -- 글자 기준선 (font_size 8 → 대략 박스 세로 중앙)

local function flash_status(msg, secs)
  flash_text = msg
  flash_until = util.time() + (secs or 1.2)
end

local function draw_flash_banner()
  if not flash_text or util.time() >= flash_until then return end
  screen.level(15)
  screen.rect(FLASH_BOX_X, FLASH_BOX_Y, FLASH_BOX_W, FLASH_BOX_H)
  screen.fill()
  screen.level(0)
  screen.move(FLASH_TEXT_X, FLASH_TEXT_Y)
  screen.text(flash_text)
end
local active_note = nil
local held_notes = {}
local delay_sync_clock_id = nil
local page_repeat_clock_id = nil
local page_repeat_dir = 0
local PAGE_REPEAT_DELAY = 0.4
local PAGE_REPEAT_INTERVAL = 0.12

local function any_note_held()
  return next(held_notes) ~= nil
end

local PRESET_DIR = "ashsynth"
local PRESET_PREFIX = "ashsynth-"

local lfo_dest_ids = {
  "lfo_amp_amount",
  "lfo_osc_amount", "lfo_filter_amount",
  "lfo_filter_env_attack_amount", "lfo_filter_env_decay_amount", "lfo_filter_env_sustain_amount", "lfo_filter_env_release_amount",
  "lfo_pw_amount", "lfo_detune1_amount", "lfo_detune2_amount",
  "lfo_noise_amount", "lfo_fm_amount", "lfo_glide_amount",
  "lfo_delay_amount", "lfo_reverb_amount", "lfo_drive_amount",
}
local lfo_dest_labels = {
  lfo_osc_amount = "Pitch", lfo_filter_amount = "Filter", lfo_amp_amount = "Amp",
  lfo_filter_env_attack_amount = "FEnv A",
  lfo_filter_env_decay_amount = "FEnv D",
  lfo_filter_env_sustain_amount = "FEnv S",
  lfo_filter_env_release_amount = "FEnv R",
  lfo_pw_amount = "PW", lfo_detune1_amount = "Detune1", lfo_detune2_amount = "Detune2",
  lfo_noise_amount = "Noise", lfo_fm_amount = "FM", lfo_glide_amount = "Glide",
  lfo_delay_amount = "Delay", lfo_reverb_amount = "Reverb", lfo_drive_amount = "Drive",
}
-- LFO2: same modulation targets as LFO1; page title + independent rate/shape/master distinguish them.
local lfo2_dest_ids = {}
for _, id in ipairs(lfo_dest_ids) do
  local id2 = "lfo2_" .. string.sub(id, 5)
  lfo2_dest_ids[#lfo2_dest_ids + 1] = id2
  lfo_dest_labels[id2] = lfo_dest_labels[id]
end

local function build_lfo_page(prefix, dest_ids)
  local page = {prefix .. "rate", prefix .. "shape", prefix .. "master"}
  for _, id in ipairs(dest_ids) do page[#page + 1] = id end
  return page
end

local lfo_page = build_lfo_page("lfo_", lfo_dest_ids)
local lfo2_page = build_lfo_page("lfo2_", lfo2_dest_ids)

-- Per-page param order (E2 cycles)
local page_params = {
  {"osc1_wave", "osc1_level", "osc1_detune", "osc1_pitch", "osc1_octave", "osc1_pw"},
  {"osc2_wave", "osc2_level", "osc2_detune", "osc2_pitch", "osc2_octave", "osc2_pw"},
  {"noise_level", "fm_amount", "glide", "glide_mode"},
  {"lp_cutoff", "lp_resonance", "lp_env_amount", "lp_tracking"},
  {"filter_attack", "filter_decay", "filter_sustain", "filter_release", "filter_env_link_amp"},
  {"amp_attack", "amp_decay", "amp_sustain", "amp_release", "drive"},
  lfo_page,
  lfo2_page,
  {"delay_mix", "delay_time", "delay_feedback", "delay_sync", "delay_division", "delay_filter"},
  {"reverb_mix", "reverb_room", "reverb_damp"},
}

local page_names = {"OSC1", "OSC2", "MIX", "FILTER", "FILTER ENV", "AMP ENV", "LFO1", "LFO2", "DELAY", "REVERB"}
local NUM_PAGES = #page_names

local LFO_PAGE = 7
local LFO2_PAGE = 8
local LFO_VISIBLE_DEST = 4
local LFO_SCROLL_X = 100
local lfo_scroll = { [LFO_PAGE] = 0, [LFO2_PAGE] = 0 }

local builtin_cc = {
  [1] = "lp_env_amount", [7] = "drive", [71] = "lp_resonance", [74] = "lp_cutoff",
}

local assign_cc_options = {
  "none",
  "osc1_level", "osc2_level", "osc1_pitch", "osc2_pitch", "osc1_octave", "osc2_octave",
  "noise_level", "fm_amount", "glide", "lp_cutoff", "lp_resonance", "lp_env_amount",
  "filter_attack", "filter_decay", "amp_attack", "amp_decay",
  "lfo_rate", "lfo_master", "lfo_osc_amount", "lfo_filter_amount", "lfo_amp_amount",
  "lfo_filter_env_attack_amount", "lfo_filter_env_decay_amount", "lfo_filter_env_sustain_amount", "lfo_filter_env_release_amount",
  "lfo_pw_amount", "lfo_detune1_amount", "lfo_detune2_amount", "lfo_noise_amount", "lfo_fm_amount", "lfo_glide_amount",
  "lfo_delay_amount", "lfo_reverb_amount", "lfo_drive_amount",
  "lfo2_rate", "lfo2_master", "lfo2_osc_amount", "lfo2_filter_amount", "lfo2_amp_amount",
  "lfo2_filter_env_attack_amount", "lfo2_filter_env_decay_amount", "lfo2_filter_env_sustain_amount", "lfo2_filter_env_release_amount",
  "lfo2_pw_amount", "lfo2_detune1_amount", "lfo2_detune2_amount", "lfo2_noise_amount", "lfo2_fm_amount", "lfo2_glide_amount",
  "lfo2_delay_amount", "lfo2_reverb_amount", "lfo2_drive_amount",
  "delay_mix", "delay_feedback", "reverb_mix", "drive",
}

local function clamp_index(i, lo, hi)
  if i < lo then return lo end
  if i > hi then return hi end
  return i
end

local function current_param_ids()
  return page_params[page_index] or {}
end

local function page_param_count(pg)
  local ids = page_params[pg]
  return ids and #ids or 1
end

local function selected_param_id()
  local ids = current_param_ids()
  return ids[param_index]
end

local function remember_page_param_index()
  page_param_index[page_index] = param_index
end

local function restore_page_param_index(pg)
  local saved = page_param_index[pg] or 1
  param_index = clamp_index(saved, 1, page_param_count(pg))
end

local function current_lfo_dest_ids()
  if page_index == LFO2_PAGE then return lfo2_dest_ids end
  if page_index == LFO_PAGE then return lfo_dest_ids end
  return nil
end

local function get_lfo_scroll()
  return lfo_scroll[page_index] or 0
end

local function set_lfo_scroll(v)
  if lfo_scroll[page_index] ~= nil then lfo_scroll[page_index] = v end
end

local function lfo_dest_scroll_max(dest_ids)
  dest_ids = dest_ids or current_lfo_dest_ids() or lfo_dest_ids
  return math.max(0, #dest_ids - LFO_VISIBLE_DEST)
end

local function enc_step(delta)
  if delta > 0 then return 1 end
  if delta < 0 then return -1 end
  return 0
end

local function update_lfo_scroll()
  local dest_ids = current_lfo_dest_ids()
  if not dest_ids then return end
  local pid = selected_param_id()
  if not pid then return end
  local scroll = get_lfo_scroll()
  for i, id in ipairs(dest_ids) do
    if id == pid then
      local dest_i = i - 1
      if dest_i < scroll then
        scroll = dest_i
      elseif dest_i >= scroll + LFO_VISIBLE_DEST then
        scroll = dest_i - LFO_VISIBLE_DEST + 1
      end
      set_lfo_scroll(scroll)
      return
    end
  end
end

local option_param_lists = {
  osc1_wave = function() return Ash.options.WAVE end,
  osc2_wave = function() return Ash.options.WAVE end,
  lfo_shape = function() return Ash.options.LFO_SHAPE end,
  lfo2_shape = function() return Ash.options.LFO_SHAPE end,
  delay_sync = function() return Ash.options.DELAY_SYNC end,
  delay_division = function() return Ash.options.DELAY_DIV end,
  glide_mode = function() return Ash.options.GLIDE_MODE end,
  filter_env_link_amp = function() return Ash.options.ENV_LINK end,
}

local function param_norm(pid)
  local list_fn = option_param_lists[pid]
  if list_fn then
    local opts = list_fn()
    local n = #opts
    return n > 1 and (params:get(pid) - 1) / (n - 1) or 0
  end
  local idx = params.lookup and params.lookup[pid]
  if idx then
    local p = params:lookup_param(idx)
    if p and p.t == 3 and p.options then
      local n = #p.options
      return n > 1 and (params:get(pid) - 1) / (n - 1) or 0
    end
  end
  local ok, lo, hi = pcall(function() return params:get_range(pid) end)
  if ok and lo and hi and hi > lo then
    return util.clamp(util.linlin(lo, hi, 0, 1, params:get(pid)), 0, 1)
  end
  local raw_ok, raw = pcall(function() return params:get_raw(pid) end)
  if raw_ok and raw ~= nil then
    return util.clamp(raw, 0, 1)
  end
  return 0
end

local function row_y(i, step)
  return TOP_Y + i * (step or ROW_H)
end

local function param_val_str(pid)
  if pid == "osc1_wave" then return Ash.options.WAVE[params:get(pid)]
  elseif pid == "osc2_wave" then return Ash.options.WAVE[params:get(pid)]
  elseif pid == "lfo_shape" then return Ash.options.LFO_SHAPE[params:get(pid)]
  elseif pid == "lfo2_shape" then return Ash.options.LFO_SHAPE[params:get(pid)]
  elseif pid == "delay_sync" then return Ash.options.DELAY_SYNC[params:get(pid)]
  elseif pid == "delay_division" then return Ash.options.DELAY_DIV[params:get(pid)]
  elseif pid == "glide_mode" then return Ash.options.GLIDE_MODE[params:get(pid)]
  elseif pid == "filter_env_link_amp" then return Ash.options.ENV_LINK[params:get(pid)]
  elseif pid == "lfo_master" or pid == "lfo2_master" or lfo_dest_labels[pid] then
    return util.round(params:get(pid) * 100) .. "%"
  elseif pid == "osc1_pitch" or pid == "osc2_pitch" then
    local v = util.round(params:get(pid), 0.1)
    if v > 0 then return string.format("+%.1f", v)
    elseif v < 0 then return string.format("%.1f", v) else return "0" end
  end
  local s = params:string(pid) or ""
  if #s > 8 then s = string.sub(s, 1, 8) end
  return s
end

local function draw_val_right(y, str, level)
  screen.level(level or 4)
  if screen.text_right then
    screen.move(VAL_X, y)
    screen.text_right(str)
  else
    screen.move(VAL_X - math.min(44, #str * 5), y)
    screen.text(str)
  end
end

local function is_selected(pid)
  return selected_param_id() == pid
end

local function draw_header()
  screen.font_face(1)
  screen.font_size(8)
  screen.level(3)
  screen.move(LBL_X, 8)
  screen.text("ASH")
  screen.level(15)
  screen.move(24, 8)
  screen.text(page_names[page_index] or "")
  if any_note_held() then
    screen.level(15)
    screen.rect(NOTE_LED_X, NOTE_LED_Y, 2, 2)
    screen.fill()
  end
  for i = 1, NUM_PAGES do
    screen.level(i == page_index and 12 or 1)
    screen.rect(72 + i * 5, 6, 2, 2)
    screen.fill()
  end
  draw_flash_banner()
  screen.level(1)
  screen.move(LBL_X, HEADER_LINE_Y)
  screen.line(127, HEADER_LINE_Y)
  screen.stroke()
end

local function env_depth_y()
  return TOP_Y + ENV_H + ENV_ROW_GAP
end

-- one row: label + bar (same vertical band) + value on baseline
local function draw_hrow(baseline_y, norm, sel, label, val)
  norm = util.clamp(norm, 0, 1)
  local bar_y = baseline_y - BAR_H - 1
  screen.level(sel and 15 or 3)
  screen.move(LBL_X, baseline_y)
  screen.text(label)
  screen.level(1)
  screen.rect(BAR_X, bar_y, BAR_W, BAR_H)
  screen.stroke()
  local fw = util.round(BAR_W * norm)
  if fw > 0 then
    screen.level(sel and 15 or 7)
    screen.rect(BAR_X, bar_y, fw, BAR_H)
    screen.fill()
  end
  draw_val_right(baseline_y, val, sel and 15 or 4)
end

local function osc_wave_amp(t, idx, pw)
  local p = t % 1
  if idx == 1 then return math.sin(p * math.pi * 2)
  elseif idx == 2 then return 2 * p - 1
  else
    local duty = 0.1 + (pw or 0.5) * 0.8
    return p < duty and 1 or -1
  end
end

local function lfo_wave_amp(t, idx)
  local p = t % 1
  if idx == 1 then
    return math.sin(p * math.pi * 2)
  elseif idx == 2 then
    if p < 0.5 then return 4 * p - 1 else return 3 - 4 * p end
  elseif idx == 3 then
    return 2 * p - 1
  elseif idx == 4 then
    return p < 0.5 and 1 or -1
  else
    local steps = 8
    local si = math.min(steps - 1, math.floor(p * steps))
    return ((si * 1103515245 + 12345) % 65536) / 32768 - 1
  end
end

-- LFO page: ramp blink between "Rate" label and bar (phase = rate Hz, shape from lfo_shape)
local function draw_lfo_rate_led(baseline_y, sel, rate_pid, shape_pid)
  local rate = params:get(rate_pid)
  if not rate or rate <= 0 then return end
  local phase = (util.time() * rate) % 1
  local amp = lfo_wave_amp(phase, params:get(shape_pid) or 1)
  local level = util.round(util.clamp(amp * 0.5 + 0.5, 0, 1) * (sel and 15 or 11))
  if level < 1 then return end
  local bar_y = baseline_y - BAR_H - 1
  local led_y = bar_y + math.max(0, math.floor((BAR_H - RATE_LED_SIZE) * 0.5))
  screen.level(level)
  screen.rect(RATE_LED_X, led_y, RATE_LED_SIZE, RATE_LED_SIZE)
  screen.fill()
end

local function draw_wave_preview(x, y, w, h, shape_idx, pw, sel, kind)
  screen.level(sel and 12 or 5)
  local mid = y + h / 2
  local started = false
  for px = 0, w - 1 do
    local t = (px + 0.5) / w
    local amp = kind == "lfo" and lfo_wave_amp(t, shape_idx) or osc_wave_amp(t, shape_idx, pw)
    local py = util.clamp(math.floor(mid - amp * (h * 0.4) + 0.5), y, y + h - 1)
    local cx = x + px
    if not started then
      screen.move(cx, py)
      started = true
    else
      screen.line(cx, py)
    end
  end
  if started then screen.stroke() end
end

local function draw_wave_row(baseline_y, wave_id, wave_idx, pw, val)
  local sel = is_selected(wave_id)
  local pw_w, pw_h = 22, 8
  local preview_y = baseline_y - pw_h - 2 + 5
  screen.level(sel and 15 or 3)
  screen.move(LBL_X, baseline_y)
  screen.text("Wave")
  draw_wave_preview(BAR_X, preview_y, pw_w, pw_h, wave_idx, pw, sel, "osc")
  draw_val_right(baseline_y, val, sel and 15 or 4)
end

local env_seg_short = {
  attack = "Attack", decay = "Decay", sustain = "Sustain", release = "Release",
}

local function draw_env_sel_readout(y, h, prefix, sel_pid)
  local seg
  for _, name in ipairs({"attack", "decay", "sustain", "release"}) do
    if sel_pid == prefix .. name then seg = name; break end
  end
  if not seg then return end

  local pid = prefix .. seg
  local mid = y + math.floor(h / 2)
  screen.font_face(1)
  screen.font_size(8)
  screen.level(15)
  screen.move(LBL_X, mid - 2)
  screen.text(env_seg_short[seg])
  draw_val_right(mid + 6, param_val_str(pid), 15)
end

local function draw_env_graph(x, y, w, h, prefix, sel_pid)
  local a = params:get(prefix .. "attack")
  local d = params:get(prefix .. "decay")
  local s = params:get(prefix .. "sustain")
  local r = params:get(prefix .. "release")
  local sus = 0.22
  local sum = math.max(a + d + r, 0.05)
  local ta = a / sum
  local td = d / sum
  local tr = r / sum
  local tn = ta + td + tr + sus
  ta, td, tr, sus = ta / tn, td / tn, tr / tn, sus / tn
  local yb = y + h
  local ax = x + ta * w
  local dx = ax + td * w
  local sx = dx + sus * w
  local rx = x + w
  local sy = y + h * (1 - s * 0.9)

  screen.level(1)
  screen.move(x, yb)
  screen.line(ax, y)
  screen.line(dx, sy)
  screen.line(sx, sy)
  screen.line(rx, yb)
  screen.stroke()

  local segs = {
    {"attack", x, yb, ax, y},
    {"decay", ax, y, dx, sy},
    {"sustain", dx, sy, sx, sy},
    {"release", sx, sy, rx, yb},
  }
  for _, seg in ipairs(segs) do
    local on = sel_pid == prefix .. seg[1]
    screen.level(on and 15 or 6)
    screen.move(seg[2], seg[3])
    screen.line(seg[4], seg[5])
    screen.stroke()
  end

  draw_env_sel_readout(y, h, prefix, sel_pid)
end

local function draw_page_osc(prefix)
  local rh = 7
  local wave_id = prefix .. "_wave"
  local level_id = prefix .. "_level"
  local detune_id = prefix .. "_detune"
  draw_wave_row(row_y(0, rh), wave_id, params:get(wave_id), params:get(prefix .. "_pw"), param_val_str(wave_id))
  draw_hrow(row_y(1, rh), param_norm(level_id), is_selected(level_id), "Level", param_val_str(level_id))
  draw_hrow(row_y(2, rh), param_norm(detune_id), is_selected(detune_id), "Detune", param_val_str(detune_id))
  draw_hrow(row_y(3, rh), param_norm(prefix .. "_pitch"), is_selected(prefix .. "_pitch"), "Pitch", param_val_str(prefix .. "_pitch"))
  draw_hrow(row_y(4, rh), param_norm(prefix .. "_octave"), is_selected(prefix .. "_octave"), "Octave", param_val_str(prefix .. "_octave"))
  draw_hrow(row_y(5, rh), param_norm(prefix .. "_pw"), is_selected(prefix .. "_pw"), "PW", param_val_str(prefix .. "_pw"))
end

local function draw_page_mix()
  draw_hrow(row_y(0), param_norm("noise_level"), is_selected("noise_level"), "Noise", param_val_str("noise_level"))
  draw_hrow(row_y(1), param_norm("fm_amount"), is_selected("fm_amount"), "FM", param_val_str("fm_amount"))
  draw_hrow(row_y(2), param_norm("glide"), is_selected("glide"), "Glide", param_val_str("glide"))
  draw_hrow(row_y(3), param_norm("glide_mode"), is_selected("glide_mode"), "G-Mode", param_val_str("glide_mode"))
end

local function draw_page_filt()
  draw_hrow(row_y(0), param_norm("lp_cutoff"), is_selected("lp_cutoff"), "Cutoff", param_val_str("lp_cutoff"))
  draw_hrow(row_y(1), param_norm("lp_resonance"), is_selected("lp_resonance"), "Reso", param_val_str("lp_resonance"))
  draw_hrow(row_y(2), param_norm("lp_env_amount"), is_selected("lp_env_amount"), "Amount", param_val_str("lp_env_amount"))
  draw_hrow(row_y(3), param_norm("lp_tracking"), is_selected("lp_tracking"), "K-Track", param_val_str("lp_tracking"))
end

local function draw_page_fenv()
  draw_env_graph(BAR_X, TOP_Y, ENV_W, ENV_H, "filter_", selected_param_id())
  local link_sel = is_selected("filter_env_link_amp")
  draw_hrow(env_depth_y(), param_norm("filter_env_link_amp"), link_sel, "Link", param_val_str("filter_env_link_amp"))
end

local function draw_page_aenv()
  draw_env_graph(BAR_X, TOP_Y, ENV_W, ENV_H, "amp_", selected_param_id())
  draw_hrow(env_depth_y(), param_norm("drive"), is_selected("drive"), "Drive", param_val_str("drive"))
end

local function draw_lfo_scroll_hint(dest_ids)
  local max_scroll = lfo_dest_scroll_max(dest_ids)
  if max_scroll <= 0 then return end
  local rh = 7
  local scroll = get_lfo_scroll()
  screen.level(6)
  if scroll > 0 then
    screen.move(LFO_SCROLL_X, row_y(3, rh) - 4)
    screen.text("^")
  end
  if scroll < max_scroll then
    screen.move(LFO_SCROLL_X, row_y(2 + LFO_VISIBLE_DEST, rh) + 2)
    screen.text("v")
  end
end

local function draw_page_lfo_bank(rate_pid, shape_pid, master_pid, dest_ids)
  update_lfo_scroll()
  local rh = 7
  local scroll = get_lfo_scroll()
  local rate_y = row_y(0, rh)
  local rate_sel = is_selected(rate_pid)
  draw_hrow(rate_y, param_norm(rate_pid), rate_sel, "Rate", param_val_str(rate_pid))
  draw_lfo_rate_led(rate_y, rate_sel, rate_pid, shape_pid)

  local sy = row_y(1, rh)
  local shape_sel = is_selected(shape_pid)
  local shape_idx = params:get(shape_pid)
  screen.level(shape_sel and 15 or 3)
  screen.move(LBL_X, sy)
  screen.text("Shape")
  local ww, wh = 22, 8
  local wy = sy - wh - 1 + 4
  draw_wave_preview(BAR_X + 4, wy, ww, wh, shape_idx, nil, shape_sel, "lfo")
  draw_val_right(sy, param_val_str(shape_pid), shape_sel and 15 or 4)

  draw_hrow(row_y(2, rh), param_norm(master_pid), is_selected(master_pid), "Mix", param_val_str(master_pid))

  for i = 1, LFO_VISIBLE_DEST do
    local dest_i = scroll + i
    local pid = dest_ids[dest_i]
    if pid then
      draw_hrow(row_y(2 + i, rh), param_norm(pid), is_selected(pid),
        lfo_dest_labels[pid] or pid, param_val_str(pid))
    end
  end
  draw_lfo_scroll_hint(dest_ids)
end

local function draw_page_lfo()
  draw_page_lfo_bank("lfo_rate", "lfo_shape", "lfo_master", lfo_dest_ids)
end

local function draw_page_lfo2()
  draw_page_lfo_bank("lfo2_rate", "lfo2_shape", "lfo2_master", lfo2_dest_ids)
end

local function draw_page_delay()
  local rh = 7
  draw_hrow(row_y(0, rh), param_norm("delay_mix"), is_selected("delay_mix"), "Mix", param_val_str("delay_mix"))
  draw_hrow(row_y(1, rh), param_norm("delay_time"), is_selected("delay_time"), "Time", param_val_str("delay_time"))
  draw_hrow(row_y(2, rh), param_norm("delay_feedback"), is_selected("delay_feedback"), "Fdbk", param_val_str("delay_feedback"))
  draw_hrow(row_y(3, rh), param_norm("delay_sync"), is_selected("delay_sync"), "Sync", param_val_str("delay_sync"))
  draw_hrow(row_y(4, rh), param_norm("delay_division"), is_selected("delay_division"), "Div", param_val_str("delay_division"))
  draw_hrow(row_y(5, rh), param_norm("delay_filter"), is_selected("delay_filter"), "Tone", param_val_str("delay_filter"))
end

local function draw_page_reverb()
  draw_hrow(row_y(0), param_norm("reverb_mix"), is_selected("reverb_mix"), "Mix", param_val_str("reverb_mix"))
  draw_hrow(row_y(1), param_norm("reverb_room"), is_selected("reverb_room"), "Room", param_val_str("reverb_room"))
  draw_hrow(row_y(2), param_norm("reverb_damp"), is_selected("reverb_damp"), "Damp", param_val_str("reverb_damp"))
end

local page_drawers = {
  function() draw_page_osc("osc1") end,
  function() draw_page_osc("osc2") end,
  draw_page_mix,
  draw_page_filt,
  draw_page_fenv,
  draw_page_aenv,
  draw_page_lfo,
  draw_page_lfo2,
  draw_page_delay,
  draw_page_reverb,
}

function redraw()
  screen.clear()
  draw_header()
  local drawer = page_drawers[page_index]
  if drawer then
    local ok, err = pcall(drawer)
    if not ok then
      print("ASH draw error p" .. page_index .. ": " .. tostring(err))
      screen.level(15)
      screen.move(LBL_X, TOP_Y)
      screen.text("draw err")
    end
  end
  screen.update()
  screen.ping()
end

local function cc_to_param(cc)
  if builtin_cc[cc] then return builtin_cc[cc] end
  for i = 1, 4 do
    if params:get("cc_num_" .. i) == cc then
      local n = assign_cc_options[params:get("cc_assign_" .. i)]
      if n ~= "none" then return n end
    end
  end
end

local function set_cc_value(param_id, val)
  local idx = params.lookup and params.lookup[param_id]
  if idx then
    local p = params:lookup_param(idx)
    if p and p.t == 3 and p.options then
      params:set(param_id, util.clamp(util.round(val * #p.options - 0.001) + 1, 1, #p.options))
      return
    end
  end
  local ok, a, b = pcall(function() return params:get_range(param_id) end)
  if ok and a and b then params:set(param_id, util.linlin(0, 1, a, b, val)) end
end

local function held_note_count()
  local n = 0
  for _ in pairs(held_notes) do n = n + 1 end
  return n
end

local function apply_glide_for_note(is_legato)
  if params:get("glide") <= 0 then
    if engine.glideOn then engine.glideOn(0) end
    return
  end
  local on = 1
  if params:get("glide_mode") == 2 then
    on = is_legato and 1 or 0
  end
  if engine.glideOn then engine.glideOn(on) end
end

local function note_on(id, n, vel)
  local legato = held_note_count() > 0
  apply_glide_for_note(legato)
  held_notes[id] = n
  engine.noteOn(id, MusicUtil.note_num_to_freq(n), vel)
  active_note = n
end

local function note_off(id)
  held_notes[id] = nil
  engine.noteOff(id)
  if held_note_count() == 0 then
    active_note = nil
  end
end

local function note_off_all()
  held_notes = {}
  engine.noteOffAll()
  active_note = nil
end

local function grid_led_note(note, vel, on)
  if not grid_device then return end
  local d = note - 40
  if d < 0 or d > 39 then return end
  grid_device:led((d % 5) + 1, 8 - math.floor(d / 5), on and 12 or 0)
  grid_device:refresh()
end

function load_preset(num)
  local n = string.format("%02d", num)
  local candidates = {
    _path.data .. PRESET_DIR .. "/" .. PRESET_PREFIX .. n .. ".pset",
    _path.data .. "ash/ash-" .. n .. ".pset",
    _path.data .. "ash_synth/ash_synth-" .. n .. ".pset",
    _path.data .. "asynth/asynth-" .. n .. ".pset",
  }
  local path
  for _, p in ipairs(candidates) do
    if util.file_exists(p) then
      path = p
      break
    end
  end
  if path then
    params:read(path)
    params:bang()
    Ash.push_engine_state()
    print("불러온 프리셋: " .. path)
  else
    print("프리셋 없음: " .. PRESET_DIR .. "/" .. PRESET_PREFIX .. n .. ".pset")
  end
end

local function midi_event(data)
  local msg = midi.to_msg(data)
  if msg.type == "program_change" and msg.ch == 5 then
    load_preset(msg.val + 1)
    return
  end
  local ch = params:get("midi_channel")
  if not (ch == 1 or (ch > 1 and msg.ch == ch - 1)) then return end
  if msg.type == "note_on" and msg.vel > 0 then
    note_on(msg.note, msg.note, msg.vel / 127)
    grid_led_note(msg.note, msg.vel, true)
  elseif msg.type == "note_off" or (msg.type == "note_on" and msg.vel == 0) then
    note_off(msg.note)
    grid_led_note(msg.note, 0, false)
  elseif msg.type == "pitchbend" then
    engine.pitchBend(MusicUtil.interval_to_ratio(((util.round(msg.val / 2)) / 8192 * 2 - 1) * params:get("bend_range")))
  elseif msg.type == "cc" then
    local pid = cc_to_param(msg.cc)
    if pid then set_cc_value(pid, msg.val / 127) end
  end
end

local function grid_key(x, y, z)
  if not grid_device then return end
  local note = ((8 - y) * 5) + x + 40
  if z == 1 then note_on(note, note, 0.85); grid_device:led(x, y, 15)
  else note_off(note); grid_device:led(x, y, 0) end
  grid_device:refresh()
end

local function update_delay_actions()
  params:set_action("delay_time", function(v)
    if params:get("delay_sync") == 1 then engine.delayTime(v) end
  end)
  params:set_action("delay_division", function() Ash.apply_delay_time() end)
  params:set_action("delay_sync", function() Ash.apply_delay_time() end)
end

function init()
  if not Ash or not Ash.add_params then
    print("ASH: engine lib missing")
    return
  end

  screen.aa(0)
  page_index = 1
  param_index = 1
  lfo_scroll = { [LFO_PAGE] = 0, [LFO2_PAGE] = 0 }
  page_param_index = {}
  for i = 1, NUM_PAGES do
    page_param_index[i] = 1
  end

  params:add_separator("input")
  params:add{type = "number", id = "midi_device", name = "MIDI Device", min = 1, max = 4, default = 1,
    action = function(v)
      midi_in_device.event = nil
      midi_in_device = midi.connect(v)
      midi_in_device.event = midi_event
    end}
  local channels = {"All"}
  for i = 1, 16 do table.insert(channels, i) end
  params:add{type = "option", id = "midi_channel", name = "MIDI Channel", options = channels, default = 1}
  params:add{type = "number", id = "bend_range", name = "Pitch Bend Range", min = 1, max = 48, default = 2}
  params:add{type = "number", id = "grid_device", name = "Grid Device", min = 1, max = 4, default = 1,
    action = function(v)
      if grid_device then grid_device:all(0); grid_device:refresh(); grid_device.key = nil end
      grid_device = grid.connect(v)
      if grid_device then grid_device.key = grid_key end
    end}
  params:add_separator("midi cc assign")
  for i = 1, 4 do
    params:add{type = "number", id = "cc_num_" .. i, name = "CC #" .. i, min = 0, max = 127, default = 10 + i}
    params:add{type = "option", id = "cc_assign_" .. i, name = "CC " .. i .. " dest", options = assign_cc_options, default = 1}
  end

  Ash.add_params()
  update_delay_actions()

  midi_in_device = midi.connect(1)
  midi_in_device.event = midi_event
  local g = grid.connect(1)
  if g then grid_device = g; grid_device.key = grid_key end

  screen_refresh_metro = metro.init()
  screen_refresh_metro.time = 1 / SCREEN_FRAMERATE
  screen_refresh_metro.event = function() redraw() end
  screen_refresh_metro:start()

  params:bang()
  clock.run(function()
    for _ = 1, 50 do
      if engine and engine.osc1Wave then break end
      clock.sleep(0.1)
    end
    Ash.boot_synth()
  end)
  delay_sync_clock_id = clock.run(function()
    while true do
      clock.sync(1 / 4)
      if params:get("delay_sync") == 2 then Ash.apply_delay_time() end
    end
  end)

  redraw()
end

local function change_page(delta)
  local step = enc_step(delta)
  if step == 0 then return end
  remember_page_param_index()
  page_index = clamp_index(page_index + step, 1, NUM_PAGES)
  restore_page_param_index(page_index)
end

local function stop_page_repeat()
  page_repeat_dir = 0
  if page_repeat_clock_id then
    clock.cancel(page_repeat_clock_id)
    page_repeat_clock_id = nil
  end
end

local function start_page_repeat(dir)
  stop_page_repeat()
  page_repeat_dir = dir
  change_page(dir)
  redraw()
  page_repeat_clock_id = clock.run(function()
    clock.sleep(PAGE_REPEAT_DELAY)
    while page_repeat_dir == dir do
      change_page(dir)
      redraw()
      clock.sleep(PAGE_REPEAT_INTERVAL)
    end
  end)
end

function enc(n, delta)
  if n == 1 then
    change_page(delta)
  elseif n == 2 then
    local step = enc_step(delta)
    if step ~= 0 then
      local ids = current_param_ids()
      if #ids > 0 then
        param_index = clamp_index(param_index + step, 1, #ids)
        page_param_index[page_index] = param_index
        if page_index == LFO_PAGE or page_index == LFO2_PAGE then update_lfo_scroll() end
      end
    end
  elseif n == 3 then
    local pid = selected_param_id()
    if pid then
      if pid == "osc1_pitch" or pid == "osc2_pitch" then
        params:set(pid, util.clamp(util.round(params:get(pid) + delta * 0.1, 0.1), -12, 12))
      else
        params:delta(pid, delta)
      end
    end
  end
  redraw()
end

function key(n, z)
  if n == 1 then
    alt = (z == 1)
    if z == 0 then stop_page_repeat() end
    return
  end
  if n == 2 then
    if z == 1 then
      if alt then
        stop_page_repeat()
        Ash.reset_defaults()
        flash_status("INIT")
      else
        start_page_repeat(-1)
      end
    else
      stop_page_repeat()
      if alt then
        Ash.reset_defaults()
        flash_status("INIT")
      end
    end
    redraw()
    return
  end
  if n == 3 then
    if z == 1 then
      if alt then
        stop_page_repeat()
        Ash.randomize()
        Ash.apply_delay_time()
        flash_status("RAND")
      else
        start_page_repeat(1)
      end
    else
      stop_page_repeat()
    end
    redraw()
    return
  end
end

function refresh()
  redraw()
end

function cleanup()
  held_notes = {}
  active_note = nil
  stop_page_repeat()
  if delay_sync_clock_id then
    clock.cancel(delay_sync_clock_id)
    delay_sync_clock_id = nil
  end
  if midi_in_device then midi_in_device.event = nil end
  if engine and engine.noteKillAll then pcall(function() engine.noteKillAll() end) end
  if engine and engine.noteOffAll then pcall(function() engine.noteOffAll() end) end
  if grid_device then
    pcall(function()
      grid_device:all(0)
      grid_device:refresh()
      grid_device.key = nil
    end)
  end
  if screen_refresh_metro then
    screen_refresh_metro:stop()
    screen_refresh_metro = nil
  end
end
