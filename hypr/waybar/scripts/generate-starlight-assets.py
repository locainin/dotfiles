#!/usr/bin/env python3
"""
Generate transparent PNG assets for a Waybar "starlight headliner" effect.

Outputs (relative to this directory's parent):
- assets/starlight_base.png              : faint always-on starfield (single frame)
- assets/starlight_twinkle_sheet.png     : sprite sheet of twinkle-only frames (vertical strip)
- assets/starlight_sheet.png             : sprite sheet of base+twinkle frames (vertical strip)

The images are transparent everywhere except for the stars so the bar background can remain
fully invisible while stars render as a subtle overlay.
"""

from __future__ import annotations

import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


# Frames are stacked vertically in the final sprite sheet to avoid Cairo pattern-size limits that
# can be hit when scaling very wide horizontal sprite sheets across large center spans.
# Render width is independent of the center span width; GTK scales to the widget width.
#
# Rendering close to the output width reduces upscaling artifacts, improving the "premium" look
# without increasing runtime redraw cost (assets are generated offline).
FRAME_WIDTH = 2560
# Render taller than the bar and let GTK scale down; downsampling keeps stars crisp instead of
# turning into soft blobs.
FRAME_HEIGHT = 60
# Frame 0 is duplicated as the final frame for seamless looping.
FRAME_COUNT = 120
# Keep animation timing centralized so sprite scheduling stays consistent with CSS.
# This value must match the `animation-duration` configured in `style.css`.
ANIMATION_DURATION_SECONDS = 18.0

# Star density and brightness tuning.
# Keep the base layer light; depth should not read as a translucent bar.
# Base stars should be sparse to avoid reading as a textured bar.
# Increased density for a richer center strip while keeping the bar visually transparent.
BASE_STAR_COUNT = 240
# Left-side supplementation keeps the strip dense near the left chevron without widening the strip.
# Implemented as an additive overlay so the existing starfield stays stable.
BASE_STAR_EXTRA_LEFT = 40
# Small right-side supplementation to avoid frames where the right portion reads as empty once
# twinkles fade out.
BASE_STAR_EXTRA_RIGHT = 26
# Balance pass to avoid large empty horizontal bands; values are conservative to preserve the
# existing look while guaranteeing some always-on stars in each region.
BASE_BIN_COUNT = 10
BASE_MIN_STARS_PER_BIN = 14
BASE_BALANCE_MAX_TOTAL = 24
# Twinkle stars are sparse; per-star intensity is animated across the sprite sheet frames.
# Increase density rather than increasing animation step rate to keep CPU usage stable.
# Elevated twinkle density for a fuller shimmer without increasing frame rate.
TWINKLE_STAR_COUNT = 420
# Left-side supplementation for twinkles to close the visible gap near the left edge.
TWINKLE_STAR_EXTRA_LEFT = 48
#
# Right-side supplementation mirrors the left-side padding. This exists primarily to avoid frames
# where the right portion of the center span reads as empty once the random twinkles fade out.
TWINKLE_STAR_EXTRA_RIGHT = 28
#
# "Anchor" twinkles:
# - stable star positions that are scheduled across time so each side of the clock always has
#   some twinkling activity
# - not "always-on" pixels; each anchor follows a fade-in / fade-out envelope
TWINKLE_ANCHOR_STARS_PER_SIDE = 22
# Keep anchors more separated than normal twinkles to avoid "snow" clumping.
TWINKLE_ANCHOR_MIN_DIST_PX = 22.0
#
# "Macro" twinkles:
# - larger/brighter twinkles (still fading in/out) to provide a premium "hero star" mix
# - kept sparse and highly separated to avoid a "snow" look
TWINKLE_MACRO_STARS_PER_SIDE = 10
TWINKLE_MACRO_MIN_DIST_PX = 40.0
#
# "Micro" twinkles:
# - low-intensity, small-radius twinkles spread across the full strip
# - increases perceived smoothness by reducing large per-frame brightness deltas
TWINKLE_MICRO_STAR_COUNT = 340
#
# Rare "sparkle" twinkles:
# - extremely sparse and subtle (long envelope) so the effect reads as occasional premium glints
# - implemented as a small flare on top of the normal twinkle core/glow
TWINKLE_SPARKLE_STAR_COUNT = 10
TWINKLE_SPARKLE_MIN_DIST_PX = 34.0

# Prevent clustered points which read as "snow" in low-height strips.
BASE_MIN_DIST_PX = 10.0
TWINKLE_MIN_DIST_PX = 13.0


# Subtle edge fade (baked into the sprite) keeps the strip from reading as a hard rectangle while
# remaining compatible with a fully transparent `window#waybar` background.
EDGE_FADE_STRENGTH = 0.18  # 0.0 disables the fade; 1.0 applies the full smoothstep curve.

# Seed is fixed for stable visuals across regenerations.
BASE_SEED = 1731


def _edge_fade_alpha(x01: float) -> float:
    """
    Fade star alpha towards the edges (x01 in [0, 1]).
    """

    if EDGE_FADE_STRENGTH <= 0.0:
        return 1.0

    # Smoothstep from center to edges; keeps the middle slightly stronger.
    dist = abs(x01 - 0.5) * 2.0  # 0 at center, 1 at edges
    fade = 1.0 - (dist * dist * (3.0 - 2.0 * dist))  # smoothstep
    return 1.0 - EDGE_FADE_STRENGTH * (1.0 - fade)


def _poisson_sample(
    *,
    rng: random.Random,
    count: int,
    width: int,
    height: int,
    min_dist_px: float,
    max_attempts: int,
    existing_points: list[tuple[float, float]] | None = None,
    x_min: float | None = None,
    x_max: float | None = None,
    y_min: float | None = None,
    y_max: float | None = None,
) -> list[tuple[float, float]]:
    """
    Sample points with a minimum separation using a grid-accelerated rejection loop.

    This avoids clustered points which read as "snow" in low-height strips.
    """

    if count <= 0:
        return []

    x_lo = 0.0 if x_min is None else max(0.0, x_min)
    x_hi = float(width - 1) if x_max is None else min(float(width - 1), x_max)
    y_lo = 0.0 if y_min is None else max(0.0, y_min)
    y_hi = float(height - 1) if y_max is None else min(float(height - 1), y_max)
    if x_hi <= x_lo or y_hi <= y_lo:
        return []

    cell_size = min_dist_px / math.sqrt(2.0)
    grid_w = int(math.ceil(width / cell_size))
    grid_h = int(math.ceil(height / cell_size))
    grid: list[list[int]] = [[] for _ in range(grid_w * grid_h)]
    points: list[tuple[float, float]] = []
    min_dist_sq = min_dist_px * min_dist_px

    def grid_index(x: float, y: float) -> tuple[int, int]:
        return int(x / cell_size), int(y / cell_size)

    def fits(x: float, y: float) -> bool:
        gx, gy = grid_index(x, y)
        for yy in range(max(0, gy - 2), min(grid_h, gy + 3)):
            row = yy * grid_w
            for xx in range(max(0, gx - 2), min(grid_w, gx + 3)):
                for idx in grid[row + xx]:
                    px, py = points[idx]
                    dx = x - px
                    dy = y - py
                    if dx * dx + dy * dy < min_dist_sq:
                        return False
        return True

    if existing_points:
        for x, y in existing_points:
            # Clamp to the valid bounds; defensive against rounding drift in callers.
            x = max(0.0, min(float(width - 1), x))
            y = max(0.0, min(float(height - 1), y))
            points.append((x, y))
            gx, gy = grid_index(x, y)
            grid[gy * grid_w + gx].append(len(points) - 1)

    target_total = count + (len(existing_points) if existing_points else 0)

    for _ in range(max_attempts):
        if len(points) >= target_total:
            break
        x = rng.uniform(x_lo, x_hi)
        y = rng.uniform(y_lo, y_hi)
        if not fits(x, y):
            continue
        points.append((x, y))
        gx, gy = grid_index(x, y)
        grid[gy * grid_w + gx].append(len(points) - 1)

    # If sampling cannot reach target density, return best effort rather than forcing clumps.
    if not existing_points:
        return points

    # Strip the pre-seeded points before returning; callers only need newly sampled points.
    return points[len(existing_points) :]


def _draw_starfield(
    *,
    rng: random.Random,
    count: int,
    base_alpha: int,
    tint_rgb: tuple[int, int, int],
    width: int,
    height: int,
    min_dist_px: float,
    points: list[tuple[float, float]] | None = None,
) -> Image.Image:
    """
    Draw a star layer with soft glow on a transparent canvas.
    """

    canvas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    glow = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw_canvas = ImageDraw.Draw(canvas)
    draw_glow = ImageDraw.Draw(glow)

    if points is None:
        points = _poisson_sample(
            rng=rng,
            count=count,
            width=width,
            height=height,
            min_dist_px=min_dist_px,
            max_attempts=count * 2500,
        )

    for x_f, y_f in points:
        x01 = x_f / max(1.0, (width - 1.0))
        x = int(round(x_f))
        y = int(round(y_f))

        fade = _edge_fade_alpha(x01)
        alpha = int(base_alpha * rng.uniform(0.55, 1.0) * fade)
        if alpha <= 0:
            continue

        # Mild cool tint variation keeps stars from reading as uniform noise.
        r = min(255, tint_rgb[0] + rng.randint(-10, 10))
        g = min(255, tint_rgb[1] + rng.randint(-10, 10))
        b = min(255, tint_rgb[2] + rng.randint(-5, 5))

        size_roll = rng.random()
        if size_roll < 0.95:
            core_r = 0
            glow_r = rng.choice([1, 1, 1, 2])
        elif size_roll < 0.995:
            core_r = 1
            glow_r = rng.choice([2, 2, 2, 3])
        else:
            core_r = 1
            glow_r = 3

        glow_alpha = min(14, int(alpha * 0.60))
        core_alpha = min(255, int(alpha * (2.1 if core_r == 0 else 1.5)))

        draw_glow.ellipse(
            (x - glow_r, y - glow_r, x + glow_r, y + glow_r),
            fill=(r, g, b, glow_alpha),
        )

        if core_r == 0:
            draw_canvas.point((x, y), fill=(r, g, b, core_alpha))
        else:
            draw_canvas.ellipse(
                (x - core_r, y - core_r, x + core_r, y + core_r),
                fill=(r, g, b, core_alpha),
            )

    # A small blur produces a soft star bloom while minimizing background haze.
    glow = glow.filter(ImageFilter.GaussianBlur(radius=0.75))
    merged = Image.alpha_composite(glow, canvas)
    return merged


def _write_png(path: Path, image: Image.Image) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG", optimize=True)


def _render_twinkle_frames(
    *,
    seed: int,
    points: list[tuple[float, float]],
    kinds: dict[tuple[int, int], str] | None = None,
) -> list[Image.Image]:
    """
    Render twinkle frames (single-frame images).

    Each star has a stable position and a per-frame intensity curve, which produces a BMW-like
    "fade up / fade down" twinkle rather than a hard on/off flicker.
    """

    rng = random.Random(seed)

    # Twinkle star specifications (stable positions; per-frame intensity is computed below).
    #
    # This uses plain tuples to keep the generator dependency-free.
    #
    # tuple: (x01, y01, events, peak_alpha, glow_radius_px, power, kind)
    # - events: list of (center_t, half_width_t) in normalized time [0, 1]
    # - kind:
    #   - "normal": standard core + glow
    #   - "sparkle": standard core + glow + subtle flare
    #   - "macro": larger/brighter hero stars (still fading in/out)
    stars: list[tuple[float, float, list[tuple[float, float]], int, int, float, str]] = []

    def add_random_twinkles(*, pts: list[tuple[float, float]], kind: str, style: str) -> None:
        """
        Add twinkle stars with randomized envelopes.

        `kind` selects conservative presets:
        - "main": primary visible twinkles
        - "micro": low-intensity twinkles used to reduce perceived stepping without increasing
          the animation step rate
        """

        for x_f, y_f in pts:
            x01 = x_f / max(1.0, (FRAME_WIDTH - 1.0))
            y01 = y_f / max(1.0, (FRAME_HEIGHT - 1.0))

            if kind == "micro":
                # Micro twinkles are intentionally subtle and long-lived.
                event_count = 1 if rng.random() < 0.82 else 2
                half_width_lo, half_width_hi = 0.18, 0.34
                peak_lo, peak_hi = 120, 190
                power_lo, power_hi = 1.0, 1.6
                glow_choices = [1, 1, 1, 2]
            else:
                # Main twinkles should fade in/out smoothly (no hard flicker), but remain sparse.
                event_count = 1 if rng.random() < 0.66 else 2
                # Wider envelopes reduce large per-frame brightness deltas at the same step rate.
                half_width_lo, half_width_hi = 0.11, 0.26
                peak_lo, peak_hi = 215, 255
                # Lower power flattens the curve slightly, reducing "popping" at frame boundaries.
                power_lo, power_hi = 1.25, 2.05
                # Bias toward smaller glows to avoid "snow" blobs on dark wallpapers.
                glow_choices = [1, 1, 1, 2, 2]

            events: list[tuple[float, float]] = []
            for _ in range(event_count):
                center_t = rng.uniform(0.0, 1.0)
                half_width_t = rng.uniform(half_width_lo, half_width_hi)
                events.append((center_t, half_width_t))

            peak_alpha = rng.randint(peak_lo, peak_hi)
            glow_r = rng.choice(glow_choices)
            power = rng.uniform(power_lo, power_hi)
            stars.append((x01, y01, events, peak_alpha, glow_r, power, style))

    # Anchor twinkles: enforce steady activity on both sides of the clock without creating any
    # permanently visible stars.
    #
    # This is achieved by distributing envelope centers across the full loop for each side so the
    # overlap guarantees that at least a few anchors are active at any given time.
    def add_anchor_twinkles(*, pts: list[tuple[float, float]], phase_seed: int) -> None:
        if not pts:
            return

        local_rng = random.Random(phase_seed)
        n = len(pts)
        # Evenly spaced centers with small jitter avoids a periodic look while preventing gaps.
        base_centers = [(i / float(n)) for i in range(n)]
        local_rng.shuffle(base_centers)

        for (x_f, y_f), base_center in zip(pts, base_centers, strict=False):
            x01 = x_f / max(1.0, (FRAME_WIDTH - 1.0))
            y01 = y_f / max(1.0, (FRAME_HEIGHT - 1.0))

            center_t = (base_center + local_rng.uniform(-0.02, 0.02)) % 1.0
            half_width_t = local_rng.uniform(0.16, 0.28)
            peak_alpha = local_rng.randint(180, 240)
            glow_r = local_rng.choice([1, 1, 2])
            power = local_rng.uniform(1.1, 1.8)
            stars.append((x01, y01, [(center_t, half_width_t)], peak_alpha, glow_r, power, "normal"))

    def add_macro_twinkles(*, pts: list[tuple[float, float]], phase_seed: int) -> None:
        """
        Add sparse hero stars with larger glows that still fade in/out.
        """

        if not pts:
            return

        local_rng = random.Random(phase_seed)
        n = len(pts)
        base_centers = [(i / float(n)) for i in range(n)]
        local_rng.shuffle(base_centers)

        for (x_f, y_f), base_center in zip(pts, base_centers, strict=False):
            x01 = x_f / max(1.0, (FRAME_WIDTH - 1.0))
            y01 = y_f / max(1.0, (FRAME_HEIGHT - 1.0))

            center_t = (base_center + local_rng.uniform(-0.03, 0.03)) % 1.0
            half_width_t = local_rng.uniform(0.22, 0.36)
            peak_alpha = local_rng.randint(220, 255)
            glow_r = 3
            power = local_rng.uniform(1.05, 1.55)
            stars.append((x01, y01, [(center_t, half_width_t)], peak_alpha, glow_r, power, "macro"))

    # Partition points into roles.
    # - Points are pre-sampled with minimum separation to avoid clustered "snow".
    # - Certain points are explicitly sampled for anchors/macros/sparkles in `main()`; those are
    #   provided via `kinds` to keep scheduling stable and prevent accidental duplication.
    # - Keys are rounded integer coordinates so the mapping is stable across floating-point
    #   representation and independent of list ordering.
    kinds = kinds or {}

    anchor_left: list[tuple[float, float]] = []
    anchor_right: list[tuple[float, float]] = []
    macro_left: list[tuple[float, float]] = []
    macro_right: list[tuple[float, float]] = []
    sparkle_points: list[tuple[float, float]] = []
    other_points: list[tuple[float, float]] = []

    pts = points[:]
    rng.shuffle(pts)

    for x_f, y_f in pts:
        key = (int(round(x_f)), int(round(y_f)))
        kind = kinds.get(key)
        x01 = x_f / max(1.0, (FRAME_WIDTH - 1.0))

        if kind == "sparkle":
            sparkle_points.append((x_f, y_f))
        elif kind == "macro":
            if x01 <= 0.5:
                macro_left.append((x_f, y_f))
            else:
                macro_right.append((x_f, y_f))
        elif kind == "anchor":
            if x01 <= 0.5:
                anchor_left.append((x_f, y_f))
            else:
                anchor_right.append((x_f, y_f))
        else:
            other_points.append((x_f, y_f))

    # Micro twinkles: reserve a fraction of the remaining pool to reduce perceived stepping.
    micro_take = min(TWINKLE_MICRO_STAR_COUNT, max(0, (len(other_points) * 2) // 5))
    micro_points = other_points[:micro_take]
    main_points = other_points[micro_take:]

    add_macro_twinkles(pts=macro_left, phase_seed=seed + 303)
    add_macro_twinkles(pts=macro_right, phase_seed=seed + 404)
    add_anchor_twinkles(pts=anchor_left, phase_seed=seed + 101)
    add_anchor_twinkles(pts=anchor_right, phase_seed=seed + 202)
    add_random_twinkles(pts=main_points, kind="main", style="normal")
    add_random_twinkles(pts=micro_points, kind="micro", style="normal")
    add_random_twinkles(pts=sparkle_points, kind="micro", style="sparkle")

    frames: list[Image.Image] = []

    # Frame count uses the last frame as a duplicate of the first for a seamless wrap.
    for frame_index in range(FRAME_COUNT):
        t = (frame_index % (FRAME_COUNT - 1)) / float(FRAME_COUNT - 1)

        frame = Image.new("RGBA", (FRAME_WIDTH, FRAME_HEIGHT), (0, 0, 0, 0))
        glow = Image.new("RGBA", (FRAME_WIDTH, FRAME_HEIGHT), (0, 0, 0, 0))
        shadow = Image.new("RGBA", (FRAME_WIDTH, FRAME_HEIGHT), (0, 0, 0, 0))
        draw_frame = ImageDraw.Draw(frame)
        draw_glow = ImageDraw.Draw(glow)
        draw_shadow = ImageDraw.Draw(shadow)

        for x01, y01, events, peak_alpha, glow_r, power, style in stars:
            # Raised-cosine envelope per event:
            # - 1.0 at the event center
            # - smoothly fades to 0.0 at the event edges
            best = 0.0
            for center_t, half_width_t in events:
                dt = abs(t - center_t)
                dt = min(dt, 1.0 - dt)  # wrap-around distance for looping
                if dt >= half_width_t:
                    continue
                x = dt / max(1e-6, half_width_t)
                v = 0.5 * (1.0 + math.cos(math.pi * x))
                if v > best:
                    best = v

            if best <= 0.0:
                continue

            intensity = best**power

            fade = _edge_fade_alpha(x01)
            alpha = int(peak_alpha * intensity * fade)
            if alpha <= 0:
                continue

            x = int(x01 * (FRAME_WIDTH - 1))
            y = int(y01 * (FRAME_HEIGHT - 1))

            # Improve visibility on light wallpapers without adding a visible bar backdrop by
            # baking a subtle dark shadow underneath twinkles. This remains per-star (not a band),
            # so the `window#waybar` background can stay fully transparent.
            shadow_r = min(6, (glow_r + 2) if style in {"macro", "sparkle"} else (glow_r + 1))
            shadow_a = min(85 if style == "macro" else 65, int(alpha * (0.28 if style == "macro" else 0.22)))
            if shadow_a > 0:
                draw_shadow.ellipse(
                    (x - shadow_r, y - shadow_r, x + shadow_r, y + shadow_r),
                    fill=(0, 0, 0, shadow_a),
                )

            # Core and glow; glow uses a smaller alpha cap to avoid a visible tinted band.
            glow_r = min(glow_r, 3)
            draw_glow.ellipse(
                (x - glow_r, y - glow_r, x + glow_r, y + glow_r),
                fill=(
                    255,
                    255,
                    255,
                    min(
                        185 if style == "macro" else 150,
                        int(alpha * (0.90 if style == "macro" else (0.85 if glow_r >= 3 else 0.95))),
                    ),
                ),
            )
            if style == "macro":
                # Secondary faint halo increases perceived size without increasing the number of
                # macro stars or adding sliding motion.
                halo_r = 5
                halo_a = min(70, int(alpha * 0.22))
                if halo_a > 0:
                    draw_glow.ellipse(
                        (x - halo_r, y - halo_r, x + halo_r, y + halo_r),
                        fill=(255, 255, 255, halo_a),
                    )
            # Core uses a single pixel to avoid a "blob" look when scaled.
            draw_frame.point((x, y), fill=(255, 255, 255, min(255, int(alpha * 1.25))))

            if style == "macro":
                # Subtle multi-point flare makes macro stars read as "hero" points.
                # Intensity is capped to avoid creating a distracting sparkle pattern.
                flare_a = min(110, int(alpha * 0.45))
                diag_a = min(70, int(alpha * 0.28))
                if flare_a > 0:
                    draw_frame.point((x - 3, y), fill=(255, 255, 255, flare_a))
                    draw_frame.point((x + 3, y), fill=(255, 255, 255, flare_a))
                    draw_frame.point((x, y - 3), fill=(255, 255, 255, flare_a))
                    draw_frame.point((x, y + 3), fill=(255, 255, 255, flare_a))
                if diag_a > 0:
                    draw_frame.point((x - 2, y - 2), fill=(255, 255, 255, diag_a))
                    draw_frame.point((x + 2, y - 2), fill=(255, 255, 255, diag_a))
                    draw_frame.point((x - 2, y + 2), fill=(255, 255, 255, diag_a))
                    draw_frame.point((x + 2, y + 2), fill=(255, 255, 255, diag_a))
            elif style == "sparkle":
                # Subtle 4-point flare; intensity is intentionally capped so the effect reads as
                # a premium glint rather than a distracting "spark".
                flare_a = min(70, int(alpha * 0.35))
                if flare_a > 0:
                    draw_frame.point((x - 2, y), fill=(255, 255, 255, flare_a))
                    draw_frame.point((x + 2, y), fill=(255, 255, 255, flare_a))
                    draw_frame.point((x, y - 2), fill=(255, 255, 255, flare_a))
                    draw_frame.point((x, y + 2), fill=(255, 255, 255, flare_a))

        shadow = shadow.filter(ImageFilter.GaussianBlur(radius=1.05))
        glow = glow.filter(ImageFilter.GaussianBlur(radius=0.75))
        frames.append(Image.alpha_composite(Image.alpha_composite(shadow, glow), frame))

    return frames


def _frames_to_sheet(frames: list[Image.Image]) -> Image.Image:
    # Stack frames vertically to avoid Cairo pattern-size limits hit with very wide horizontal
    # sprite sheets when `background-size` scales the sheet to large center spans.
    sheet = Image.new("RGBA", (FRAME_WIDTH, FRAME_HEIGHT * len(frames)), (0, 0, 0, 0))
    for idx, frame in enumerate(frames):
        sheet.paste(frame, (0, idx * FRAME_HEIGHT))
    return sheet


def main() -> int:
    repo_dir = Path(__file__).resolve().parent.parent
    assets_dir = repo_dir / "assets"

    # Base starfield: faint always-on depth layer.
    base_rng = random.Random(BASE_SEED)
    base_points = _poisson_sample(
        rng=base_rng,
        count=BASE_STAR_COUNT,
        width=FRAME_WIDTH,
        height=FRAME_HEIGHT,
        min_dist_px=BASE_MIN_DIST_PX,
        max_attempts=BASE_STAR_COUNT * 2500,
    )
    # Supplementation points use a different RNG and are rendered as an overlay so the primary
    # base starfield (and its per-star jitter) remains stable across tweaks.
    extra_left_rng = random.Random(BASE_SEED + 4242)
    base_extra_left_points = _poisson_sample(
        rng=extra_left_rng,
        count=BASE_STAR_EXTRA_LEFT,
        width=FRAME_WIDTH,
        height=FRAME_HEIGHT,
        min_dist_px=BASE_MIN_DIST_PX,
        max_attempts=BASE_STAR_EXTRA_LEFT * 3500,
        existing_points=base_points,
        x_min=0.0,
        x_max=FRAME_WIDTH * 0.35,
    )
    extra_right_rng = random.Random(BASE_SEED + 4343)
    base_extra_right_points = _poisson_sample(
        rng=extra_right_rng,
        count=BASE_STAR_EXTRA_RIGHT,
        width=FRAME_WIDTH,
        height=FRAME_HEIGHT,
        min_dist_px=BASE_MIN_DIST_PX,
        max_attempts=BASE_STAR_EXTRA_RIGHT * 3500,
        existing_points=base_points + base_extra_left_points,
        x_min=FRAME_WIDTH * 0.65,
        x_max=float(FRAME_WIDTH - 1),
    )

    def bin_index(x: float) -> int:
        bin_w = FRAME_WIDTH / float(BASE_BIN_COUNT)
        return max(0, min(BASE_BIN_COUNT - 1, int(x / bin_w)))

    base_all_points = base_points + base_extra_left_points + base_extra_right_points
    bin_counts = [0] * BASE_BIN_COUNT
    for x, _y in base_all_points:
        bin_counts[bin_index(x)] += 1

    balance_rng = random.Random(BASE_SEED + 5150)
    balance_points: list[tuple[float, float]] = []
    total_added = 0
    for b, count in enumerate(bin_counts):
        if total_added >= BASE_BALANCE_MAX_TOTAL:
            break
        need = BASE_MIN_STARS_PER_BIN - count
        if need <= 0:
            continue
        need = min(need, BASE_BALANCE_MAX_TOTAL - total_added)
        x0 = (FRAME_WIDTH * b) / float(BASE_BIN_COUNT)
        x1 = (FRAME_WIDTH * (b + 1)) / float(BASE_BIN_COUNT)
        pts = _poisson_sample(
            rng=balance_rng,
            count=need,
            width=FRAME_WIDTH,
            height=FRAME_HEIGHT,
            min_dist_px=BASE_MIN_DIST_PX,
            max_attempts=need * 6000,
            existing_points=base_all_points + balance_points,
            x_min=x0,
            x_max=x1,
        )
        balance_points.extend(pts)
        total_added += len(pts)
    base_layer = _draw_starfield(
        rng=base_rng,
        count=BASE_STAR_COUNT,
        # Keep the base layer very faint so the effect reads as "blinking starlight" rather than
        # a static texture band.
        base_alpha=13,
        tint_rgb=(215, 235, 255),
        width=FRAME_WIDTH,
        height=FRAME_HEIGHT,
        min_dist_px=BASE_MIN_DIST_PX,
        points=base_points,
    )
    if base_extra_left_points:
        base_layer_extra = _draw_starfield(
            rng=extra_left_rng,
            count=len(base_extra_left_points),
            base_alpha=12,
            tint_rgb=(215, 235, 255),
            width=FRAME_WIDTH,
            height=FRAME_HEIGHT,
            min_dist_px=BASE_MIN_DIST_PX,
            points=base_extra_left_points,
        )
        base_layer = Image.alpha_composite(base_layer, base_layer_extra)
    if base_extra_right_points:
        base_layer_extra = _draw_starfield(
            rng=extra_right_rng,
            count=len(base_extra_right_points),
            base_alpha=11,
            tint_rgb=(215, 235, 255),
            width=FRAME_WIDTH,
            height=FRAME_HEIGHT,
            min_dist_px=BASE_MIN_DIST_PX,
            points=base_extra_right_points,
        )
        base_layer = Image.alpha_composite(base_layer, base_layer_extra)
    if balance_points:
        base_layer_extra = _draw_starfield(
            rng=balance_rng,
            count=len(balance_points),
            base_alpha=10,
            tint_rgb=(215, 235, 255),
            width=FRAME_WIDTH,
            height=FRAME_HEIGHT,
            min_dist_px=BASE_MIN_DIST_PX,
            points=balance_points,
        )
        base_layer = Image.alpha_composite(base_layer, base_layer_extra)
    _write_png(assets_dir / "starlight_base.png", base_layer)

    # Twinkle frames: per-star fade across frames.
    # Twinkle point sampling considers the base points to avoid clusters where twinkles sit directly
    # on top of base stars (common "snow" failure mode in low-height strips).
    twinkle_seed = BASE_SEED + 9001
    twinkle_rng = random.Random(twinkle_seed)
    twinkle_points = _poisson_sample(
        rng=twinkle_rng,
        count=TWINKLE_STAR_COUNT,
        width=FRAME_WIDTH,
        height=FRAME_HEIGHT,
        min_dist_px=TWINKLE_MIN_DIST_PX,
        max_attempts=TWINKLE_STAR_COUNT * 3500,
        existing_points=base_points,
    )
    # Add a small number of twinkles on the left to match the base supplementation.
    twinkle_extra_rng = random.Random(BASE_SEED + 9001 + 4242)
    twinkle_extra_left_points = _poisson_sample(
        rng=twinkle_extra_rng,
        count=TWINKLE_STAR_EXTRA_LEFT,
        width=FRAME_WIDTH,
        height=FRAME_HEIGHT,
        min_dist_px=TWINKLE_MIN_DIST_PX,
        max_attempts=TWINKLE_STAR_EXTRA_LEFT * 4500,
        existing_points=base_points + base_extra_left_points + twinkle_points,
        x_min=0.0,
        x_max=FRAME_WIDTH * 0.35,
    )
    if twinkle_extra_left_points:
        twinkle_points = twinkle_points + twinkle_extra_left_points

    # Right-side supplementation mirrors the left-side fill so both sides of the clock keep
    # twinkling activity throughout the loop.
    twinkle_extra_right_rng = random.Random(BASE_SEED + 9001 + 4343)
    twinkle_extra_right_points = _poisson_sample(
        rng=twinkle_extra_right_rng,
        count=TWINKLE_STAR_EXTRA_RIGHT,
        width=FRAME_WIDTH,
        height=FRAME_HEIGHT,
        min_dist_px=TWINKLE_MIN_DIST_PX,
        max_attempts=TWINKLE_STAR_EXTRA_RIGHT * 4500,
        existing_points=base_points + base_extra_right_points + twinkle_points,
        x_min=FRAME_WIDTH * 0.65,
        x_max=float(FRAME_WIDTH - 1),
    )
    if twinkle_extra_right_points:
        twinkle_points = twinkle_points + twinkle_extra_right_points

    # Anchor points are sampled independently to guarantee consistent activity on both sides while
    # keeping spacing higher than the main twinkles to avoid a "snow" look.
    anchor_rng = random.Random(BASE_SEED + 9001 + 7777)
    anchor_left_points = _poisson_sample(
        rng=anchor_rng,
        count=TWINKLE_ANCHOR_STARS_PER_SIDE,
        width=FRAME_WIDTH,
        height=FRAME_HEIGHT,
        min_dist_px=TWINKLE_ANCHOR_MIN_DIST_PX,
        max_attempts=TWINKLE_ANCHOR_STARS_PER_SIDE * 9000,
        existing_points=base_points + base_extra_left_points + twinkle_points,
        x_min=0.0,
        x_max=FRAME_WIDTH * 0.35,
    )
    anchor_right_points = _poisson_sample(
        rng=anchor_rng,
        count=TWINKLE_ANCHOR_STARS_PER_SIDE,
        width=FRAME_WIDTH,
        height=FRAME_HEIGHT,
        min_dist_px=TWINKLE_ANCHOR_MIN_DIST_PX,
        max_attempts=TWINKLE_ANCHOR_STARS_PER_SIDE * 9000,
        existing_points=base_points + base_extra_right_points + twinkle_points + anchor_left_points,
        x_min=FRAME_WIDTH * 0.65,
        x_max=float(FRAME_WIDTH - 1),
    )
    if anchor_left_points:
        twinkle_points = twinkle_points + anchor_left_points
    if anchor_right_points:
        twinkle_points = twinkle_points + anchor_right_points

    # Macro points are sampled independently with a higher separation to avoid clumps. These are
    # merged into the twinkle pool so the renderer can schedule them as larger/brighter twinkles.
    macro_rng = random.Random(BASE_SEED + 9001 + 8888)
    macro_left_points = _poisson_sample(
        rng=macro_rng,
        count=TWINKLE_MACRO_STARS_PER_SIDE,
        width=FRAME_WIDTH,
        height=FRAME_HEIGHT,
        min_dist_px=TWINKLE_MACRO_MIN_DIST_PX,
        max_attempts=TWINKLE_MACRO_STARS_PER_SIDE * 20000,
        existing_points=base_points + base_extra_left_points + twinkle_points,
        x_min=0.0,
        x_max=FRAME_WIDTH * 0.35,
    )
    macro_right_points = _poisson_sample(
        rng=macro_rng,
        count=TWINKLE_MACRO_STARS_PER_SIDE,
        width=FRAME_WIDTH,
        height=FRAME_HEIGHT,
        min_dist_px=TWINKLE_MACRO_MIN_DIST_PX,
        max_attempts=TWINKLE_MACRO_STARS_PER_SIDE * 20000,
        existing_points=base_points + base_extra_right_points + twinkle_points + macro_left_points,
        x_min=FRAME_WIDTH * 0.65,
        x_max=float(FRAME_WIDTH - 1),
    )
    if macro_left_points:
        twinkle_points = twinkle_points + macro_left_points
    if macro_right_points:
        twinkle_points = twinkle_points + macro_right_points

    # Sparkle points are sampled last with a large separation so they remain rare glints.
    sparkle_rng = random.Random(BASE_SEED + 9001 + 9999)
    sparkle_points = _poisson_sample(
        rng=sparkle_rng,
        count=TWINKLE_SPARKLE_STAR_COUNT,
        width=FRAME_WIDTH,
        height=FRAME_HEIGHT,
        min_dist_px=TWINKLE_SPARKLE_MIN_DIST_PX,
        max_attempts=TWINKLE_SPARKLE_STAR_COUNT * 25000,
        existing_points=base_points + twinkle_points,
    )
    if sparkle_points:
        twinkle_points = twinkle_points + sparkle_points

    twinkle_kinds: dict[tuple[int, int], str] = {}
    for x_f, y_f in anchor_left_points + anchor_right_points:
        twinkle_kinds[(int(round(x_f)), int(round(y_f)))] = "anchor"
    for x_f, y_f in macro_left_points + macro_right_points:
        twinkle_kinds[(int(round(x_f)), int(round(y_f)))] = "macro"
    for x_f, y_f in sparkle_points:
        twinkle_kinds[(int(round(x_f)), int(round(y_f)))] = "sparkle"

    twinkle_frames = _render_twinkle_frames(seed=twinkle_seed, points=twinkle_points, kinds=twinkle_kinds)
    _write_png(assets_dir / "starlight_twinkle_sheet.png", _frames_to_sheet(twinkle_frames))

    # Combined sheet: base+twinkle per frame, so CSS only needs to animate a single background.
    combined_frames = [Image.alpha_composite(base_layer, frame) for frame in twinkle_frames]
    _write_png(assets_dir / "starlight_sheet.png", _frames_to_sheet(combined_frames))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
