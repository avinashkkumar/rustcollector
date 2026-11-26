#!/usr/bin/env python3
"""Compare Rustfall benchmark runs (e.g. Linux vs Windows, native vs FSR).

Usage:
    python3 tools/compare_benchmarks.py [RESULT_DIR_OR_PARENT ...] [-o report.html] [--baseline LABEL]

With no arguments it scans build/benchmark_results/. Every folder that contains a
summary.json + frames.csv is one run. Runs with the same OS / preset / upscaler / scale /
resolution are grouped and averaged, so do 3+ runs per configuration.

Only the Python 3 standard library is used, so this runs unchanged on Windows and Linux.
"""
from __future__ import annotations

import argparse
import csv
import html
import json
import math
import statistics as st
import sys
from pathlib import Path

STAGES = ["flyover", "sweep", "swarm", "rover", "storm"]
STAGE_NAMES = {"flyover": "Colony Flyover", "sweep": "Surface Sweep", "swarm": "Drone Swarm",
               "rover": "Sweeper Run", "storm": "Dust Storm"}
PALETTE = ["#e8743b", "#3b8fe8", "#2fae6b", "#b35fd6", "#d6b13b", "#e84a7a", "#4ac6c6", "#8a8a8a"]


# ----------------------------------------------------------------------------- stats

def pct(sorted_vals: list[float], q: float) -> float:
    n = len(sorted_vals)
    return sorted_vals[min(max(math.ceil(q * n) - 1, 0), n - 1)]


def frame_stats(ft: list[float]) -> dict:
    """Same definitions as the in-game benchmark (scripts/benchmark.gd)."""
    n = len(ft)
    if n < 2:
        return {}
    s = sorted(ft)
    total = sum(ft)
    mean = total / n
    sd = math.sqrt(sum((v - mean) ** 2 for v in ft) / n)
    deltas = [abs(ft[i] - ft[i - 1]) for i in range(1, n)]
    ds = sorted(deltas)
    stutters, roll, win = 0, 0.0, 30
    for i, v in enumerate(ft):
        if i >= 8:
            avg = roll / min(i, win)
            if v > avg * 2.0 and v - avg > 4.0:
                stutters += 1
        if i >= win:
            roll -= ft[i - win]
        roll += v
    k1 = max(int(n * 0.01), 1)
    k01 = max(int(n * 0.001), 1)
    return {
        "frames": n,
        "avg_fps": 1000.0 * n / total,
        "low_1pct_fps": 1000.0 / (sum(s[-k1:]) / k1),
        "low_01pct_fps": 1000.0 / (sum(s[-k01:]) / k01),
        "ft_avg_ms": mean,
        "ft_p50_ms": pct(s, 0.5),
        "ft_p95_ms": pct(s, 0.95),
        "ft_p99_ms": pct(s, 0.99),
        "ft_max_ms": s[-1],
        "ft_stddev_ms": sd,
        "pacing_avg_delta_ms": sum(deltas) / len(deltas),
        "pacing_p99_delta_ms": pct(ds, 0.99),
        "pacing_delta_over_2ms_pct": 100.0 * sum(d > 2.0 for d in deltas) / len(deltas),
        "stutters": stutters,
        "hitches_over_50ms": sum(v > 50.0 for v in ft),
    }


def col_mean(rows: list[dict], key: str) -> float:
    vals = [float(r[key]) for r in rows if r.get(key) not in (None, "")]
    return st.mean(vals) if vals else 0.0


# ----------------------------------------------------------------------------- loading

class Run:
    def __init__(self, path: Path):
        self.path = path
        self.summary = json.loads((path / "summary.json").read_text(encoding="utf-8"))
        with (path / "frames.csv").open(newline="", encoding="utf-8") as f:
            self.rows = list(csv.DictReader(f))
        sysinfo = self.summary["system"]
        self.sys = sysinfo
        up = sysinfo.get("upscaler", "off")
        scale = float(sysinfo.get("render_scale", 1.0))
        self.label = "{os} · {preset} · {up} {scale}% · {res}".format(
            os=sysinfo["os"], preset=sysinfo["preset"], up=up.upper(), scale=round(scale * 100), res=sysinfo["resolution"])
        self.ft = [float(r["frametime_ms"]) for r in self.rows]
        self.overall = self._stats(self.rows)
        self.stages = {s: self._stats([r for r in self.rows if r["stage"] == s]) for s in STAGES}

    @staticmethod
    def _stats(rows: list[dict]) -> dict:
        d = frame_stats([float(r["frametime_ms"]) for r in rows])
        if d:
            d["gpu_avg_ms"] = col_mean(rows, "gpu_ms")
            d["cpu_render_avg_ms"] = col_mean(rows, "cpu_render_ms")
            d["draw_calls_avg"] = col_mean(rows, "draw_calls")
            d["vram_max_mb"] = max(float(r["vram_mb"]) for r in rows)
        return d


def find_runs(paths: list[Path]) -> list[Run]:
    runs = []
    for p in paths:
        for summary in sorted(p.rglob("summary.json")) if p.is_dir() else []:
            d = summary.parent
            if (d / "frames.csv").exists():
                try:
                    runs.append(Run(d))
                except (KeyError, ValueError, json.JSONDecodeError) as e:
                    print(f"skipping {d}: {e}", file=sys.stderr)
    return runs


class Group:
    def __init__(self, label: str, runs: list[Run]):
        self.label = label
        self.runs = runs
        self.sys = runs[0].sys

    def metric(self, key: str, stage: str | None = None) -> tuple[float, float]:
        vals = [(r.stages.get(stage, {}) if stage else r.overall).get(key) for r in self.runs]
        vals = [v for v in vals if v is not None]
        if not vals:
            return float("nan"), 0.0
        return st.mean(vals), (st.stdev(vals) if len(vals) > 1 else 0.0)


# ----------------------------------------------------------------------------- report

METRICS = [
    ("avg_fps", "Avg FPS", True, "{:.1f}"),
    ("low_1pct_fps", "1% low", True, "{:.1f}"),
    ("low_01pct_fps", "0.1% low", True, "{:.1f}"),
    ("ft_p99_ms", "p99 frame ms", False, "{:.2f}"),
    ("ft_stddev_ms", "Frame SD ms", False, "{:.2f}"),
    ("pacing_avg_delta_ms", "Pacing Δ ms", False, "{:.2f}"),
    ("pacing_delta_over_2ms_pct", "Δ>2ms %", False, "{:.1f}"),
    ("stutters", "Stutters", False, "{:.1f}"),
    ("gpu_avg_ms", "GPU ms", False, "{:.2f}"),
    ("cpu_render_avg_ms", "CPU render ms", False, "{:.2f}"),
]


def fmt_cell(g: Group, base: Group, key: str, better_high: bool, fmt: str, stage: str | None = None) -> str:
    m, sd = g.metric(key, stage)
    if math.isnan(m):
        return "<td>–</td>"
    txt = fmt.format(m)
    if len(g.runs) > 1:
        txt += f"<span class=sd> ±{fmt.format(sd)}</span>"
    if g is not base:
        b, _ = base.metric(key, stage)
        if b and not math.isnan(b) and b != 0:
            delta = (m - b) / abs(b) * 100.0
            good = (delta > 0) == better_high
            if abs(delta) >= 0.5:
                txt += f"<span class='d {'good' if good else 'bad'}'>{delta:+.1f}%</span>"
    return f"<td>{txt}</td>"


def table(groups: list[Group], base: Group, stage: str | None) -> str:
    head = "".join(f"<th>{html.escape(h)}</th>" for _, h, _, _ in METRICS)
    out = [f"<table><thead><tr><th>Configuration</th><th>Runs</th>{head}</tr></thead><tbody>"]
    for i, g in enumerate(groups):
        cells = "".join(fmt_cell(g, base, k, hi, f, stage) for k, _, hi, f in METRICS)
        sw = f"<span class=sw style='background:{PALETTE[i % len(PALETTE)]}'></span>"
        tag = " <span class=base>baseline</span>" if g is base else ""
        out.append(f"<tr><th class=lbl>{sw}{html.escape(g.label)}{tag}</th><td>{len(g.runs)}</td>{cells}</tr>")
    out.append("</tbody></table>")
    return "".join(out)


def svg_frametimes(groups: list[Group], width=1100, height=300) -> str:
    """Frame time over benchmark time, first run of each group, downsampled to max-per-bucket."""
    pad_l, pad_b = 46, 26
    series = []
    tmax, ymax = 0.0, 0.0
    for g in groups:
        r = g.runs[0]
        t = [float(x["time_s"]) for x in r.rows]
        tmax = max(tmax, t[-1] if t else 0)
        series.append((t, r.ft))
        ymax = max(ymax, pct(sorted(r.ft), 0.995))
    ymax = max(ymax * 1.15, 5.0)
    buckets = 900
    paths = []
    for i, (t, ft) in enumerate(series):
        pts = {}
        for ti, v in zip(t, ft):
            b = int(ti / max(tmax, 1e-6) * (buckets - 1))
            pts[b] = max(pts.get(b, 0.0), v)
        d = " ".join(f"{pad_l + b / (buckets - 1) * (width - pad_l - 8):.1f},{(height - pad_b) - min(v, ymax) / ymax * (height - pad_b - 8):.1f}"
                     for b, v in sorted(pts.items()))
        paths.append(f"<polyline fill=none stroke='{PALETTE[i % len(PALETTE)]}' stroke-width=1.3 points='{d}'/>")
    grid = []
    for k in range(6):
        y = (height - pad_b) - k / 5 * (height - pad_b - 8)
        grid.append(f"<line x1={pad_l} x2={width - 8} y1={y:.1f} y2={y:.1f} class=grid /><text x=4 y={y + 4:.1f}>{ymax * k / 5:.1f}</text>")
    stage_marks = []
    r0 = groups[0].runs[0]
    seen = set()
    for x in r0.rows:
        if x["stage"] not in seen:
            seen.add(x["stage"])
            xx = pad_l + float(x["time_s"]) / max(tmax, 1e-6) * (width - pad_l - 8)
            stage_marks.append(f"<line x1={xx:.1f} x2={xx:.1f} y1=8 y2={height - pad_b} class=stage /><text x={xx + 4:.1f} y={height - 8}>{STAGE_NAMES.get(x['stage'], x['stage'])}</text>")
    return f"<svg viewBox='0 0 {width} {height}' class=chart>{''.join(grid)}{''.join(stage_marks)}{''.join(paths)}<text x=4 y=12>ms</text></svg>"


def svg_percentiles(groups: list[Group], width=540, height=300) -> str:
    """Frame-time percentile curve (lower and flatter is better)."""
    pad_l, pad_b = 46, 26
    qs = [i / 200 for i in range(100, 200)] + [0.995, 0.999]
    curves, ymax = [], 0.0
    for g in groups:
        s = sorted(g.runs[0].ft)
        c = [(q, pct(s, q)) for q in qs]
        ymax = max(ymax, c[-1][1])
        curves.append(c)
    ymax = max(ymax * 1.1, 5.0)

    def xq(q: float) -> float:  # log-ish scale emphasising the tail
        return pad_l + (-math.log10(1 - min(q, 0.999)) / 3.0) * (width - pad_l - 8)

    paths = []
    for i, c in enumerate(curves):
        d = " ".join(f"{xq(q):.1f},{(height - pad_b) - v / ymax * (height - pad_b - 8):.1f}" for q, v in c)
        paths.append(f"<polyline fill=none stroke='{PALETTE[i % len(PALETTE)]}' stroke-width=2 points='{d}'/>")
    ticks = "".join(f"<line x1={xq(q):.1f} x2={xq(q):.1f} y1=8 y2={height - pad_b} class=grid /><text x={xq(q) - 10:.1f} y={height - 8}>{lbl}</text>"
                    for q, lbl in [(0.5, "p50"), (0.9, "p90"), (0.99, "p99"), (0.999, "p99.9")])
    yt = "".join(f"<text x=4 y={(height - pad_b) - k / 4 * (height - pad_b - 8) + 4:.1f}>{ymax * k / 4:.1f}</text>" for k in range(5))
    return f"<svg viewBox='0 0 {width} {height}' class=chart>{ticks}{yt}{''.join(paths)}</svg>"


def svg_bars(groups: list[Group], key: str, title: str, width=540, height=300) -> str:
    pad_l, pad_b = 46, 40
    n_st = len(STAGES)
    vals = [[g.metric(key, s)[0] for s in STAGES] for g in groups]
    vmax = max((v for row in vals for v in row if not math.isnan(v)), default=1.0) * 1.15
    gw = (width - pad_l - 8) / n_st
    bw = gw * 0.8 / max(len(groups), 1)
    bars = []
    for si, s in enumerate(STAGES):
        for gi, row in enumerate(vals):
            v = row[si]
            if math.isnan(v):
                continue
            h = v / vmax * (height - pad_b - 10)
            x = pad_l + si * gw + gw * 0.1 + gi * bw
            bars.append(f"<rect x={x:.1f} y={height - pad_b - h:.1f} width={bw - 1:.1f} height={h:.1f} fill='{PALETTE[gi % len(PALETTE)]}'><title>{html.escape(groups[gi].label)}: {v:.1f}</title></rect>")
        bars.append(f"<text x={pad_l + si * gw + gw / 2:.1f} y={height - pad_b + 16} text-anchor=middle>{STAGE_NAMES[s]}</text>")
    yt = "".join(f"<text x=4 y={(height - pad_b) - k / 4 * (height - pad_b - 10) + 4:.1f}>{vmax * k / 4:.0f}</text>" for k in range(5))
    return f"<svg viewBox='0 0 {width} {height}' class=chart><text x={pad_l} y=12 class=t>{html.escape(title)}</text>{yt}{''.join(bars)}</svg>"


def sys_table(groups: list[Group]) -> str:
    keys = [("os", "OS"), ("os_version", "OS version"), ("os_distribution", "Distribution"), ("display_server", "Display server"),
            ("cpu", "CPU"), ("ram_gb", "RAM GB"), ("gpu", "GPU"), ("gpu_driver", "GPU driver"), ("rendering_driver", "Graphics API"),
            ("gpu_api_version", "API version"), ("resolution", "Resolution"), ("internal_resolution", "Internal resolution"),
            ("upscaler", "Upscaler"), ("render_scale", "Render scale"), ("preset", "Preset"), ("window_mode", "Window mode"),
            ("refresh_rate", "Refresh Hz"), ("engine", "Engine"), ("build", "Build")]
    head = "".join(f"<th><span class=sw style='background:{PALETTE[i % len(PALETTE)]}'></span>{html.escape(g.label)}</th>" for i, g in enumerate(groups))
    rows = "".join("<tr><th class=lbl>{}</th>{}</tr>".format(lbl, "".join(f"<td>{html.escape(str(g.sys.get(k, '–')))}</td>" for g in groups)) for k, lbl in keys)
    return f"<table class=sys><thead><tr><th></th>{head}</tr></thead><tbody>{rows}</tbody></table>"


CSS = """
:root{--bg:#fbf8f6;--fg:#231a16;--mut:#7d6c63;--line:#e6dcd6;--card:#fff;--good:#1d8a4f;--bad:#c2412d}
@media (prefers-color-scheme:dark){:root{--bg:#171210;--fg:#f1e7e1;--mut:#a7958b;--line:#352a25;--card:#211a17;--good:#4cc985;--bad:#ff7a63}}
body{margin:0;background:var(--bg);color:var(--fg);font:14px/1.45 system-ui,-apple-system,Segoe UI,Roboto,sans-serif}
main{max-width:1180px;margin:0 auto;padding:28px 20px 60px}
h1{font-size:24px;margin:0 0 4px}h2{font-size:17px;margin:30px 0 10px}p.mut{color:var(--mut);margin:0 0 16px}
.card{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:14px;overflow-x:auto;margin-bottom:14px}
table{border-collapse:collapse;width:100%;font-variant-numeric:tabular-nums}
th,td{padding:6px 9px;border-bottom:1px solid var(--line);text-align:right;white-space:nowrap}
th.lbl,thead th:first-child{text-align:left}thead th{color:var(--mut);font-weight:600;font-size:12px}
.sd{color:var(--mut);font-size:11px}.d{font-size:11px;margin-left:5px}.d.good{color:var(--good)}.d.bad{color:var(--bad)}
.base{font-size:10px;border:1px solid var(--line);border-radius:4px;padding:0 4px;color:var(--mut);margin-left:4px}
.sw{display:inline-block;width:10px;height:10px;border-radius:2px;margin-right:7px;vertical-align:middle}
.row{display:grid;grid-template-columns:1fr 1fr;gap:14px}@media (max-width:900px){.row{grid-template-columns:1fr}}
svg.chart{width:100%;height:auto;font-size:11px;fill:var(--mut)}svg .grid{stroke:var(--line)}svg .stage{stroke:var(--line);stroke-dasharray:3 3}svg .t{fill:var(--fg);font-weight:600}
table.sys td{text-align:left;white-space:normal}
"""


def build_report(groups: list[Group], base: Group) -> str:
    parts = [f"<!doctype html><html><head><meta charset=utf-8><meta name=viewport content='width=device-width,initial-scale=1'>",
             f"<title>Rustfall benchmark comparison</title><style>{CSS}</style></head><body><main>",
             "<h1>Rustfall benchmark comparison</h1>",
             f"<p class=mut>{sum(len(g.runs) for g in groups)} runs in {len(groups)} configurations. Deltas are relative to the baseline; ± is the standard deviation across repeated runs. "
             "Pacing Δ = average change in frame time from one frame to the next (lower = smoother).</p>",
             "<h2>Overall</h2><div class=card>", table(groups, base, None), "</div>",
             "<h2>Frame time over the run</h2><div class=card>", svg_frametimes(groups), "</div>",
             "<div class=row><div><h2>Frame-time percentiles</h2><div class=card>", svg_percentiles(groups),
             "</div></div><div><h2>Average FPS by stage</h2><div class=card>", svg_bars(groups, "avg_fps", "Avg FPS"), "</div></div></div>",
             "<div class=row><div><h2>1% low FPS by stage</h2><div class=card>", svg_bars(groups, "low_1pct_fps", "1% low FPS"),
             "</div></div><div><h2>GPU time by stage (ms)</h2><div class=card>", svg_bars(groups, "gpu_avg_ms", "GPU ms"), "</div></div></div>"]
    for s in STAGES:
        parts += [f"<h2>Stage: {STAGE_NAMES[s]}</h2><div class=card>", table(groups, base, s), "</div>"]
    parts += ["<h2>Systems</h2><div class=card>", sys_table(groups), "</div></main></body></html>"]
    return "".join(parts)


def main() -> int:
    here = Path(__file__).resolve().parent.parent
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("paths", nargs="*", type=Path, help="result folders or parents (default: build/benchmark_results)")
    ap.add_argument("-o", "--output", type=Path, help="HTML report path (default: <first path>/comparison.html)")
    ap.add_argument("--baseline", help="substring of the configuration label to use as baseline (default: first)")
    args = ap.parse_args()
    paths = args.paths or [here / "build" / "benchmark_results"]
    runs = find_runs(paths)
    if not runs:
        print("No benchmark runs found in: " + ", ".join(map(str, paths)), file=sys.stderr)
        return 1
    by_label: dict[str, list[Run]] = {}
    for r in runs:
        by_label.setdefault(r.label, []).append(r)
    groups = [Group(k, v) for k, v in sorted(by_label.items())]
    base = next((g for g in groups if args.baseline and args.baseline.lower() in g.label.lower()), groups[0])
    out = args.output or (paths[0] / "comparison.html")
    out.write_text(build_report(groups, base), encoding="utf-8")
    w = max(len(g.label) for g in groups)
    print(f"{'Configuration':<{w}}  runs  avgFPS  1%low  0.1%low  p99ms  SDms  paceΔ  stutters  GPUms")
    for g in groups:
        m = lambda k: g.metric(k)[0]
        print(f"{g.label:<{w}}  {len(g.runs):>4}  {m('avg_fps'):6.1f}  {m('low_1pct_fps'):5.1f}  {m('low_01pct_fps'):7.1f}  "
              f"{m('ft_p99_ms'):5.2f}  {m('ft_stddev_ms'):4.2f}  {m('pacing_avg_delta_ms'):5.2f}  {m('stutters'):8.1f}  {m('gpu_avg_ms'):5.2f}")
    print(f"\nReport written to {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
