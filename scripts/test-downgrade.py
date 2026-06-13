#!/usr/bin/env python3
from __future__ import annotations
"""
SmartLLMRouter 模型降级逻辑测试脚本 v2

每个用例:
  1. 截取测试前的日志位置
  2. 发请求（短超时——我们关心的是路由决策，不是后端是否真的回）
  3. 截取测试后的日志，提取 SmartRouter / ProxyServer 关键行
  4. 判定降级是否触发
"""

import json
import os
import re
import sys
import time
import urllib.request
import urllib.error

PROXY = "http://localhost:1897"
TIMEOUT = 35  # 给后端 30s 超时 + buffer

LOG_DIR = os.path.expanduser("~/Library/Logs/SmartLLMRouter")


def latest_log() -> str:
    files = [os.path.join(LOG_DIR, f) for f in os.listdir(LOG_DIR) if f.endswith(".log")]
    files.sort(key=os.path.getmtime, reverse=True)
    return files[0] if files else ""


def log_size(path: str) -> int:
    try:
        return os.path.getsize(path)
    except OSError:
        return 0


def log_tail_since(path: str, offset: int) -> str:
    if not path:
        return ""
    try:
        with open(path, "rb") as f:
            f.seek(offset)
            return f.read().decode("utf-8", errors="replace")
    except OSError:
        return ""


def post(path: str, body: dict) -> tuple[int, str]:
    headers = {"Content-Type": "application/json"}
    req = urllib.request.Request(
        PROXY + path,
        data=json.dumps(body).encode(),
        headers=headers,
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            return resp.status, resp.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", errors="replace")
    except Exception as e:
        return -1, f"{type(e).__name__}: {e}"


def extract_router_lines(log_chunk: str) -> list[str]:
    """从日志片段中拎出 SmartRouter 和 ProxyServer 关键行"""
    lines = []
    for line in log_chunk.splitlines():
        if "SmartRouter.swift" in line or "RequestForwarder" in line or (
            "ProxyServer.swift" in line and any(k in line for k in ["[#", "No available"])
        ):
            # 去掉前面的时间戳让结果更干净
            m = re.search(r"\[(SmartRouter|ProxyServer|RequestForwarder)\.swift:\d+\].*", line)
            if m:
                lines.append(m.group(0))
            else:
                lines.append(line)
    return lines


def run_case(idx: int, name: str, path: str, body: dict, expect_downgrade: bool):
    log_path = latest_log()
    pre_offset = log_size(log_path)

    print(f"\n{'='*72}")
    print(f"[{idx}] {name}")
    print(f"    POST {path}  model={body.get('model')!r}  expect_downgrade={expect_downgrade}")
    print("-" * 72)

    t0 = time.time()
    status, text = post(path, body)
    elapsed = time.time() - t0
    print(f"    HTTP: {status}  ({elapsed*1000:.0f}ms)")
    if 0 < status < 600:
        # 截短回显
        snip = text[:200].replace("\n", " ")
        print(f"    body[:200]: {snip}")

    # 给日志一点时间落盘
    time.sleep(0.3)
    log_chunk = log_tail_since(log_path, pre_offset)
    router_lines = extract_router_lines(log_chunk)

    print("    ── router log ──")
    if not router_lines:
        print("      (no router activity captured)")
    for line in router_lines:
        print(f"      {line}")

    # 判定
    downgrade_triggered = any("No exact channel match" in l for l in router_lines)
    no_channel = any("No available channel" in l for l in router_lines)
    if downgrade_triggered:
        verdict = "✅ DOWNGRADE TRIGGERED"
    elif no_channel:
        verdict = "⚠️  NO AVAILABLE CHANNEL (cooldown/empty)"
    elif "RequestForwarder" in str(router_lines) or any("[#" in l for l in router_lines):
        verdict = "ℹ️  exact match — forwarded as-is"
    else:
        verdict = "❓ unclear"

    if expect_downgrade and not downgrade_triggered:
        verdict += "  [EXPECTED DOWNGRADE BUT NONE OBSERVED]"
    if not expect_downgrade and downgrade_triggered:
        verdict += "  [UNEXPECTED DOWNGRADE — model exists but no channel?]"
    print(f"    {verdict}")
    return downgrade_triggered, status


def main():
    print(f"SmartLLMRouter downgrade test → {PROXY}")
    print(f"timestamp: {time.strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"log file: {latest_log()}")

    msgs = [{"role": "user", "content": "ok"}]

    cases = [
        ("real OpenAI model: gpt-4o-mini", "/v1/chat/completions",
         {"model": "gpt-4o-mini", "messages": msgs, "max_tokens": 4}, False),
        ("typo OpenAI model: gpt-4o-mim", "/v1/chat/completions",
         {"model": "gpt-4o-mim", "messages": msgs, "max_tokens": 4}, True),
        ("fictional OpenAI model: super-llm-9000", "/v1/chat/completions",
         {"model": "super-llm-9000", "messages": msgs, "max_tokens": 4}, True),
        ("real Anthropic model: claude-3-5-sonnet", "/v1/messages",
         {"model": "claude-3-5-sonnet-20241022", "max_tokens": 4, "messages": msgs}, False),
        ("fictional Anthropic model: claude-fake-99-opus", "/v1/messages",
         {"model": "claude-fake-99-opus", "max_tokens": 4, "messages": msgs}, True),
        ("garbage model: !@#$%^", "/v1/chat/completions",
         {"model": "!@#$%^", "messages": msgs, "max_tokens": 4}, True),
        ("empty model name", "/v1/chat/completions",
         {"model": "", "messages": msgs, "max_tokens": 4}, True),
    ]

    results = []
    for i, (name, p, b, exp) in enumerate(cases, 1):
        try:
            dg, status = run_case(i, name, p, b, exp)
            results.append((name, exp, dg, status))
        except Exception as e:
            print(f"    ❌ EXCEPTION: {e}")
            results.append((name, exp, False, -1))
        time.sleep(1.0)  # 给 circuit breaker 喘息

    print(f"\n{'='*72}")
    print("FINAL VERDICT")
    print("=" * 72)
    pass_n = 0
    for name, exp, dg, status in results:
        ok = (exp == dg) or (not exp and not dg)
        # 对于 expect_downgrade=False 的真实模型：不应触发降级（dg=False 才对）
        # 对于 expect_downgrade=True：应触发降级（dg=True 才对）
        if exp == dg:
            mark = "✅"
            pass_n += 1
        else:
            mark = "❌"
        print(f"  {mark}  expect_dg={exp!s:<5}  observed_dg={dg!s:<5}  http={status:<4}  {name}")
    print(f"\n{pass_n}/{len(results)} cases passed")


if __name__ == "__main__":
    main()
