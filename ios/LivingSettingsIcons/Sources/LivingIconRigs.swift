import Foundation

// `RIGS` of prototype/src/settings/living-icons.js: every icon's motion, line for line —
// the same curves, constants, durations and effects. The parts they move are cut by LivingIconArtwork.
// Pure Swift: CI replays the web's golden frames through these (tools/golden-icons.mjs).

public enum LivingIconRigs {
    /// Premium: where its five arms fly out — the star's ten outline points (tips at 0, 2, …) and centre
    /// (living-icons.js `STAR_PTS`, `STAR_C`).
    public static let starPoints: [(Double, Double)] = [(15.0, 4.8), (18.0, 11.2), (25.0, 12.0), (19.8, 16.8), (21.2, 23.7), (15.0, 20.2), (8.8, 23.7), (10.2, 16.8), (5.0, 12.0), (12.0, 11.2)]
    public static let starCenter: (Double, Double) = (15.0, 15.24)
    /// Power Saving: the line the battery's charge jolts along on impact (a unit vector; the charge goes the other
    /// way, up and left: `BOLT_CUT`).
    public static let boltCut: (Double, Double) = (0.857, 0.514)

    /// The rigs by the prototype's icon name (`ic-bell`, …, `money`, `set-avatar`).
    public static let all: [String: LivingIconRig] = [
        "ic-bell": bell,
        "ic-phone": phone,
        "ic-folder": folder,
        "ic-saved": saved,
        "ic-data": data,
        "ic-devices": devices,
        "ic-lock": lock,
        "ic-profile": profile,
        "ic-proxy": proxy,
        "ic-stars": stars,
        "ic-premium": premium,
        "ic-power": power,
        "ic-language": language,
        "ic-gift": gift,
        "ic-business": business,
        "ic-ask": ask,
        "ic-faq": faq,
        "ic-features": features,
        "ic-appearance": appearance,
        "money": money,
        "set-emoji-status": emojiStatus,
        "set-avatar": avatar,
        "set-covercolor": coverColor,
    ]

    private typealias C = LivingIconCurves

    static let bell = LivingIconRig(duration: 1.15) { t, P, fx, _ in
        let a = C.ring(t, 22.0, 3.2, 3.6)
        P.body.set(r: a, cx: 15.0, cy: 5.6)
        // The clapper hangs from the same pivot and lags behind the bell.
        let c = C.ring(t, 30.0, 3.2, 3.2, 0.05)
        P.clapper.set(r: c, cx: 15.0, cy: 5.6)
        // The badge swells on the first swing and settles with a little wobble.
        let d = 1.0 + 0.36 * C.bump(t, 0.08, 0.26) + C.ring(t, 0.07, 5.0, 8.0, 0.34)
        P.dot.set(sx: d, sy: d, cx: 20.5, cy: 9.5)
        fx.waves(t, 0.06, 2)
    }

    // Cut across the middle of its handle: the two ends shake against each other.
    static let phone = LivingIconRig(duration: 1.0) { t, P, fx, _ in
        let on: Double = t < 0.7 ? 1.0 : 0.0
        let buzz = sin(2.0 * Double.pi * 13.0 * t) * 14.0 * exp(-3.4 * t) * on
        P.handset.set(r: buzz, sx: 1.0 + 0.08 * exp(-6.0 * t), sy: 1.0 + 0.08 * exp(-6.0 * t), cx: 15.0, cy: 15.0)
        // The ends, a quarter-beat apart: the earpiece and the mouthpiece rattle in turn.
        let flex = cos(2.0 * Double.pi * 13.0 * t) * 7.0 * exp(-3.8 * t) * on
        P.ear.set(r: flex, cx: 11.95, cy: 18.03)
        P.mouth.set(r: -flex, cx: 11.95, cy: 18.03)
        fx.waves(t, 0.0, 3)
    }

    static let folder = LivingIconRig(duration: 1.0, flags: [.paper]) { t, P, fx, _ in
        // The flap swings open (foreshortened about its bottom hinge) and falls back with a bounce.
        let open = t < 0.22 ? C.easeOut(t / 0.22) : 1.0 - C.pop(t, 0.42, 0.22, 0.42)
        P.front.set(sy: 1.0 - 0.45 * open, kx: -14.0 * open, cx: 15.0, cy: 23.0)
        fx.paper(open)
    }

    static let saved = LivingIconRig(duration: 1.05) { t, P, _, E in
        // Lifted, dropped in with bounces and a squash…
        let y = C.hopDrop(t, 9.0, 0.0, 0.1)
        let land = 0.1 + sqrt((2.0 * 9.0) / 2200.0)
        let squash = t > land - 0.01 ? max(0.0, 1.0 - abs(y) / 1.2) * exp(-5.0 * (t - 0.1)) : 0.0
        P.mark.set(y: y, sx: 1.0 + 0.08 * squash, sy: 1.0 - 0.14 * squash, cx: 15.0, cy: 23.0)
        // …and its ribbon end flaps as it lands: the tails swing down and out, the notch snaps up.
        E.bookmark(C.ring(t, -2.2, 4.6, 6.5, land), C.ring(t, 0.7, 4.6, 6.5, land), C.ring(t, 1.3, 4.6, 6.5, land))
    }

    static let data = LivingIconRig(duration: 1.0) { t, P, _, _ in
        for (name, t0) in [("top", 0.0), ("middle", 0.07), ("bottom", 0.14)] {
            let u = t - t0
            let y = u < 0.0 ? 0.0 : -3.2 * sin(Double.pi * C.clamp(u / 0.26)) + C.ring(u, 0.9, 4.0, 7.0, 0.26)
            // Each disk lands with a squash.
            let sq = u > 0.26 ? 0.1 * exp(-12.0 * (u - 0.26)) : 0.0
            P[name].set(y: y, sx: 1.0 + 0.5 * sq, sy: 1.0 - sq, cx: 15.0, cy: name == "top" ? 12.0 : name == "middle" ? 18.0 : 24.0)
        }
    }

    static let devices = LivingIconRig(duration: 1.0) { t, P, fx, _ in
        P.laptop.set(y: -3.0 * sin(Double.pi * C.clamp(t / 0.24)) + C.ring(t, 0.8, 4.0, 7.0, 0.24))
        // The laptop's lid shuts on its hinge and springs open again.
        P.screen.set(sy: 1.0 - 0.72 * C.bump(t, 0.02, 0.3) + C.ring(t, 0.07, 4.5, 7.0, 0.32), cx: 9.85, cy: 18.66)
        P.phone.set(r: C.ring(t, 8.0, 3.0, 5.0, 0.12), y: -3.4 * sin(Double.pi * C.clamp((t - 0.12) / 0.24)) + C.ring(t, 0.8, 4.0, 7.0, 0.36), cx: 20.0, cy: 22.0)
        fx.glow(t, 0.15, 0.5)
    }

    static let lock = LivingIconRig(duration: 1.2) { t, P, fx, _ in
        // The lock hops; in the air its shackle springs up out of the body and swings open on its long
        // leg, holds, then swings back and slams down: a click (the body squashes, the shackle bounces)
        // and a glint.
        let lift = t < 0.16 ? -3.0 * C.easeOut(t / 0.16) : -3.0 + 3.0 * C.pop(t, 0.2, 0.16, 0.55)
        let shut = 1.0 - C.easeIn((t - 0.56) / 0.11)
        let rise = -2.7 * C.pop(t, 0.22, 0.03, 0.6) * shut + C.ring(t, -0.7, 7.0, 11.0, 0.67)
        let swing = -28.0 * C.pop(t, 0.34, 0.14, 0.5) * shut
        let click = t > 0.67 ? exp(-13.0 * (t - 0.67)) : 0.0
        P.lock.set(y: lift + 0.6 * click, cx: 15.0, cy: 25.0)
        P.shackle.set(r: swing, y: rise, cx: 10.0, cy: 15.6)
        P.body.set(sx: 1.0 + 0.06 * click, sy: 1.0 - 0.1 * click, cx: 15.0, cy: 25.0)
        fx.glint(t, 0.64)
    }

    static let profile = LivingIconRig(duration: 1.05) { t, P, fx, _ in
        let y = -3.4 * sin(Double.pi * C.clamp(t / 0.26)) + C.ring(t, 0.7, 4.0, 7.0, 0.26)
        P.profile.set(y: y, cx: 15.0, cy: 25.0)
        fx.halo(t, 0.05)
        // The person ducks, pops back up (the head a beat later, overshooting) and nods.
        let duck: (Double, Double, Double, Double) -> Double = { d, t0, r, z in
            return t < t0 ? d * C.easeIn(t / t0) : d * (1.0 - C.pop(t, r, t0, z))
        }
        P.bust.set(y: duck(3.4, 0.12, 0.36, 0.42))
        let hs = 1.0 + 0.12 * C.bump(t, 0.22, 0.26)
        P.head.set(r: C.ring(t, 10.0, 2.3, 4.2, 0.46), y: duck(4.8, 0.15, 0.34, 0.36), sx: hs, sy: hs, cx: 15.0, cy: 15.6)
    }

    static let proxy = LivingIconRig(duration: 1.05) { t, P, fx, _ in
        let s = 1.0 + 0.16 * sin(Double.pi * C.clamp(t / 0.3)) * (1.0 - C.clamp((t - 0.3) / 0.4))
        P.shield.set(sx: s, sy: s, cx: 15.0, cy: 15.0)
        // Out one side, back in from the other (hidden behind the rim on the way round).
        let run: (Double, Double) -> Double = { t0, sign in
            let u = C.clamp((t - t0) / 0.46)
            var x = 24.0 * C.ease(u)
            if x > 12.0 {
                x -= 24.0
            }
            return sign * x
        }
        P.right.set(x: run(0.08, 1.0))
        P.left.set(x: run(0.18, -1.0))
        fx.glint(t, 0.12)
    }

    static let stars = LivingIconRig(duration: 1.1) { t, P, fx, _ in
        // A full turn (the star isn't symmetric: it ends where it began) with a pop, the disc giving under it.
        let turn = 360.0 * C.easeOut(t / 0.62) + C.ring(t, 8.0, 2.5, 6.0, 0.62)
        let s = 1.0 + 0.22 * C.bump(t, 0.0, 0.42) + C.ring(t, 0.05, 3.0, 6.0, 0.42)
        P.star.set(r: turn, sx: s, sy: s, cx: 15.0, cy: 14.6)
        let d = 1.0 - 0.05 * C.bump(t, 0.0, 0.16) + 0.04 * C.bump(t, 0.16, 0.24)
        P.disc.set(sx: d, sy: d, cx: 15.0, cy: 15.0)
        fx.sparkles(t, 0.1, 5, 0xffe9a8)
    }

    // Telegram's star as its core and five arms: the arms fly out while it spins and snap back.
    static let premium = LivingIconRig(duration: 1.15, flags: [.spin3d]) { t, P, fx, _ in
        fx.spin3d(t, 0.0, 0.7)
        for i in 0 ..< 5 {
            let tip = starPoints[2 * i]
            let dx = tip.0 - starCenter.0
            let dy = tip.1 - starCenter.1
            let l = hypot(dx, dy)
            let out = 1.9 * C.bump(t, 0.06 + Double(i) * 0.035, 0.42) + C.ring(t, 0.35, 4.0, 8.0, 0.48 + Double(i) * 0.035)
            P["arm\(i)"].set(x: (dx / l) * out, y: (dy / l) * out)
        }
        let k = 1.0 - 0.14 * C.bump(t, 0.06, 0.4)
        P.core.set(sx: k, sy: k, cx: starCenter.0, cy: starCenter.1)
        fx.sparkles(t, 0.12, 7, 0xffffff)
    }

    static let power = LivingIconRig(duration: 0.95) { t, P, fx, _ in
        // Raised, then it strikes; on impact its charge jolts out of place and snaps back (twice, the
        // second smaller).
        let strike = t < 0.06 ? -4.0 * C.easeOut(t / 0.06) : t < 0.13 ? -4.0 + 4.0 * ((t - 0.06) / 0.07) : C.ring(t, 1.2, 6.0, 9.0, 0.13)
        let s = 1.0 + 0.22 * exp(-7.0 * max(0.0, t - 0.06)) * (t < 0.06 ? t / 0.06 : 1.0)
        P.bolt.set(y: strike, sx: s, sy: s, cx: 15.0, cy: 15.0)
        let crack = 1.5 * C.bump(t, 0.13, 0.12) + 0.7 * C.bump(t, 0.27, 0.1)
        P.top.set(x: -boltCut.0 * crack, y: -boltCut.1 * crack)
        P.bottom.set(x: boltCut.0 * crack, y: boltCut.1 * crack)
        fx.glow(t, 0.1, 0.42)
        fx.sparkles(t, 0.12, 4, 0xfff3b0)
    }

    static let language = LivingIconRig(duration: 1.15, flags: [.globe]) { t, _, fx, _ in
        fx.globe(C.easeOut(t / 1.05))
    }

    static let gift = LivingIconRig(duration: 1.1) { t, P, fx, _ in
        let up = t < 0.16 ? C.easeOut(t / 0.16) : 1.0 - C.pop(t, 0.3, 0.16, 0.45)
        P.lid.set(r: -9.0 * up, y: -4.5 * up, cx: 23.8, cy: 15.2)
        P.bow.set(r: -9.0 * up + C.ring(t, 10.0, 4.0, 5.0, 0.2), y: -5.5 * up, cx: 23.8, cy: 15.2)
        fx.confetti(t, 0.1)
    }

    static let business = LivingIconRig(duration: 1.0) { t, P, _, _ in
        let y = -3.0 * sin(Double.pi * C.clamp(t / 0.24)) + C.ring(t, 0.8, 4.0, 7.0, 0.24)
        P["case"].set(r: C.ring(t, 9.0, 3.4, 4.5, 0.05), y: y, cx: 15.0, cy: 8.0)
        // At the top of the hop the awning pops open a crack, and it snaps shut as the shop lands.
        let open = C.bump(t, 0.06, 0.22)
        let snap = t > 0.28 ? exp(-14.0 * (t - 0.28)) : 0.0
        P.lid.set(r: -5.0 * open, y: -1.7 * open, cx: 6.0, cy: 15.0)
        P.base.set(sx: 1.0 + 0.04 * snap, sy: 1.0 - 0.08 * snap, cx: 15.0, cy: 23.3)
    }

    static let ask = LivingIconRig(duration: 1.2, flags: [.dots]) { t, P, fx, _ in
        let s = 0.82 + 0.18 * C.pop(t, 0.3, 0.0, 0.45)
        // A jelly wobble as it lands (wider, then taller).
        let w = C.ring(t, 0.07, 3.6, 5.5, 0.18)
        P.bubble.set(sx: s * (1.0 + w), sy: s * (1.0 - w), cx: 9.0, cy: 22.0)
        fx.dots(t, 0.18)
    }

    static let faq = LivingIconRig(duration: 1.1) { t, P, _, _ in
        // The question mark writes itself again (undrawn and drawn along its stroke), then wobbles; the dot
        // hops and drops back in.
        let d = t < 0.12 ? C.easeIn(t / 0.12) : 1.0 - C.easeOut((t - 0.12) / 0.32)
        P.mark.dash(d)
        P.mark.set(r: C.ring(t, 16.0, 2.8, 4.2, 0.4), cx: 15.2, cy: 19.0)
        P.dot.set(y: C.hopDrop(t, 4.0, 0.3, 0.08))
    }

    static let features = LivingIconRig(duration: 1.05) { t, P, fx, E in
        let r = C.ring(t, 9.0, 2.6, 4.4)
        P.lamp.set(r: r, cx: 15.0, cy: 4.0)
        // The bulb swells as it lights; the base screws itself in (squeezes as it turns).
        let glow = C.bump(t, 0.05, 0.5)
        P.bulb.set(sx: 1.0 + 0.06 * glow, sy: 1.0 + 0.06 * glow, cx: 15.0, cy: 11.0)
        let turn = abs(sin(2.0 * Double.pi * 3.0 * C.clamp((t - 0.04) / 0.5))) * (1.0 - C.clamp((t - 0.04) / 0.5))
        P.base.set(y: -0.5 * turn, sx: 1.0 - 0.22 * turn, cx: 15.0, cy: 22.7)
        let drawn = C.easeOut((t - 0.12) / 0.25)
        E.shine(dashOffset: 1.0 - drawn, opacity: drawn <= 0.001 ? 0.0 : 1.0 - C.clamp((t - 0.6) / 0.3))
        fx.glow(t, 0.05, 0.6)
        fx.rays(t, 0.1)
    }

    static let appearance = LivingIconRig(duration: 1.05) { t, P, fx, _ in
        // A brush stroke: wind up, paint, settle — the dial swings, its half disc trailing; a stroke of
        // paint under it.
        let a = t < 0.14 ? -18.0 * C.easeOut(t / 0.14) : -18.0 + 30.0 * C.easeOut((t - 0.14) / 0.2) - 12.0 * C.pop(t, 0.3, 0.34, 0.5)
        P.brush.set(r: a, cx: 12.0, cy: 18.0)
        let lag = t < 0.14 ? 10.0 * C.easeOut(t / 0.14) : 10.0 - 26.0 * C.easeOut((t - 0.14) / 0.2) + 16.0 * C.pop(t, 0.34, 0.34, 0.32)
        let press = C.bump(t, 0.2, 0.22)
        P.tip.set(r: lag, sx: 1.0 + 0.12 * press, sy: 1.0 - 0.1 * press, cx: 13.4, cy: 16.4)
        fx.stroke(t, 0.2)
    }

    // Telegram's gem (a bitmap): the element itself turns.
    static let money = LivingIconRig(duration: 1.1, flags: [.element]) { t, _, fx, E in
        fx.spin3d(t, 0.0, 0.75)
        // The sparkle inside it turns a quarter and flares as the gem comes round.
        let s = 1.0 + 0.45 * C.bump(t, 0.25, 0.45)
        E.inner(rotation: 90.0 * C.easeOut((t - 0.2) / 0.6), scale: s)
        fx.sparkles(t, 0.15, 6, 0xbfe6ff)
    }

    static let emojiStatus = LivingIconRig(duration: 1.0) { t, P, _, _ in
        let blink = t > 0.18 && t < 0.42 ? 1.0 - sin(Double.pi * (t - 0.18) / 0.24) * 0.9 : 1.0
        let y = -2.4 * sin(Double.pi * C.clamp(t / 0.24)) + C.ring(t, 0.6, 4.0, 7.0, 0.24)
        P.leftEye.set(y: y, cx: 19.0, cy: 12.7)
        P.rightEye.set(y: y, sy: blink, cx: 19.0, cy: 12.7)
        P.face.set(y: y)
        // The smile widens with the wink…
        let grin = 0.18 * C.bump(t, 0.16, 0.34)
        P.smile.set(y: y + 0.4 * grin, sx: 1.0 + grin, sy: 1.0 + 0.6 * grin, cx: 15.0, cy: 18.5)
        // …and the pencil scribbles (pivoting on its point, sliding along its length).
        let u = t - 0.22
        let w = u > 0.0 ? sin(2.0 * Double.pi * 3.4 * u) * exp(-3.2 * u) : 0.0
        P.pencil.set(r: 9.0 * w, x: 0.6 * w, y: y - 0.6 * w, cx: 16.6, cy: 29.2)
    }

    static let avatar = LivingIconRig(duration: 1.0) { t, P, fx, _ in
        let s = 1.0 - 0.1 * sin(Double.pi * C.clamp(t / 0.16)) + C.ring(t, 0.04, 4.0, 6.0, 0.16)
        P.camera.set(sx: s, sy: s, cx: 15.0, cy: 15.0)
        // The shot: the lens zooms in and back, the flash bulb fires, and the plus spins in.
        let z = 1.0 - 0.18 * C.bump(t, 0.0, 0.14) + 0.14 * C.bump(t, 0.12, 0.2) + C.ring(t, 0.03, 4.0, 7.0, 0.32)
        P.lens.set(sx: z, sy: z, cx: 15.0, cy: 15.3)
        let f = 1.0 + 0.9 * C.bump(t, 0.08, 0.2)
        P.flash.set(sx: f, sy: f, cx: 22.5, cy: 11.25)
        let p = 1.0 + 0.25 * C.bump(t, 0.12, 0.3)
        P.plus.set(r: 90.0 * C.pop(t, 0.36, 0.12, 0.5), sx: p, sy: p, cx: 5.5, cy: 22.0)
        fx.flash(t, 0.1)
    }

    static let coverColor = LivingIconRig(duration: 1.15, flags: [.hue]) { t, P, fx, _ in
        P.palette.set(r: C.ring(t, 12.0, 2.4, 4.0), cx: 15.0, cy: 15.0)
        // The photo pops, the name bar slides out under it and the sparkles twinkle in turn.
        let a = 1.0 + 0.16 * C.bump(t, 0.04, 0.3) + C.ring(t, 0.03, 4.0, 7.0, 0.34)
        P.avatar.set(sx: a, sy: a, cx: 15.0, cy: 13.5)
        P.bar.set(sx: 0.55 + 0.45 * C.pop(t, 0.34, 0.1, 0.55), cx: 15.25, cy: 20.5)
        for (k, cx, cy, t0) in [("s1", 6.5, 6.5, 0.1), ("s2", 25.0, 12.0, 0.2), ("s3", 11.0, 25.0, 0.3)] {
            let v = 1.0 - 0.85 * C.bump(t, t0, 0.12) + (t > t0 + 0.12 ? 0.5 * C.bump(t, t0 + 0.12, 0.24) : 0.0)
            P[k].set(r: 90.0 * C.easeOut((t - t0) / 0.4), sx: v, sy: v, cx: cx, cy: cy)
        }
        fx.hue(t, 0.95)
    }
}
