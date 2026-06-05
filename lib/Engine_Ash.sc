// CroneEngine_Ash
// Classic mono synth: dual osc, LP filter, dual ADSR, LFO, delay, reverb.
// v1.1.2

Engine_Ash : CroneEngine {

	var lfo;
	var lfo2;
	var synthVoice;
	var delayFx;
	var reverbFx;

	var lfoBus;
	var lfo2Bus;
	var fxBus;

	var noteList;
	var activeNoteId;
	var lastFreq;

	var startPauseRoutine;
	var pauseRoutine;
	var allocRoutine;
	var maxRelease = 12;

	*new { arg context, doneCallback;
		^super.new(context, doneCallback);
	}

	alloc {

		allocRoutine = Routine({

			lfoBus = Bus.control(context.server, 1);
			lfo2Bus = Bus.control(context.server, 1);
			fxBus = Bus.audio(context.server, 2);

			noteList = List.new();
			lastFreq = 220;

			SynthDef(\asynthLfo, {
				arg out, lfoRate = 1, lfoShape = 0;
				var lfo, shapes;
				lfoRate = Lag.kr(lfoRate, 0.01);
				shapes = [
					SinOsc.kr(lfoRate),
					LFTri.kr(lfoRate),
					LFSaw.kr(lfoRate),
					LFPulse.kr(lfoRate, 0.5, 0),
					LFNoise0.kr(lfoRate)
				];
				lfo = Select.kr(lfoShape.clip(0, 4), shapes);
				Out.kr(out, lfo);
			}).add;

			SynthDef(\asynthVoice, {
				arg out, lfoIn, lfo2In, gate, killGate, freq = 220, pitchBendRatio = 1, glide = 0, glideOn = 1, vel = 1,
				osc1Wave = 1, osc2Wave = 1, osc1Level = 0.5, osc2Level = 0, osc1Pw = 0.5, osc2Pw = 0.5,
				osc1Pitch = 0, osc1Octave = 0, osc2Pitch = 0, osc2Octave = 0,
				noiseLevel = 0, osc1Detune = 0, osc2Detune = 0, fmAmount = 0,
				lpCutoff = 800, lpResonance = 0.15, lpEnvAmount = 0.45, lpTracking = 1,
				filterAtk = 0.01, filterDec = 0.25, filterSus = 0.5, filterRel = 0.4,
				ampAtk = 0.01, ampDec = 0.25, ampSus = 0.5, ampRel = 0.4,
				filterEnvLinkAmp = 0,
				lfoMaster = 1,
				lfoOscAmt = 0, lfoFilterAmt = 0,
				lfoFilterEnvAtkAmt = 0, lfoFilterEnvDecAmt = 0, lfoFilterEnvSusAmt = 0, lfoFilterEnvRelAmt = 0,
				lfoAmpAmt = 0,
				lfoPwAmt = 0, lfoDet1Amt = 0, lfoDet2Amt = 0, lfoNoiseAmt = 0, lfoFmAmt = 0, lfoGlideAmt = 0,
				lfoDriveAmt = 0,
				lfo2Master = 1,
				lfo2OscAmt = 0, lfo2FilterAmt = 0,
				lfo2FilterEnvAtkAmt = 0, lfo2FilterEnvDecAmt = 0, lfo2FilterEnvSusAmt = 0, lfo2FilterEnvRelAmt = 0,
				lfo2AmpAmt = 0,
				lfo2PwAmt = 0, lfo2Det1Amt = 0, lfo2Det2Amt = 0, lfo2NoiseAmt = 0, lfo2FmAmt = 0, lfo2GlideAmt = 0,
				lfo2DriveAmt = 0,
				drive = 0.2;

				var i_nyquist = SampleRate.ir * 0.5, i_cFreq = 48.midicps, lfo, lfo2, controlLag = 0.005,
				fBase, f1, f2, osc1, osc2, osc2Free, lockOscs, fmAmt, fmMod, fmLayer, signal, filterEnv, filterEnvBase, ampEnv, ampEnvPlain, killEnv,
				lfoFenvAtk, lfoFenvDec, lfoFenvSus, lfoFenvRel, susTarget,
				filterAtkEff, filterDecEff, filterRelEff,
				attackRaw, decayRaw, releaseRaw, attackW, decayW, releaseW,
				cutRatio, lpFreq, rq, glideMod, osc1PwMod, osc2PwMod, det1, det2, noiseMod, fmLfo, fmRaw, driveMod;

				lfo = In.kr(lfoIn, 1) * Lag.kr(lfoMaster.clip(0, 1), controlLag);
				lfo2 = In.kr(lfo2In, 1) * Lag.kr(lfo2Master.clip(0, 1), controlLag);

				fBase = freq * pitchBendRatio * (((lfo * lfoOscAmt) + (lfo2 * lfo2OscAmt)) * 24).midiratio;
				// MIX glide + LFO glide (bipolar lfo; 0 when LFO master or waveform center)
				glideMod = (
					(glide * Lag.kr(glideOn.clip(0, 1), 0.01))
					+ (((lfo * lfoGlideAmt) + (lfo2 * lfo2GlideAmt)) * 1.2).clip(0, 3)
				).clip(0, 3);
				fBase = Lag.kr(fBase, 0.005 + glideMod);
				// Bipolar LFO around MIX detune; returns to mix value when LFO depth is 0
				det1 = Select.kr((lfoDet1Amt + lfo2Det1Amt) < 0.0001, [
					(osc1Detune + ((lfo * lfoDet1Amt) + (lfo2 * lfo2Det1Amt)) * 12).clip(-50, 50),
					osc1Detune
				]);
				det2 = Select.kr((lfoDet2Amt + lfo2Det2Amt) < 0.0001, [
					(osc2Detune + ((lfo * lfoDet2Amt) + (lfo2 * lfo2Det2Amt)) * 12).clip(-50, 50),
					osc2Detune
				]);
				f1 = (fBase * (2 ** osc1Octave) * osc1Pitch.midiratio * (1 + (det1 * 0.01))).clip(20, i_nyquist);
				f2 = (fBase * (2 ** osc2Octave) * osc2Pitch.midiratio * (1 + (det2 * 0.01))).clip(20, i_nyquist);

				osc1PwMod = (osc1Pw + ((lfo * lfoPwAmt) + (lfo2 * lfo2PwAmt)) * 0.25).clip(0, 1);
				osc2PwMod = (osc2Pw + ((lfo * lfoPwAmt) + (lfo2 * lfo2PwAmt)) * 0.25).clip(0, 1);

				osc1 = Select.ar(osc1Wave.clip(0, 2), [
					SinOsc.ar(f1),
					Saw.ar(f1),
					Pulse.ar(f1, osc1PwMod.linlin(0, 1, 0.08, 0.92))
				]) * osc1Level;

				osc2Free = Select.ar(osc2Wave.clip(0, 2), [
					SinOsc.ar(f2),
					Saw.ar(f2),
					Pulse.ar(f2, osc2PwMod.linlin(0, 1, 0.08, 0.92))
				]) * osc2Level;

				// Same pitch + zero detune: lock OSC2 to OSC1 phase (avoids stuck phasey tone after detune)
				lockOscs = Lag.kr(
					(det1.abs < 0.01) * (det2.abs < 0.01)
					* ((f1 - f2).abs < 0.1)
					* ((osc1Wave - osc2Wave).abs < 0.1)
					* ((osc1Pitch - osc2Pitch).abs < 0.01)
					* ((osc1Octave - osc2Octave).abs < 0.01),
					0.02
				);
				osc2 = Select.ar(lockOscs, [
					osc2Free,
					osc1 * (osc2Level / osc1Level.max(0.001))
				]);

				// FM: MIX level + LFO fills toward 100% (lfo.max(0) = full depth when master on)
				fmLfo = (lfoFmAmt * lfo.max(0)) + (lfo2FmAmt * lfo2.max(0));
				fmRaw = (fmAmount + (fmLfo * (1 - fmAmount))).clip(0, 1);
				fmAmt = Lag.kr(fmRaw.pow(1.2), controlLag);
				fmMod = SinOsc.ar(
					(fBase * 4).clip(20, i_nyquist),
					mul: fmAmt * 5 * (fBase * 4)
				);
				fmLayer = SinOsc.ar((fBase + fmMod).clip(20, i_nyquist)) * fmAmt * 0.38;

				signal = osc1 + osc2 + fmLayer;
				noiseMod = (noiseLevel + ((lfo * lfoNoiseAmt) + (lfo2 * lfo2NoiseAmt)) * 0.4).clip(0, 1);
				signal = signal + WhiteNoise.ar(noiseMod);

				// FEnv S: sustain level ± LFO. FEnv A/D/R: segment time ± LFO (seconds, not ×).
				lfoFenvAtk = (lfo * lfoFilterEnvAtkAmt) + (lfo2 * lfo2FilterEnvAtkAmt);
				lfoFenvDec = (lfo * lfoFilterEnvDecAmt) + (lfo2 * lfo2FilterEnvDecAmt);
				lfoFenvSus = (lfo * lfoFilterEnvSusAmt) + (lfo2 * lfo2FilterEnvSusAmt);
				lfoFenvRel = (lfo * lfoFilterEnvRelAmt) + (lfo2 * lfo2FilterEnvRelAmt);
				susTarget = (filterSus + lfoFenvSus).clip(0, 1);
				filterAtkEff = (filterAtk + (lfoFenvAtk * 0.28)).clip(0.001, 5);
				filterDecEff = (filterDec + (lfoFenvDec * 0.35)).clip(0.001, 8);
				filterRelEff = (filterRel + (lfoFenvRel * 0.42)).clip(0.001, 12);
				filterEnvBase = EnvGen.kr(
					Env.adsr(filterAtkEff, filterDecEff, susTarget, filterRelEff),
					gate
				);
				attackRaw = gate * (susTarget - filterEnvBase).max(0) / susTarget.max(0.001);
				decayRaw = gate * (filterEnvBase - susTarget).max(0) / (1 - susTarget).clip(0.001, 1);
				releaseRaw = (1 - gate) * filterEnvBase;
				attackW = Lag.kr(attackRaw, (filterAtkEff * 2 + 0.15).clip(0.15, 2.5));
				decayW = Lag.kr(decayRaw, (filterDecEff * 2 + 0.15).clip(0.15, 3));
				releaseW = Lag.kr(releaseRaw, (filterRelEff * 2 + 0.18).clip(0.18, 4));
				filterEnv = (
					filterEnvBase
					* (1
						+ (lfoFenvAtk * attackW * 2)
						+ (lfoFenvDec * decayW * 2)
						+ (lfoFenvRel * releaseW * 2))
				).clip(0, 3.5);
				ampEnvPlain = EnvGen.kr(
					Env.adsr(ampAtk, ampDec, ampSus, ampRel),
					gate
				);
				// LINK on: amp envelope follows filter env incl. LFO FEnv A/D/S/R
				ampEnv = Select.kr(filterEnvLinkAmp.clip(0, 1), [ampEnvPlain, filterEnv]);
				killEnv = EnvGen.kr(Env.asr(0, 1, 0.01), killGate);

				cutRatio = (fBase / i_cFreq).pow(lpTracking.clip(0, 2));

				lpFreq = Lag.kr(lpCutoff.clip(40, 18000), 0.02) * cutRatio;
				lpFreq = lpFreq * (2 ** (filterEnv * lpEnvAmount * 3));
				lpFreq = lpFreq * (2 ** (((lfo * lfoFilterAmt) + (lfo2 * lfo2FilterAmt)) * 2));
				lpFreq = lpFreq.clip(40, 18000);

				rq = lpResonance.linlin(0, 1, 1, 0.05);
				signal = RLPF.ar(RLPF.ar(signal, lpFreq, rq), lpFreq, rq);

				signal = signal * ampEnv;
				signal = signal * (1 + (((lfo * lfoAmpAmt) + (lfo2 * lfo2AmpAmt)) * 0.85));
				signal = signal * vel.linlin(0, 1, 0.12, 1);
				driveMod = (drive + (((lfo * lfoDriveAmt * lfo.max(0)) + (lfo2 * lfo2DriveAmt * lfo2.max(0))) * (1 - drive))).clip(0, 1);
				signal = tanh(signal * (1 + (driveMod.linlin(0, 1, 0, 10)))).softclip * 0.20;
				signal = signal * killEnv;

				Out.ar(out, signal.dup);
			}).add;

			SynthDef(\asynthDelay, {
				arg in, out, lfoIn, lfo2In, mix = 0, lfoDelayAmt = 0, lfo2DelayAmt = 0,
					lfoMaster = 1, lfo2Master = 1,
					time = 0.375, feedback = 0.45, filterFc = 4000;
				var dry, local, wet, outSig, makeup, lfo, lfo2, mixBase, mixEff, lfoUni;
				mixBase = Lag.kr(mix.clip(0, 1), 0.02);
				lfo = In.kr(lfoIn, 1) * Lag.kr(lfoMaster.clip(0, 1), 0.02);
				lfo2 = In.kr(lfo2In, 1) * Lag.kr(lfo2Master.clip(0, 1), 0.02);
				lfoUni = (lfo * lfoDelayAmt * lfo.max(0)) + (lfo2 * lfo2DelayAmt * lfo2.max(0));
				mixEff = (mixBase + (lfoUni * (1 - mixBase))).clip(0, 1);
				time = Lag.kr(time.clip(0.01, 2), 0.02);
				feedback = Lag.kr(feedback.clip(0, 0.95), 0.02);
				dry = In.ar(in, 2);
				local = LocalIn.ar(2);
				local = DelayC.ar(dry + local, 2, time);
				local = LPF.ar(local, filterFc);
				LocalOut.ar(local * feedback);
				wet = local;
				outSig = (dry * (1 - mixEff)) + (wet * mixEff);
				makeup = 1 + (mixEff * 0.35);
				Out.ar(out, outSig * makeup);
			}).add;

			SynthDef(\asynthReverb, {
				arg in, out, lfoIn, lfo2In, mix = 0, lfoReverbAmt = 0, lfo2ReverbAmt = 0,
					lfoMaster = 1, lfo2Master = 1, room = 0.8, damp = 0.4;
				var dry, wet, outSig, makeup, lfo, lfo2, mixBase, mixEff, lfoUni;
				mixBase = Lag.kr(mix.clip(0, 1), 0.02);
				lfo = In.kr(lfoIn, 1) * Lag.kr(lfoMaster.clip(0, 1), 0.02);
				lfo2 = In.kr(lfo2In, 1) * Lag.kr(lfo2Master.clip(0, 1), 0.02);
				lfoUni = (lfo * lfoReverbAmt * lfo.max(0)) + (lfo2 * lfo2ReverbAmt * lfo2.max(0));
				mixEff = (mixBase + (lfoUni * (1 - mixBase))).clip(0, 1);
				dry = In.ar(in, 2);
				wet = FreeVerb2.ar(dry[0], dry[1], mixEff, room, damp);
				outSig = (dry * (1 - mixEff)) + wet;
				makeup = 1 + (mixEff * 0.55);
				Out.ar(out, outSig * makeup);
			}).add;

			context.server.sync;

			lfo = Synth.tail(context.xg, \asynthLfo, [\out, lfoBus]);
			lfo2 = Synth.tail(context.xg, \asynthLfo, [\out, lfo2Bus]);

			synthVoice = Synth.newPaused(\asynthVoice, [
				\out, fxBus,
				\lfoIn, lfoBus,
				\lfo2In, lfo2Bus,
			], target: context.xg, addAction: \addToTail);

			delayFx = Synth.tail(context.xg, \asynthDelay, [
				\in, fxBus,
				\out, fxBus,
				\lfoIn, lfoBus,
				\lfo2In, lfo2Bus,
			]);

			reverbFx = Synth.tail(context.xg, \asynthReverb, [
				\in, fxBus,
				\out, context.out_b,
				\lfoIn, lfoBus,
				\lfo2In, lfo2Bus,
			]);

		}).play;

		this.addCommands;
	}

	free {
		if(allocRoutine.notNil, { allocRoutine.stop; });
		if(pauseRoutine.notNil, { pauseRoutine.stop; });
		if(lfo.notNil, { lfo.free; });
		if(lfo2.notNil, { lfo2.free; });
		if(synthVoice.notNil, { synthVoice.free; });
		if(delayFx.notNil, { delayFx.free; });
		if(reverbFx.notNil, { reverbFx.free; });
		if(lfoBus.notNil, { lfoBus.free; });
		if(lfo2Bus.notNil, { lfo2Bus.free; });
		if(fxBus.notNil, { fxBus.free; });
	}

	addCommands {

		this.addCommand(\noteOn, "iff", { arg msg;
			var id = msg[1], freq = msg[2], vel = msg[3], note = Dictionary.new(2);
			noteList.remove(noteList.detect{ arg item; item[\id] == id });
			if(synthVoice.notNil, {
				pauseRoutine.stop;
				if(lastFreq == 0, { lastFreq = freq });
				synthVoice.run(true);
				synthVoice.set(\freq, freq, \vel, vel, \gate, 1, \killGate, 1);
				note[\id] = id;
				note[\freq] = freq;
				noteList.add(note);
				activeNoteId = id;
				lastFreq = freq;
			});
		});

		startPauseRoutine = {
			pauseRoutine = Routine {
				(maxRelease + 0.01).wait;
				if(synthVoice.notNil, { synthVoice.run(false) });
			}.play;
		};

		this.addCommand(\noteOff, "i", { arg msg;
			var id = msg[1];
			noteList.remove(noteList.detect{ arg item; item[\id] == id });
			if(id == activeNoteId, {
				if(noteList.size > 0, {
					synthVoice.set(\freq, noteList.last.at(\freq));
					activeNoteId = noteList.last.at(\id);
					lastFreq = noteList.last.at(\freq);
				}, {
					synthVoice.set(\gate, 0);
					activeNoteId = nil;
					pauseRoutine.stop;
					startPauseRoutine.value;
				});
			});
		});

		this.addCommand(\noteOffAll, "", { arg msg;
			synthVoice.set(\gate, 0);
			activeNoteId = nil;
			noteList.clear;
			pauseRoutine.stop;
			startPauseRoutine.value;
		});

		this.addCommand(\noteKill, "i", { arg msg;
			var id = msg[1];
			noteList.remove(noteList.detect{ arg item; item[\id] == id });
			if(id == activeNoteId, {
				if(noteList.size > 0, {
					synthVoice.set(\freq, noteList.last.at(\freq));
					activeNoteId = noteList.last.at(\id);
				}, {
					synthVoice.set(\gate, 0);
					synthVoice.set(\killGate, 0);
					activeNoteId = nil;
					pauseRoutine.stop;
					startPauseRoutine.value;
				});
			});
		});

		this.addCommand(\noteKillAll, "", { arg msg;
			synthVoice.set(\gate, 0);
			synthVoice.set(\killGate, 0);
			activeNoteId = nil;
			noteList.clear;
			pauseRoutine.stop;
			startPauseRoutine.value;
		});

		this.addCommand(\pitchBend, "f", { arg msg;
			synthVoice.set(\pitchBendRatio, msg[1]);
		});

		this.addCommand(\glide, "f", { arg msg; synthVoice.set(\glide, msg[1]) });
		this.addCommand(\glideOn, "f", { arg msg; synthVoice.set(\glideOn, msg[1]) });
		this.addCommand(\osc1Wave, "i", { arg msg; synthVoice.set(\osc1Wave, msg[1]) });
		this.addCommand(\osc2Wave, "i", { arg msg; synthVoice.set(\osc2Wave, msg[1]) });
		this.addCommand(\osc1Level, "f", { arg msg; synthVoice.set(\osc1Level, msg[1]) });
		this.addCommand(\osc2Level, "f", { arg msg; synthVoice.set(\osc2Level, msg[1]) });
		this.addCommand(\osc1Pw, "f", { arg msg; synthVoice.set(\osc1Pw, msg[1]) });
		this.addCommand(\osc2Pw, "f", { arg msg; synthVoice.set(\osc2Pw, msg[1]) });
		this.addCommand(\osc1Pitch, "f", { arg msg; synthVoice.set(\osc1Pitch, msg[1]) });
		this.addCommand(\osc2Pitch, "f", { arg msg; synthVoice.set(\osc2Pitch, msg[1]) });
		this.addCommand(\osc1Octave, "f", { arg msg; synthVoice.set(\osc1Octave, msg[1]) });
		this.addCommand(\osc2Octave, "f", { arg msg; synthVoice.set(\osc2Octave, msg[1]) });
		this.addCommand(\osc1Detune, "f", { arg msg; synthVoice.set(\osc1Detune, msg[1]) });
		this.addCommand(\osc2Detune, "f", { arg msg; synthVoice.set(\osc2Detune, msg[1]) });
		this.addCommand(\fmAmount, "f", { arg msg; synthVoice.set(\fmAmount, msg[1]) });
		this.addCommand(\noiseLevel, "f", { arg msg; synthVoice.set(\noiseLevel, msg[1]) });
		this.addCommand(\lpCutoff, "f", { arg msg; synthVoice.set(\lpCutoff, msg[1]) });
		this.addCommand(\lpResonance, "f", { arg msg; synthVoice.set(\lpResonance, msg[1]) });
		this.addCommand(\lpEnvAmount, "f", { arg msg; synthVoice.set(\lpEnvAmount, msg[1]) });
		this.addCommand(\lpTracking, "f", { arg msg; synthVoice.set(\lpTracking, msg[1]) });
		this.addCommand(\filterAtk, "f", { arg msg; synthVoice.set(\filterAtk, msg[1]) });
		this.addCommand(\filterDec, "f", { arg msg; synthVoice.set(\filterDec, msg[1]) });
		this.addCommand(\filterSus, "f", { arg msg; synthVoice.set(\filterSus, msg[1]) });
		this.addCommand(\filterRel, "f", { arg msg; synthVoice.set(\filterRel, msg[1]) });
		this.addCommand(\filterEnvLinkAmp, "i", { arg msg; synthVoice.set(\filterEnvLinkAmp, msg[1]) });
		this.addCommand(\ampAtk, "f", { arg msg; synthVoice.set(\ampAtk, msg[1]) });
		this.addCommand(\ampDec, "f", { arg msg; synthVoice.set(\ampDec, msg[1]) });
		this.addCommand(\ampSus, "f", { arg msg; synthVoice.set(\ampSus, msg[1]) });
		this.addCommand(\ampRel, "f", { arg msg; synthVoice.set(\ampRel, msg[1]) });
		this.addCommand(\lfoRate, "f", { arg msg; lfo.set(\lfoRate, msg[1]) });
		this.addCommand(\lfoShape, "i", { arg msg; lfo.set(\lfoShape, msg[1]) });
		this.addCommand(\lfoMaster, "f", { arg msg;
			synthVoice.set(\lfoMaster, msg[1]);
			delayFx.set(\lfoMaster, msg[1]);
			reverbFx.set(\lfoMaster, msg[1]);
		});
		this.addCommand(\lfoOscAmt, "f", { arg msg; synthVoice.set(\lfoOscAmt, msg[1]) });
		this.addCommand(\lfoFilterAmt, "f", { arg msg; synthVoice.set(\lfoFilterAmt, msg[1]) });
		this.addCommand(\lfoFilterEnvAtkAmt, "f", { arg msg; synthVoice.set(\lfoFilterEnvAtkAmt, msg[1]) });
		this.addCommand(\lfoFilterEnvDecAmt, "f", { arg msg; synthVoice.set(\lfoFilterEnvDecAmt, msg[1]) });
		this.addCommand(\lfoFilterEnvSusAmt, "f", { arg msg; synthVoice.set(\lfoFilterEnvSusAmt, msg[1]) });
		this.addCommand(\lfoFilterEnvRelAmt, "f", { arg msg; synthVoice.set(\lfoFilterEnvRelAmt, msg[1]) });
		this.addCommand(\lfoAmpAmt, "f", { arg msg; synthVoice.set(\lfoAmpAmt, msg[1]) });
		this.addCommand(\lfoPwAmt, "f", { arg msg; synthVoice.set(\lfoPwAmt, msg[1]) });
		this.addCommand(\lfoDet1Amt, "f", { arg msg; synthVoice.set(\lfoDet1Amt, msg[1]) });
		this.addCommand(\lfoDet2Amt, "f", { arg msg; synthVoice.set(\lfoDet2Amt, msg[1]) });
		this.addCommand(\lfoNoiseAmt, "f", { arg msg; synthVoice.set(\lfoNoiseAmt, msg[1]) });
		this.addCommand(\lfoFmAmt, "f", { arg msg; synthVoice.set(\lfoFmAmt, msg[1]) });
		this.addCommand(\lfoGlideAmt, "f", { arg msg; synthVoice.set(\lfoGlideAmt, msg[1]) });
		this.addCommand(\lfoDriveAmt, "f", { arg msg; synthVoice.set(\lfoDriveAmt, msg[1]) });
		this.addCommand(\lfo2Rate, "f", { arg msg; lfo2.set(\lfoRate, msg[1]) });
		this.addCommand(\lfo2Shape, "i", { arg msg; lfo2.set(\lfoShape, msg[1]) });
		this.addCommand(\lfo2Master, "f", { arg msg;
			synthVoice.set(\lfo2Master, msg[1]);
			delayFx.set(\lfo2Master, msg[1]);
			reverbFx.set(\lfo2Master, msg[1]);
		});
		this.addCommand(\lfo2OscAmt, "f", { arg msg; synthVoice.set(\lfo2OscAmt, msg[1]) });
		this.addCommand(\lfo2FilterAmt, "f", { arg msg; synthVoice.set(\lfo2FilterAmt, msg[1]) });
		this.addCommand(\lfo2FilterEnvAtkAmt, "f", { arg msg; synthVoice.set(\lfo2FilterEnvAtkAmt, msg[1]) });
		this.addCommand(\lfo2FilterEnvDecAmt, "f", { arg msg; synthVoice.set(\lfo2FilterEnvDecAmt, msg[1]) });
		this.addCommand(\lfo2FilterEnvSusAmt, "f", { arg msg; synthVoice.set(\lfo2FilterEnvSusAmt, msg[1]) });
		this.addCommand(\lfo2FilterEnvRelAmt, "f", { arg msg; synthVoice.set(\lfo2FilterEnvRelAmt, msg[1]) });
		this.addCommand(\lfo2AmpAmt, "f", { arg msg; synthVoice.set(\lfo2AmpAmt, msg[1]) });
		this.addCommand(\lfo2PwAmt, "f", { arg msg; synthVoice.set(\lfo2PwAmt, msg[1]) });
		this.addCommand(\lfo2Det1Amt, "f", { arg msg; synthVoice.set(\lfo2Det1Amt, msg[1]) });
		this.addCommand(\lfo2Det2Amt, "f", { arg msg; synthVoice.set(\lfo2Det2Amt, msg[1]) });
		this.addCommand(\lfo2NoiseAmt, "f", { arg msg; synthVoice.set(\lfo2NoiseAmt, msg[1]) });
		this.addCommand(\lfo2FmAmt, "f", { arg msg; synthVoice.set(\lfo2FmAmt, msg[1]) });
		this.addCommand(\lfo2GlideAmt, "f", { arg msg; synthVoice.set(\lfo2GlideAmt, msg[1]) });
		this.addCommand(\lfo2DriveAmt, "f", { arg msg; synthVoice.set(\lfo2DriveAmt, msg[1]) });
		this.addCommand(\lfoDelayAmt, "f", { arg msg; delayFx.set(\lfoDelayAmt, msg[1]) });
		this.addCommand(\lfoReverbAmt, "f", { arg msg; reverbFx.set(\lfoReverbAmt, msg[1]) });
		this.addCommand(\lfo2DelayAmt, "f", { arg msg; delayFx.set(\lfo2DelayAmt, msg[1]) });
		this.addCommand(\lfo2ReverbAmt, "f", { arg msg; reverbFx.set(\lfo2ReverbAmt, msg[1]) });
		this.addCommand(\drive, "f", { arg msg; synthVoice.set(\drive, msg[1]) });
		this.addCommand(\delayTime, "f", { arg msg; delayFx.set(\time, msg[1]) });
		this.addCommand(\delayFeedback, "f", { arg msg; delayFx.set(\feedback, msg[1]) });
		this.addCommand(\delayMix, "f", { arg msg; delayFx.set(\mix, msg[1]) });
		this.addCommand(\delayFilter, "f", { arg msg; delayFx.set(\filterFc, msg[1]) });
		this.addCommand(\reverbMix, "f", { arg msg; reverbFx.set(\mix, msg[1]) });
		this.addCommand(\reverbRoom, "f", { arg msg; reverbFx.set(\room, msg[1]) });
		this.addCommand(\reverbDamp, "f", { arg msg; reverbFx.set(\damp, msg[1]) });
	}

}
