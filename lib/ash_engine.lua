--- ASH engine lib
-- @module AshEngine
-- @release v1.0.2

local ControlSpec = require "controlspec"
local Formatters = require "formatters"

local Ash = {}

local specs = {}
local options = {}

options.WAVE = {"Sine", "Saw", "Pulse"}
options.LFO_SHAPE = {"Sine", "Triangle", "Saw", "Square", "Random"}
options.DELAY_SYNC = {"Free", "Clock"}
options.GLIDE_MODE = {"All", "Legato"}
options.ENV_LINK = {"off", "on"}
-- 4/4: 1/N note length = 4/N beats (T ×2/3, D ×1.5)
local function div_beats(denom)
  return 4 / denom
end

options.DELAY_DIV = {
  "1/32", "1/24", "1/16", "1/16T", "1/16D",
  "1/12", "1/8", "1/8T", "1/8D",
  "1/6", "1/4", "1/4T", "1/4D",
  "1/3", "1/2", "1/2T", "1/2D",
  "1 bar", "2 bar",
}
Ash.DELAY_DIV_BEATS = {
  div_beats(32), div_beats(24), div_beats(16), div_beats(16) * 2/3, div_beats(16) * 1.5,
  div_beats(12), div_beats(8), div_beats(8) * 2/3, div_beats(8) * 1.5,
  div_beats(6), div_beats(4), div_beats(4) * 2/3, div_beats(4) * 1.5,
  div_beats(3), div_beats(2), div_beats(2) * 2/3, div_beats(2) * 1.5,
  4, 8,
}

specs.GLIDE = ControlSpec.new(0, 3, "lin", 0, 0, "s")
specs.OSC_LEVEL = ControlSpec.new(0, 1, "lin", 0, 0.5, "")
specs.PW = ControlSpec.new(0, 1, "lin", 0, 0.5, "")
specs.PITCH = ControlSpec.new(-12, 12, "lin", 0.1, 0, "st")
specs.OCTAVE = ControlSpec.new(-2, 2, "lin", 1, 0, "oct")
specs.DETUNE = ControlSpec.new(0, 50, "lin", 0, 0, "ct")
specs.NOISE = ControlSpec.UNIPOLAR
specs.FM_AMOUNT = ControlSpec.UNIPOLAR

specs.LP_CUTOFF = ControlSpec.new(40, 16000, "exp", 0, 800, "Hz")
specs.LP_RES = ControlSpec.new(0, 1, "lin", 0, 0.15, "")
specs.LP_ENV_AMT = ControlSpec.new(0, 1, "lin", 0, 0.45, "")
specs.LP_TRACK = ControlSpec.new(0, 2, "lin", 0, 1, ":1")

specs.ENV_A = ControlSpec.new(0.001, 5, "exp", 0, 0.01, "s")
specs.ENV_D = ControlSpec.new(0.001, 8, "exp", 0, 0.25, "s")
specs.ENV_S = ControlSpec.new(0, 1, "lin", 0, 0.5, "")
specs.ENV_R = ControlSpec.new(0.001, 12, "exp", 0, 0.4, "s")

specs.LFO_RATE = ControlSpec.new(0.02, 20, "exp", 0, 1, "Hz")
specs.LFO_AMT = ControlSpec.UNIPOLAR
specs.LFO_MASTER = ControlSpec.new(0, 1, "lin", 0, 1, "")
specs.DRIVE = ControlSpec.UNIPOLAR

specs.DELAY_TIME = ControlSpec.new(0.01, 2, "exp", 0, 0.375, "s")
specs.DELAY_FB = ControlSpec.new(0, 0.95, "lin", 0, 0.45, "")
specs.DELAY_MIX = ControlSpec.UNIPOLAR
specs.DELAY_FC = ControlSpec.new(500, 12000, "exp", 0, 4000, "Hz")
specs.REVERB_MIX = ControlSpec.UNIPOLAR
specs.REVERB_ROOM = ControlSpec.new(0, 1, "lin", 0, 0.8, "")
specs.REVERB_DAMP = ControlSpec.new(0, 1, "lin", 0, 0.4, "")

Ash.specs = specs
Ash.options = options

Ash.RANDOM_PITCH_ST = {-12, 0, 7, 12}

Ash.SYNTH_PARAM_IDS = {
  "osc1_wave", "osc1_level", "osc1_detune", "osc1_pw", "osc1_pitch", "osc1_octave",
  "osc2_wave", "osc2_level", "osc2_detune", "osc2_pw", "osc2_pitch", "osc2_octave",
  "noise_level", "fm_amount", "glide", "glide_mode",
  "lp_cutoff", "lp_resonance", "lp_env_amount", "lp_tracking",
  "filter_attack", "filter_decay", "filter_sustain", "filter_release", "filter_env_link_amp",
  "amp_attack", "amp_decay", "amp_sustain", "amp_release", "drive",
  "lfo_rate", "lfo_shape", "lfo_master",
  "lfo_osc_amount", "lfo_filter_amount",
  "lfo_filter_env_attack_amount", "lfo_filter_env_decay_amount", "lfo_filter_env_sustain_amount", "lfo_filter_env_release_amount",
  "lfo_amp_amount", "lfo_pw_amount",
  "lfo_detune1_amount", "lfo_detune2_amount", "lfo_noise_amount", "lfo_fm_amount", "lfo_glide_amount",
  "lfo_delay_amount", "lfo_reverb_amount", "lfo_drive_amount",

  "lfo2_rate", "lfo2_shape", "lfo2_master",
  "lfo2_osc_amount", "lfo2_filter_amount",
  "lfo2_filter_env_attack_amount", "lfo2_filter_env_decay_amount", "lfo2_filter_env_sustain_amount", "lfo2_filter_env_release_amount",
  "lfo2_amp_amount", "lfo2_pw_amount",
  "lfo2_detune1_amount", "lfo2_detune2_amount", "lfo2_noise_amount", "lfo2_fm_amount", "lfo2_glide_amount",
  "lfo2_delay_amount", "lfo2_reverb_amount", "lfo2_drive_amount",

  "delay_sync", "delay_time", "delay_division", "delay_feedback", "delay_mix", "delay_filter",
  "reverb_mix", "reverb_room", "reverb_damp",
}

-- Factory values (match controlspec / params:add defaults at first boot)
Ash.FACTORY_PRESET = {
  osc1_wave = 2, osc2_wave = 2,
  osc1_level = 0.5, osc2_level = 0,
  osc1_detune = 0, osc2_detune = 0,
  osc1_pw = 0.5, osc2_pw = 0.5,
  osc1_pitch = 0, osc2_pitch = 0,
  osc1_octave = 0, osc2_octave = 0,
  noise_level = 0, fm_amount = 0, glide = 0, glide_mode = 1,
  lp_cutoff = 800, lp_resonance = 0.15, lp_env_amount = 0.45, lp_tracking = 1,
  filter_attack = 0.01, filter_decay = 0.25, filter_sustain = 0.5, filter_release = 0.4,
  filter_env_link_amp = 1,
  amp_attack = 0.01, amp_decay = 0.25, amp_sustain = 0.5, amp_release = 0.4,
  drive = 0.2,
  lfo_rate = 1, lfo_shape = 1, lfo_master = 1,
  lfo_osc_amount = 0, lfo_filter_amount = 0,
  lfo_filter_env_attack_amount = 0, lfo_filter_env_decay_amount = 0, lfo_filter_env_sustain_amount = 0, lfo_filter_env_release_amount = 0,
  lfo_amp_amount = 0, lfo_pw_amount = 0,
  lfo_detune1_amount = 0, lfo_detune2_amount = 0, lfo_noise_amount = 0, lfo_fm_amount = 0, lfo_glide_amount = 0,
  lfo_delay_amount = 0, lfo_reverb_amount = 0, lfo_drive_amount = 0,

  lfo2_rate = 1, lfo2_shape = 1, lfo2_master = 1,
  lfo2_osc_amount = 0, lfo2_filter_amount = 0,
  lfo2_filter_env_attack_amount = 0, lfo2_filter_env_decay_amount = 0, lfo2_filter_env_sustain_amount = 0, lfo2_filter_env_release_amount = 0,
  lfo2_amp_amount = 0, lfo2_pw_amount = 0,
  lfo2_detune1_amount = 0, lfo2_detune2_amount = 0, lfo2_noise_amount = 0, lfo2_fm_amount = 0, lfo2_glide_amount = 0,
  lfo2_delay_amount = 0, lfo2_reverb_amount = 0, lfo2_drive_amount = 0,

  delay_sync = 2, delay_time = 0.375, delay_division = 9, delay_feedback = 0.45, delay_mix = 0, delay_filter = 4000,
  reverb_mix = 0, reverb_room = 0.8, reverb_damp = 0.4,
}

local function format_octave(param)
  local v = param:get()
  if v > 0 then return "+" .. v .. " oct"
  elseif v < 0 then return v .. " oct"
  else return "0 oct" end
end

local function format_pitch(param)
  local v = util.round(param:get(), 0.1)
  if v > 0 then return string.format("+%.1f st", v)
  elseif v < 0 then return string.format("%.1f st", v)
  else return "0.0 st" end
end

local function engine_call(fn, ...)
  if engine and fn then
    local ok, err = pcall(fn, ...)
    if not ok then print("ASH engine: " .. tostring(err)) end
  end
end

local env_link_guard = false

local function filter_env_linked()
  return params:get("filter_env_link_amp") == 2
end

local function filter_env_action(engine_fn, amp_id)
  return function(v)
    engine_call(engine_fn, v)
    if filter_env_linked() and not env_link_guard then
      env_link_guard = true
      params:set(amp_id, v)
      env_link_guard = false
    end
  end
end

local function amp_env_action(engine_fn, filter_id)
  return function(v)
    engine_call(engine_fn, v)
    if filter_env_linked() and not env_link_guard then
      env_link_guard = true
      params:set(filter_id, v)
      env_link_guard = false
    end
  end
end

local function sync_amp_env_from_filter()
  env_link_guard = true
  params:set("amp_attack", params:get("filter_attack"))
  params:set("amp_decay", params:get("filter_decay"))
  params:set("amp_sustain", params:get("filter_sustain"))
  params:set("amp_release", params:get("filter_release"))
  env_link_guard = false
end

function Ash.add_params()
  params:add_separator("ASH")

  params:add_separator("osc 1")
  params:add{type = "option", id = "osc1_wave", name = "Waveform", options = options.WAVE, default = 2,
    action = function(v) engine_call(engine.osc1Wave, v - 1) end}
  params:add{type = "control", id = "osc1_level", name = "Level", controlspec = specs.OSC_LEVEL,
    action = function(v) engine_call(engine.osc1Level, v) end}
  params:add{type = "control", id = "osc1_detune", name = "Detune", controlspec = specs.DETUNE,
    formatter = function(p) return util.round(p:get(), 0.1) .. " ct" end,
    action = function(v) engine_call(engine.osc1Detune, v) end}
  params:add{type = "control", id = "osc1_pw", name = "Pulse Width", controlspec = specs.PW,
    action = function(v) engine_call(engine.osc1Pw, v) end}
  params:add{type = "control", id = "osc1_pitch", name = "Pitch", controlspec = specs.PITCH, formatter = format_pitch,
    action = function(v) engine_call(engine.osc1Pitch, v) end}
  params:add{type = "control", id = "osc1_octave", name = "Octave", controlspec = specs.OCTAVE, formatter = format_octave,
    action = function(v) engine_call(engine.osc1Octave, v) end}

  params:add_separator("osc 2")
  params:add{type = "option", id = "osc2_wave", name = "Waveform", options = options.WAVE, default = 2,
    action = function(v) engine_call(engine.osc2Wave, v - 1) end}
  params:add{type = "control", id = "osc2_level", name = "Level", controlspec = specs.OSC_LEVEL, default = 0,
    action = function(v) engine_call(engine.osc2Level, v) end}
  params:add{type = "control", id = "osc2_detune", name = "Detune", controlspec = specs.DETUNE,
    formatter = function(p) return util.round(p:get(), 0.1) .. " ct" end,
    action = function(v) engine_call(engine.osc2Detune, v) end}
  params:add{type = "control", id = "osc2_pw", name = "Pulse Width", controlspec = specs.PW,
    action = function(v) engine_call(engine.osc2Pw, v) end}
  params:add{type = "control", id = "osc2_pitch", name = "Pitch", controlspec = specs.PITCH, formatter = format_pitch,
    action = function(v) engine_call(engine.osc2Pitch, v) end}
  params:add{type = "control", id = "osc2_octave", name = "Octave", controlspec = specs.OCTAVE, formatter = format_octave,
    action = function(v) engine_call(engine.osc2Octave, v) end}

  params:add_separator("mix")
  params:add{type = "control", id = "noise_level", name = "Noise", controlspec = specs.NOISE,
    action = function(v) engine_call(engine.noiseLevel, v) end}
  params:add{type = "control", id = "fm_amount", name = "FM", controlspec = specs.FM_AMOUNT,
    formatter = function(p) return util.round(p:get() * 100) .. "%" end,
    action = function(v) engine_call(engine.fmAmount, v) end}
  params:add{type = "control", id = "glide", name = "Glide", controlspec = specs.GLIDE, formatter = Formatters.format_secs,
    action = function(v) engine_call(engine.glide, v) end}
  params:add{type = "option", id = "glide_mode", name = "Glide Mode", options = options.GLIDE_MODE, default = 1}

  params:add_separator("filter")
  params:add{type = "control", id = "lp_cutoff", name = "LP Cutoff", controlspec = specs.LP_CUTOFF, formatter = Formatters.format_freq,
    action = function(v) engine_call(engine.lpCutoff, v) end}
  params:add{type = "control", id = "lp_resonance", name = "LP Resonance", controlspec = specs.LP_RES,
    action = function(v) engine_call(engine.lpResonance, v) end}
  params:add{type = "control", id = "lp_env_amount", name = "Filter Env Amount", controlspec = specs.LP_ENV_AMT,
    action = function(v) engine_call(engine.lpEnvAmount, v) end}
  params:add{type = "control", id = "lp_tracking", name = "Key Tracking", controlspec = specs.LP_TRACK,
    formatter = function(p) return util.round(p:get(), 0.01) .. ":1" end,
    action = function(v) engine_call(engine.lpTracking, v) end}

  params:add_separator("filter env")
  params:add{type = "control", id = "filter_attack", name = "Attack", controlspec = specs.ENV_A, formatter = Formatters.format_secs,
    action = filter_env_action(engine.filterAtk, "amp_attack")}
  params:add{type = "control", id = "filter_decay", name = "Decay", controlspec = specs.ENV_D, formatter = Formatters.format_secs,
    action = filter_env_action(engine.filterDec, "amp_decay")}
  params:add{type = "control", id = "filter_sustain", name = "Sustain", controlspec = specs.ENV_S,
    action = filter_env_action(engine.filterSus, "amp_sustain")}
  params:add{type = "control", id = "filter_release", name = "Release", controlspec = specs.ENV_R, formatter = Formatters.format_secs,
    action = filter_env_action(engine.filterRel, "amp_release")}
  params:add{type = "option", id = "filter_env_link_amp", name = "LINK", options = options.ENV_LINK, default = 1,
    action = function(v)
      engine_call(engine.filterEnvLinkAmp, v == 2 and 1 or 0)
      if v == 2 then sync_amp_env_from_filter() end
    end}

  params:add_separator("amp env")
  params:add{type = "control", id = "amp_attack", name = "Attack", controlspec = specs.ENV_A, formatter = Formatters.format_secs,
    action = amp_env_action(engine.ampAtk, "filter_attack")}
  params:add{type = "control", id = "amp_decay", name = "Decay", controlspec = specs.ENV_D, formatter = Formatters.format_secs,
    action = amp_env_action(engine.ampDec, "filter_decay")}
  params:add{type = "control", id = "amp_sustain", name = "Sustain", controlspec = specs.ENV_S,
    action = amp_env_action(engine.ampSus, "filter_sustain")}
  params:add{type = "control", id = "amp_release", name = "Release", controlspec = specs.ENV_R, formatter = Formatters.format_secs,
    action = amp_env_action(engine.ampRel, "filter_release")}
  params:add{type = "control", id = "drive", name = "Drive", controlspec = specs.DRIVE, default = 0.2,
    formatter = function(p) return util.round(p:get() * 100) .. "%" end,
    action = function(v) engine_call(engine.drive, v) end}

  params:add_separator("lfo1")
  params:add{type = "control", id = "lfo_rate", name = "LFO1 Rate", controlspec = specs.LFO_RATE, formatter = Formatters.format_freq,
    action = function(v) engine_call(engine.lfoRate, v) end}
  params:add{type = "option", id = "lfo_shape", name = "LFO1 Waveform", options = options.LFO_SHAPE, default = 1,
    action = function(v) engine_call(engine.lfoShape, v - 1) end}
  params:add{type = "control", id = "lfo_master", name = "LFO1 Master", controlspec = specs.LFO_MASTER, default = 1,
    formatter = function(p) return util.round(p:get() * 100) .. "%" end,
    action = function(v) engine_call(engine.lfoMaster, v) end}
  params:add{type = "control", id = "lfo_osc_amount", name = "LFO1 > Osc", controlspec = specs.LFO_AMT,
    action = function(v) engine_call(engine.lfoOscAmt, v) end}
  params:add{type = "control", id = "lfo_filter_amount", name = "LFO1 > Filter", controlspec = specs.LFO_AMT,
    action = function(v) engine_call(engine.lfoFilterAmt, v) end}
  params:add{type = "control", id = "lfo_filter_env_attack_amount", name = "LFO1 > FEnv Attack", controlspec = specs.LFO_AMT,
    formatter = function(p) return util.round(p:get() * 100) .. "%" end,
    action = function(v) engine_call(engine.lfoFilterEnvAtkAmt, v) end}
  params:add{type = "control", id = "lfo_filter_env_decay_amount", name = "LFO1 > FEnv Decay", controlspec = specs.LFO_AMT,
    formatter = function(p) return util.round(p:get() * 100) .. "%" end,
    action = function(v) engine_call(engine.lfoFilterEnvDecAmt, v) end}
  params:add{type = "control", id = "lfo_filter_env_sustain_amount", name = "LFO1 > FEnv Sustain", controlspec = specs.LFO_AMT,
    formatter = function(p) return util.round(p:get() * 100) .. "%" end,
    action = function(v) engine_call(engine.lfoFilterEnvSusAmt, v) end}
  params:add{type = "control", id = "lfo_filter_env_release_amount", name = "LFO1 > FEnv Release", controlspec = specs.LFO_AMT,
    formatter = function(p) return util.round(p:get() * 100) .. "%" end,
    action = function(v) engine_call(engine.lfoFilterEnvRelAmt, v) end}
  params:add{type = "control", id = "lfo_amp_amount", name = "LFO1 > Amp", controlspec = specs.LFO_AMT,
    action = function(v) engine_call(engine.lfoAmpAmt, v) end}
  params:add{type = "control", id = "lfo_pw_amount", name = "LFO1 > PW", controlspec = specs.LFO_AMT,
    formatter = function(p) return util.round(p:get() * 100) .. "%" end,
    action = function(v) engine_call(engine.lfoPwAmt, v) end}
  params:add{type = "control", id = "lfo_detune1_amount", name = "LFO1 > Detune 1", controlspec = specs.LFO_AMT,
    formatter = function(p) return util.round(p:get() * 100) .. "%" end,
    action = function(v) engine_call(engine.lfoDet1Amt, v) end}
  params:add{type = "control", id = "lfo_detune2_amount", name = "LFO1 > Detune 2", controlspec = specs.LFO_AMT,
    formatter = function(p) return util.round(p:get() * 100) .. "%" end,
    action = function(v) engine_call(engine.lfoDet2Amt, v) end}
  params:add{type = "control", id = "lfo_noise_amount", name = "LFO1 > Noise", controlspec = specs.LFO_AMT,
    formatter = function(p) return util.round(p:get() * 100) .. "%" end,
    action = function(v) engine_call(engine.lfoNoiseAmt, v) end}
  params:add{type = "control", id = "lfo_fm_amount", name = "LFO1 > FM", controlspec = specs.LFO_AMT,
    formatter = function(p) return util.round(p:get() * 100) .. "%" end,
    action = function(v) engine_call(engine.lfoFmAmt, v) end}
  params:add{type = "control", id = "lfo_glide_amount", name = "LFO1 > Glide", controlspec = specs.LFO_AMT,
    formatter = function(p) return util.round(p:get() * 100) .. "%" end,
    action = function(v) engine_call(engine.lfoGlideAmt, v) end}
  params:add{type = "control", id = "lfo_delay_amount", name = "LFO1 > Delay", controlspec = specs.LFO_AMT,
    formatter = function(p) return util.round(p:get() * 100) .. "%" end,
    action = function(v) engine_call(engine.lfoDelayAmt, v) end}
  params:add{type = "control", id = "lfo_reverb_amount", name = "LFO1 > Reverb", controlspec = specs.LFO_AMT,
    formatter = function(p) return util.round(p:get() * 100) .. "%" end,
    action = function(v) engine_call(engine.lfoReverbAmt, v) end}
  params:add{type = "control", id = "lfo_drive_amount", name = "LFO1 > Drive", controlspec = specs.LFO_AMT,
    formatter = function(p) return util.round(p:get() * 100) .. "%" end,
    action = function(v) engine_call(engine.lfoDriveAmt, v) end}

  params:add_separator("lfo2")
  params:add{type = "control", id = "lfo2_rate", name = "LFO2 Rate", controlspec = specs.LFO_RATE, formatter = Formatters.format_freq,
    action = function(v) engine_call(engine.lfo2Rate, v) end}
  params:add{type = "option", id = "lfo2_shape", name = "LFO2 Waveform", options = options.LFO_SHAPE, default = 1,
    action = function(v) engine_call(engine.lfo2Shape, v - 1) end}
  params:add{type = "control", id = "lfo2_master", name = "LFO2 Master", controlspec = specs.LFO_MASTER, default = 1,
    formatter = function(p) return util.round(p:get() * 100) .. "%" end,
    action = function(v) engine_call(engine.lfo2Master, v) end}
  params:add{type = "control", id = "lfo2_osc_amount", name = "LFO2 > Osc", controlspec = specs.LFO_AMT,
    action = function(v) engine_call(engine.lfo2OscAmt, v) end}
  params:add{type = "control", id = "lfo2_filter_amount", name = "LFO2 > Filter", controlspec = specs.LFO_AMT,
    action = function(v) engine_call(engine.lfo2FilterAmt, v) end}
  params:add{type = "control", id = "lfo2_filter_env_attack_amount", name = "LFO2 > FEnv Attack", controlspec = specs.LFO_AMT,
    formatter = function(p) return util.round(p:get() * 100) .. "%" end,
    action = function(v) engine_call(engine.lfo2FilterEnvAtkAmt, v) end}
  params:add{type = "control", id = "lfo2_filter_env_decay_amount", name = "LFO2 > FEnv Decay", controlspec = specs.LFO_AMT,
    formatter = function(p) return util.round(p:get() * 100) .. "%" end,
    action = function(v) engine_call(engine.lfo2FilterEnvDecAmt, v) end}
  params:add{type = "control", id = "lfo2_filter_env_sustain_amount", name = "LFO2 > FEnv Sustain", controlspec = specs.LFO_AMT,
    formatter = function(p) return util.round(p:get() * 100) .. "%" end,
    action = function(v) engine_call(engine.lfo2FilterEnvSusAmt, v) end}
  params:add{type = "control", id = "lfo2_filter_env_release_amount", name = "LFO2 > FEnv Release", controlspec = specs.LFO_AMT,
    formatter = function(p) return util.round(p:get() * 100) .. "%" end,
    action = function(v) engine_call(engine.lfo2FilterEnvRelAmt, v) end}
  params:add{type = "control", id = "lfo2_amp_amount", name = "LFO2 > Amp", controlspec = specs.LFO_AMT,
    action = function(v) engine_call(engine.lfo2AmpAmt, v) end}
  params:add{type = "control", id = "lfo2_pw_amount", name = "LFO2 > PW", controlspec = specs.LFO_AMT,
    formatter = function(p) return util.round(p:get() * 100) .. "%" end,
    action = function(v) engine_call(engine.lfo2PwAmt, v) end}
  params:add{type = "control", id = "lfo2_detune1_amount", name = "LFO2 > Detune 1", controlspec = specs.LFO_AMT,
    formatter = function(p) return util.round(p:get() * 100) .. "%" end,
    action = function(v) engine_call(engine.lfo2Det1Amt, v) end}
  params:add{type = "control", id = "lfo2_detune2_amount", name = "LFO2 > Detune 2", controlspec = specs.LFO_AMT,
    formatter = function(p) return util.round(p:get() * 100) .. "%" end,
    action = function(v) engine_call(engine.lfo2Det2Amt, v) end}
  params:add{type = "control", id = "lfo2_noise_amount", name = "LFO2 > Noise", controlspec = specs.LFO_AMT,
    formatter = function(p) return util.round(p:get() * 100) .. "%" end,
    action = function(v) engine_call(engine.lfo2NoiseAmt, v) end}
  params:add{type = "control", id = "lfo2_fm_amount", name = "LFO2 > FM", controlspec = specs.LFO_AMT,
    formatter = function(p) return util.round(p:get() * 100) .. "%" end,
    action = function(v) engine_call(engine.lfo2FmAmt, v) end}
  params:add{type = "control", id = "lfo2_glide_amount", name = "LFO2 > Glide", controlspec = specs.LFO_AMT,
    formatter = function(p) return util.round(p:get() * 100) .. "%" end,
    action = function(v) engine_call(engine.lfo2GlideAmt, v) end}
  params:add{type = "control", id = "lfo2_delay_amount", name = "LFO2 > Delay", controlspec = specs.LFO_AMT,
    formatter = function(p) return util.round(p:get() * 100) .. "%" end,
    action = function(v) engine_call(engine.lfo2DelayAmt, v) end}
  params:add{type = "control", id = "lfo2_reverb_amount", name = "LFO2 > Reverb", controlspec = specs.LFO_AMT,
    formatter = function(p) return util.round(p:get() * 100) .. "%" end,
    action = function(v) engine_call(engine.lfo2ReverbAmt, v) end}
  params:add{type = "control", id = "lfo2_drive_amount", name = "LFO2 > Drive", controlspec = specs.LFO_AMT,
    formatter = function(p) return util.round(p:get() * 100) .. "%" end,
    action = function(v) engine_call(engine.lfo2DriveAmt, v) end}

  params:add_separator("delay")
  params:add{type = "option", id = "delay_sync", name = "Delay Sync", options = options.DELAY_SYNC, default = 2}
  params:add{type = "control", id = "delay_time", name = "Delay Time", controlspec = specs.DELAY_TIME, formatter = Formatters.format_secs}
  params:add{type = "option", id = "delay_division", name = "Delay Division", options = options.DELAY_DIV, default = 9,
    action = function() Ash.apply_delay_time() end}
  params:add{type = "control", id = "delay_feedback", name = "Delay Feedback", controlspec = specs.DELAY_FB,
    action = function(v) engine_call(engine.delayFeedback, v) end}
  params:add{type = "control", id = "delay_mix", name = "Delay Mix", controlspec = specs.DELAY_MIX,
    action = function(v) engine_call(engine.delayMix, v) end}
  params:add{type = "control", id = "delay_filter", name = "Delay Filter", controlspec = specs.DELAY_FC, formatter = Formatters.format_freq,
    action = function(v) engine_call(engine.delayFilter, v) end}

  params:add_separator("reverb")
  params:add{type = "control", id = "reverb_mix", name = "Reverb Mix", controlspec = specs.REVERB_MIX,
    action = function(v) engine_call(engine.reverbMix, v) end}
  params:add{type = "control", id = "reverb_room", name = "Reverb Room", controlspec = specs.REVERB_ROOM,
    action = function(v) engine_call(engine.reverbRoom, v) end}
  params:add{type = "control", id = "reverb_damp", name = "Reverb Damp", controlspec = specs.REVERB_DAMP,
    action = function(v) engine_call(engine.reverbDamp, v) end}

end

function Ash.push_engine_state()
  if not engine then return end
  engine_call(engine.osc1Wave, params:get("osc1_wave") - 1)
  engine_call(engine.osc2Wave, params:get("osc2_wave") - 1)
  engine_call(engine.osc1Level, params:get("osc1_level"))
  engine_call(engine.osc2Level, params:get("osc2_level"))
  engine_call(engine.osc1Pw, params:get("osc1_pw"))
  engine_call(engine.osc2Pw, params:get("osc2_pw"))
  engine_call(engine.osc1Pitch, params:get("osc1_pitch"))
  engine_call(engine.osc2Pitch, params:get("osc2_pitch"))
  engine_call(engine.osc1Octave, params:get("osc1_octave"))
  engine_call(engine.osc2Octave, params:get("osc2_octave"))
  engine_call(engine.osc1Detune, params:get("osc1_detune"))
  engine_call(engine.osc2Detune, params:get("osc2_detune"))
  engine_call(engine.noiseLevel, params:get("noise_level"))
  engine_call(engine.fmAmount, params:get("fm_amount"))
  engine_call(engine.glide, params:get("glide"))
  engine_call(engine.lpCutoff, params:get("lp_cutoff"))
  engine_call(engine.lpResonance, params:get("lp_resonance"))
  engine_call(engine.lpEnvAmount, params:get("lp_env_amount"))
  engine_call(engine.lpTracking, params:get("lp_tracking"))
  engine_call(engine.filterAtk, params:get("filter_attack"))
  engine_call(engine.filterDec, params:get("filter_decay"))
  engine_call(engine.filterSus, params:get("filter_sustain"))
  engine_call(engine.filterRel, params:get("filter_release"))
  engine_call(engine.filterEnvLinkAmp, params:get("filter_env_link_amp") == 2 and 1 or 0)
  engine_call(engine.ampAtk, params:get("amp_attack"))
  engine_call(engine.ampDec, params:get("amp_decay"))
  engine_call(engine.ampSus, params:get("amp_sustain"))
  engine_call(engine.ampRel, params:get("amp_release"))
  engine_call(engine.drive, params:get("drive"))
  engine_call(engine.lfoRate, params:get("lfo_rate"))
  engine_call(engine.lfoShape, params:get("lfo_shape") - 1)
  engine_call(engine.lfoMaster, params:get("lfo_master"))
  engine_call(engine.lfoOscAmt, params:get("lfo_osc_amount"))
  engine_call(engine.lfoFilterAmt, params:get("lfo_filter_amount"))
  engine_call(engine.lfoFilterEnvAtkAmt, params:get("lfo_filter_env_attack_amount"))
  engine_call(engine.lfoFilterEnvDecAmt, params:get("lfo_filter_env_decay_amount"))
  engine_call(engine.lfoFilterEnvSusAmt, params:get("lfo_filter_env_sustain_amount"))
  engine_call(engine.lfoFilterEnvRelAmt, params:get("lfo_filter_env_release_amount"))
  engine_call(engine.lfoAmpAmt, params:get("lfo_amp_amount"))
  engine_call(engine.lfoPwAmt, params:get("lfo_pw_amount"))
  engine_call(engine.lfoDet1Amt, params:get("lfo_detune1_amount"))
  engine_call(engine.lfoDet2Amt, params:get("lfo_detune2_amount"))
  engine_call(engine.lfoNoiseAmt, params:get("lfo_noise_amount"))
  engine_call(engine.lfoFmAmt, params:get("lfo_fm_amount"))
  engine_call(engine.lfoGlideAmt, params:get("lfo_glide_amount"))
  engine_call(engine.lfoDelayAmt, params:get("lfo_delay_amount"))
  engine_call(engine.lfoReverbAmt, params:get("lfo_reverb_amount"))
  engine_call(engine.lfoDriveAmt, params:get("lfo_drive_amount"))

  engine_call(engine.lfo2Rate, params:get("lfo2_rate"))
  engine_call(engine.lfo2Shape, params:get("lfo2_shape") - 1)
  engine_call(engine.lfo2Master, params:get("lfo2_master"))
  engine_call(engine.lfo2OscAmt, params:get("lfo2_osc_amount"))
  engine_call(engine.lfo2FilterAmt, params:get("lfo2_filter_amount"))
  engine_call(engine.lfo2FilterEnvAtkAmt, params:get("lfo2_filter_env_attack_amount"))
  engine_call(engine.lfo2FilterEnvDecAmt, params:get("lfo2_filter_env_decay_amount"))
  engine_call(engine.lfo2FilterEnvSusAmt, params:get("lfo2_filter_env_sustain_amount"))
  engine_call(engine.lfo2FilterEnvRelAmt, params:get("lfo2_filter_env_release_amount"))
  engine_call(engine.lfo2AmpAmt, params:get("lfo2_amp_amount"))
  engine_call(engine.lfo2PwAmt, params:get("lfo2_pw_amount"))
  engine_call(engine.lfo2Det1Amt, params:get("lfo2_detune1_amount"))
  engine_call(engine.lfo2Det2Amt, params:get("lfo2_detune2_amount"))
  engine_call(engine.lfo2NoiseAmt, params:get("lfo2_noise_amount"))
  engine_call(engine.lfo2FmAmt, params:get("lfo2_fm_amount"))
  engine_call(engine.lfo2GlideAmt, params:get("lfo2_glide_amount"))
  engine_call(engine.lfo2DelayAmt, params:get("lfo2_delay_amount"))
  engine_call(engine.lfo2ReverbAmt, params:get("lfo2_reverb_amount"))
  engine_call(engine.lfo2DriveAmt, params:get("lfo2_drive_amount"))
  engine_call(engine.delayFeedback, params:get("delay_feedback"))
  engine_call(engine.delayMix, params:get("delay_mix"))
  engine_call(engine.delayFilter, params:get("delay_filter"))
  engine_call(engine.reverbMix, params:get("reverb_mix"))
  engine_call(engine.reverbRoom, params:get("reverb_room"))
  engine_call(engine.reverbDamp, params:get("reverb_damp"))
  Ash.apply_delay_time()
end

function Ash.bang()
  params:bang()
  Ash.push_engine_state()
end

function Ash.delay_division_beats(idx)
  return Ash.DELAY_DIV_BEATS[idx] or Ash.DELAY_DIV_BEATS[9]
end

function Ash.apply_delay_time()
  if not engine or not engine.delayTime then return end
  if params:get("delay_sync") == 1 then
    engine_call(engine.delayTime, params:get("delay_time"))
  else
    local beat = 0.5
    if clock and clock.get_beat_sec then
      beat = clock.get_beat_sec()
    end
    local beats = Ash.delay_division_beats(params:get("delay_division"))
    engine_call(engine.delayTime, util.clamp(beat * beats, 0.01, 2))
  end
end

local function rand_in_spec(spec, pow_exp)
  local t = math.random()
  if pow_exp then t = math.pow(t, pow_exp) end
  return util.linlin(0, 1, spec.minval, spec.maxval, t)
end

local function maybe_param(id, threshold, value_fn)
  if math.random() > threshold then
    params:set(id, value_fn())
  else
    params:set(id, 0)
  end
end

local function random_pitch_st()
  local choices = Ash.RANDOM_PITCH_ST
  return choices[math.random(#choices)]
end

function Ash.reset_defaults(silent)
  local n = 0
  for _, id in ipairs(Ash.SYNTH_PARAM_IDS) do
    local v = Ash.FACTORY_PRESET[id]
    if v ~= nil then
      params:set(id, v)
      n = n + 1
    end
  end
  Ash.push_engine_state()
  if not silent then print("ASH: defaults (" .. n .. ")") end
end

-- Same patch as K1+K2 INIT; used at boot so pmap does not leave a quieter/louder engine state.
function Ash.boot_synth()
  Ash.reset_defaults(true)
end

function Ash.randomize()
  local LFO_THRESH = 0.65

  params:set("osc1_wave", math.random(3))
  params:set("osc2_wave", math.random(3))
  params:set("osc1_level", math.random() * 0.6 + 0.2)
  params:set("osc2_level", math.random() * 0.6 + 0.2)
  params:set("osc1_pitch", random_pitch_st())
  params:set("osc2_pitch", random_pitch_st())
  params:set("osc1_octave", math.random(-2, 2))
  params:set("osc2_octave", math.random(-2, 2))
  params:set("osc1_pw", math.random())
  params:set("osc2_pw", math.random())
  if math.random() > 0.7 then
    params:set("osc1_detune", rand_in_spec(specs.DETUNE, 2))
    params:set("osc2_detune", rand_in_spec(specs.DETUNE, 2))
  else
    params:set("osc1_detune", 0)
    params:set("osc2_detune", 0)
  end
  params:set("noise_level", math.random() * 0.35)
  if math.random() > 0.55 then
    params:set("fm_amount", math.pow(math.random(), 4))
  else
    params:set("fm_amount", 0)
  end
  if math.random() > 0.8 then
    params:set("glide", rand_in_spec(specs.GLIDE, 2))
  else
    params:set("glide", 0)
  end

  params:set("lp_cutoff", rand_in_spec(specs.LP_CUTOFF))
  params:set("lp_resonance", math.random() * 0.75)
  params:set("lp_env_amount", rand_in_spec(specs.LP_ENV_AMT, 2))
  params:set("lp_tracking", rand_in_spec(specs.LP_TRACK))

  params:set("filter_attack", rand_in_spec(specs.ENV_A, 4))
  params:set("filter_decay", rand_in_spec(specs.ENV_D, 2))
  params:set("filter_sustain", math.random())
  params:set("filter_release", rand_in_spec(specs.ENV_R, 2))
  if params:get("filter_env_link_amp") ~= 2 then
    params:set("amp_attack", rand_in_spec(specs.ENV_A, 4))
    params:set("amp_decay", rand_in_spec(specs.ENV_D, 2))
    params:set("amp_sustain", math.random())
    params:set("amp_release", rand_in_spec(specs.ENV_R, 2))
  end

  params:set("drive", math.random() * 0.65)

  params:set("lfo_shape", math.random(5))
  params:set("lfo_rate", rand_in_spec(specs.LFO_RATE))
  params:set("lfo_master", util.linlin(0, 1, 0.5, 1, math.random()))
  maybe_param("lfo_osc_amount", 0.75, function() return math.pow(math.random(), 2) end)
  maybe_param("lfo_filter_amount", LFO_THRESH, function() return math.random() end)
  maybe_param("lfo_filter_env_attack_amount", LFO_THRESH, function() return math.random() end)
  maybe_param("lfo_filter_env_decay_amount", LFO_THRESH, function() return math.random() end)
  maybe_param("lfo_filter_env_sustain_amount", LFO_THRESH, function() return math.random() end)
  maybe_param("lfo_filter_env_release_amount", LFO_THRESH, function() return math.random() end)
  maybe_param("lfo_amp_amount", LFO_THRESH, function() return math.random() end)
  maybe_param("lfo_pw_amount", LFO_THRESH, function() return math.random() end)
  maybe_param("lfo_detune1_amount", LFO_THRESH, function() return math.random() end)
  maybe_param("lfo_detune2_amount", LFO_THRESH, function() return math.random() end)
  maybe_param("lfo_noise_amount", LFO_THRESH, function() return math.random() end)
  maybe_param("lfo_fm_amount", 0.75, function() return math.random() end)
  maybe_param("lfo_glide_amount", LFO_THRESH, function() return math.random() end)
  maybe_param("lfo_delay_amount", LFO_THRESH, function() return math.random() end)
  maybe_param("lfo_reverb_amount", LFO_THRESH, function() return math.random() end)
  maybe_param("lfo_drive_amount", LFO_THRESH, function() return math.random() end)

  params:set("lfo2_shape", math.random(5))
  params:set("lfo2_rate", rand_in_spec(specs.LFO_RATE))
  params:set("lfo2_master", util.linlin(0, 1, 0.5, 1, math.random()))
  maybe_param("lfo2_osc_amount", 0.75, function() return math.pow(math.random(), 2) end)
  maybe_param("lfo2_filter_amount", LFO_THRESH, function() return math.random() end)
  maybe_param("lfo2_filter_env_attack_amount", LFO_THRESH, function() return math.random() end)
  maybe_param("lfo2_filter_env_decay_amount", LFO_THRESH, function() return math.random() end)
  maybe_param("lfo2_filter_env_sustain_amount", LFO_THRESH, function() return math.random() end)
  maybe_param("lfo2_filter_env_release_amount", LFO_THRESH, function() return math.random() end)
  maybe_param("lfo2_amp_amount", LFO_THRESH, function() return math.random() end)
  maybe_param("lfo2_pw_amount", LFO_THRESH, function() return math.random() end)
  maybe_param("lfo2_detune1_amount", LFO_THRESH, function() return math.random() end)
  maybe_param("lfo2_detune2_amount", LFO_THRESH, function() return math.random() end)
  maybe_param("lfo2_noise_amount", LFO_THRESH, function() return math.random() end)
  maybe_param("lfo2_fm_amount", 0.75, function() return math.random() end)
  maybe_param("lfo2_glide_amount", LFO_THRESH, function() return math.random() end)
  maybe_param("lfo2_delay_amount", LFO_THRESH, function() return math.random() end)
  maybe_param("lfo2_reverb_amount", LFO_THRESH, function() return math.random() end)
  maybe_param("lfo2_drive_amount", LFO_THRESH, function() return math.random() end)

  if math.random() > 0.5 then
    params:set("delay_mix", math.random() * 0.55)
    params:set("delay_feedback", rand_in_spec(specs.DELAY_FB, 2))
    params:set("delay_filter", rand_in_spec(specs.DELAY_FC))
    params:set("delay_division", math.random(#options.DELAY_DIV))
  else
    params:set("delay_mix", 0)
  end

  params:set("reverb_mix", math.random() * 0.55)
  params:set("reverb_room", rand_in_spec(specs.REVERB_ROOM))
  params:set("reverb_damp", rand_in_spec(specs.REVERB_DAMP))
end

return Ash
