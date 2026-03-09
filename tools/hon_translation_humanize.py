#!/usr/bin/env python3
"""
Humanize Russian HoN .str translations using OpenAI API.

What it does:
- Reads HoN .str key/value files.
- Sends Russian values in chunks to the model for style polishing.
- Preserves HoN tokens/placeholders/format tags.
- Writes updated file with original BOM/newline style.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any


KV_RE = re.compile(r"^(?P<key>\S+)(?P<sep>[ \t]+)(?P<val>.*)$")
COMMENT_RE = re.compile(r"^\s*//")
CYRILLIC_RE = re.compile(r"[\u0400-\u04FF]")
TOKEN_RE = re.compile(
    r"(\\n|\^[A-Za-z*]|\{[^{}\r\n]+\}|%\d+\$?[A-Za-z]|%[A-Za-z])"
)


@dataclass
class Candidate:
    index: int
    line_no: int
    key: str
    value: str


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Humanize Russian HoN .str text.")
    p.add_argument("--input", required=True, help="Input .str path.")
    p.add_argument("--output", required=True, help="Output .str path.")
    p.add_argument(
        "--report",
        default="",
        help="JSON report path (default: <output>.humanize.report.json).",
    )
    p.add_argument(
        "--model",
        default="gpt-4.1-mini",
        help="Model for text polishing (OpenAI or Gemini).",
    )
    p.add_argument(
        "--provider",
        default="auto",
        choices=["auto", "openai", "gemini"],
        help="API provider to use. auto picks Gemini first if key exists.",
    )
    p.add_argument(
        "--chunk-size",
        type=int,
        default=50,
        help="Number of candidate values per API request.",
    )
    p.add_argument(
        "--request-delay",
        type=float,
        default=0.15,
        help="Delay between requests in seconds.",
    )
    p.add_argument(
        "--timeout",
        type=int,
        default=90,
        help="HTTP timeout in seconds.",
    )
    p.add_argument(
        "--skip-candidates",
        type=int,
        default=0,
        help="Skip this number of candidate lines.",
    )
    p.add_argument(
        "--max-lines",
        type=int,
        default=0,
        help="Limit candidates processed (0 = all).",
    )
    p.add_argument(
        "--max-value-length",
        type=int,
        default=1800,
        help="Skip value if it is longer than this number of chars.",
    )
    p.add_argument(
        "--dry-run",
        action="store_true",
        help="Do not write edited text, only generate report.",
    )
    return p.parse_args()


def read_text_with_bom(path: Path) -> tuple[str, bool]:
    data = path.read_bytes()
    had_bom = data.startswith(b"\xef\xbb\xbf")
    text = data.decode("utf-8-sig")
    return text, had_bom


def write_text_with_bom(path: Path, text: str, with_bom: bool) -> None:
    if with_bom:
        path.write_bytes(text.encode("utf-8-sig"))
    else:
        path.write_bytes(text.encode("utf-8"))


def load_api_key() -> str:
    raise RuntimeError("Internal error: use load_api_key_for_provider().")


def _load_key_from_env_or_registry(name: str) -> str:
    val = os.environ.get(name, "").strip()
    if val:
        return val

    if sys.platform.startswith("win"):
        try:
            import winreg  # type: ignore

            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, r"Environment") as key:
                reg_val, _ = winreg.QueryValueEx(key, name)
                reg_val = str(reg_val).strip()
                if reg_val:
                    return reg_val
        except Exception:
            pass
    return ""


def detect_provider(explicit: str) -> str:
    if explicit != "auto":
        return explicit
    if _load_key_from_env_or_registry("GEMINI_API_KEY") or _load_key_from_env_or_registry(
        "GOOGLE_API_KEY"
    ):
        return "gemini"
    if _load_key_from_env_or_registry("OPENAI_API_KEY"):
        return "openai"
    raise RuntimeError(
        "No API key found. Set GEMINI_API_KEY/GOOGLE_API_KEY or OPENAI_API_KEY."
    )


def load_api_key_for_provider(provider: str) -> str:
    if provider == "gemini":
        key = _load_key_from_env_or_registry("GEMINI_API_KEY")
        if key:
            return key
        key = _load_key_from_env_or_registry("GOOGLE_API_KEY")
        if key:
            return key
        raise RuntimeError(
            "Gemini key not found. Set GEMINI_API_KEY or GOOGLE_API_KEY."
        )

    if provider == "openai":
        key = _load_key_from_env_or_registry("OPENAI_API_KEY")
        if key:
            return key
        raise RuntimeError(
            "OPENAI_API_KEY not found. Set it in env or HKCU\\Environment."
        )

    raise RuntimeError(f"Unknown provider: {provider}")


def extract_tokens(text: str) -> list[str]:
    return TOKEN_RE.findall(text)


def tokens_match(a: str, b: str) -> bool:
    return extract_tokens(a) == extract_tokens(b)


def safe_length_ratio(src: str, dst: str) -> bool:
    src_len = len(src.strip())
    dst_len = len(dst.strip())
    if src_len == 0:
        return dst_len == 0
    ratio = dst_len / src_len
    return 0.35 <= ratio <= 2.75


def normalize_json_payload(raw: str) -> dict[str, Any]:
    raw = raw.strip()
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        match = re.search(r"\{.*\}", raw, re.DOTALL)
        if not match:
            raise
        return json.loads(match.group(0))


def call_openai_chat(
    api_key: str,
    model: str,
    system_text: str,
    user_text: str,
    timeout: int,
    max_retries: int = 4,
) -> str:
    url = "https://api.openai.com/v1/chat/completions"
    payload = {
        "model": model,
        "temperature": 0.2,
        "messages": [
            {"role": "system", "content": system_text},
            {"role": "user", "content": user_text},
        ],
    }
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
        "User-Agent": "HoN-RU-Humanize/1.0",
    }

    last_error: Exception | None = None
    for attempt in range(max_retries + 1):
        req = urllib.request.Request(url, data=body, method="POST", headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                obj = json.loads(resp.read().decode("utf-8"))
                choices = obj.get("choices") or []
                if not choices:
                    raise RuntimeError("OpenAI response has no choices.")
                msg = choices[0].get("message") or {}
                content = msg.get("content")
                if not isinstance(content, str):
                    raise RuntimeError("OpenAI response content is not text.")
                return content
        except urllib.error.HTTPError as e:
            status = e.code
            err_text = ""
            try:
                err_text = e.read().decode("utf-8", errors="replace")
            except Exception:
                pass
            last_error = RuntimeError(
                f"HTTP {status} from OpenAI: {err_text[:600]}"
            )
            if status in {408, 409, 429, 500, 502, 503, 504} and attempt < max_retries:
                time.sleep(1.8 * (attempt + 1))
                continue
            raise last_error
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as e:
            last_error = e
            if attempt < max_retries:
                time.sleep(1.8 * (attempt + 1))
                continue
            raise

    if last_error:
        raise last_error
    raise RuntimeError("OpenAI request failed unexpectedly.")


def call_gemini_generate(
    api_key: str,
    model: str,
    system_text: str,
    user_text: str,
    timeout: int,
    max_retries: int = 4,
) -> str:
    model_enc = urllib.parse.quote(model, safe="")
    key_enc = urllib.parse.quote(api_key, safe="")
    url = (
        f"https://generativelanguage.googleapis.com/v1beta/models/"
        f"{model_enc}:generateContent?key={key_enc}"
    )
    payload = {
        "systemInstruction": {"parts": [{"text": system_text}]},
        "contents": [{"parts": [{"text": user_text}]}],
        "generationConfig": {
            "temperature": 0.2,
            "responseMimeType": "application/json",
        },
    }
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    headers = {
        "Content-Type": "application/json",
        "User-Agent": "HoN-RU-Humanize/1.0",
    }

    last_error: Exception | None = None
    for attempt in range(max_retries + 1):
        req = urllib.request.Request(url, data=body, method="POST", headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                obj = json.loads(resp.read().decode("utf-8"))
                candidates = obj.get("candidates") or []
                if not candidates:
                    raise RuntimeError(f"Gemini response has no candidates: {obj}")
                content = candidates[0].get("content") or {}
                parts = content.get("parts") or []
                if not parts:
                    raise RuntimeError(f"Gemini response has empty parts: {obj}")
                text = parts[0].get("text")
                if not isinstance(text, str):
                    raise RuntimeError(f"Gemini response text is missing: {obj}")
                return text
        except urllib.error.HTTPError as e:
            status = e.code
            err_text = ""
            try:
                err_text = e.read().decode("utf-8", errors="replace")
            except Exception:
                pass
            last_error = RuntimeError(f"HTTP {status} from Gemini: {err_text[:600]}")
            if status in {408, 409, 429, 500, 502, 503, 504} and attempt < max_retries:
                time.sleep(1.8 * (attempt + 1))
                continue
            raise last_error
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as e:
            last_error = e
            if attempt < max_retries:
                time.sleep(1.8 * (attempt + 1))
                continue
            raise

    if last_error:
        raise last_error
    raise RuntimeError("Gemini request failed unexpectedly.")


def build_prompts(batch: list[Candidate]) -> tuple[str, str]:
    sys_msg = (
        "Ты редактор локализации игры на русский язык. "
        "Нужно сделать текст естественным, грамотным и игровым по стилю. "
        "Правь только формулировки и орфографию, смысл не меняй.\n\n"
        "Обязательно:\n"
        "1) Верни только JSON: {\"items\":[{\"id\":<int>,\"text\":\"...\"}]}\n"
        "2) Сохрани все служебные токены без изменений: \\n, ^x, ^*, {token}, %s, %d, %1 и подобные.\n"
        "3) Не меняй HTML-подобные/форматные маркеры и числа.\n"
        "4) Не переводи латинские названия способностей/предметов/имен, если они уже на английском.\n"
        "5) Не добавляй комментарии, только JSON."
    )
    user_payload = {
        "items": [{"id": c.index, "text": c.value} for c in batch],
    }
    user_msg = json.dumps(user_payload, ensure_ascii=False, indent=2)
    return sys_msg, user_msg


def chunked(items: list[Candidate], chunk_size: int) -> list[list[Candidate]]:
    out: list[list[Candidate]] = []
    for i in range(0, len(items), chunk_size):
        out.append(items[i : i + chunk_size])
    return out


def main() -> int:
    args = parse_args()
    in_path = Path(args.input).expanduser().resolve()
    out_path = Path(args.output).expanduser().resolve()
    report_path = (
        Path(args.report).expanduser().resolve()
        if args.report
        else out_path.with_suffix(out_path.suffix + ".humanize.report.json")
    )

    if not in_path.exists():
        raise SystemExit(f"Input not found: {in_path}")

    provider = detect_provider(args.provider)
    api_key = load_api_key_for_provider(provider)

    original_bytes = in_path.read_bytes()
    original_text, had_bom = read_text_with_bom(in_path)
    newline = "\r\n" if "\r\n" in original_text else "\n"
    had_trailing_newline = original_text.endswith("\n")
    lines = original_text.splitlines()

    parsed: list[tuple[str, str, str, str] | None] = []
    candidates: list[Candidate] = []

    for idx, line in enumerate(lines):
        if not line or COMMENT_RE.match(line):
            parsed.append(None)
            continue
        m = KV_RE.match(line)
        if not m:
            parsed.append(None)
            continue
        key = m.group("key")
        sep = m.group("sep")
        val = m.group("val")
        parsed.append((key, sep, val, line))

        if not CYRILLIC_RE.search(val):
            continue
        if len(val) > args.max_value_length:
            continue
        candidates.append(Candidate(index=idx, line_no=idx + 1, key=key, value=val))

    total_candidates = len(candidates)
    candidates = candidates[args.skip_candidates :]
    if args.max_lines > 0:
        candidates = candidates[: args.max_lines]

    chunks = chunked(candidates, max(1, args.chunk_size))
    updated_values: dict[int, str] = {}

    changed = 0
    token_rejects = 0
    shape_rejects = 0
    errors: list[dict[str, Any]] = []
    changes_preview: list[dict[str, Any]] = []

    for chunk_idx, batch in enumerate(chunks, start=1):
        try:
            system_text, user_text = build_prompts(batch)
            if provider == "gemini":
                raw = call_gemini_generate(
                    api_key=api_key,
                    model=args.model,
                    system_text=system_text,
                    user_text=user_text,
                    timeout=args.timeout,
                )
            else:
                raw = call_openai_chat(
                    api_key=api_key,
                    model=args.model,
                    system_text=system_text,
                    user_text=user_text,
                    timeout=args.timeout,
                )
            obj = normalize_json_payload(raw)
            items = obj.get("items")
            if not isinstance(items, list):
                raise RuntimeError("Model JSON has no 'items' list.")
        except Exception as exc:
            errors.append(
                {
                    "chunk": chunk_idx,
                    "error": str(exc),
                    "line_range": [batch[0].line_no, batch[-1].line_no],
                }
            )
            if args.request_delay > 0:
                time.sleep(args.request_delay)
            continue

        by_id: dict[int, str] = {}
        for item in items:
            if not isinstance(item, dict):
                continue
            try:
                idx = int(item.get("id"))
            except Exception:
                continue
            txt = item.get("text")
            if isinstance(txt, str):
                by_id[idx] = txt

        for cand in batch:
            src = cand.value
            dst = by_id.get(cand.index, src)

            if not dst:
                shape_rejects += 1
                continue
            if not safe_length_ratio(src, dst):
                shape_rejects += 1
                continue
            if not tokens_match(src, dst):
                token_rejects += 1
                continue

            if dst != src:
                changed += 1
                updated_values[cand.index] = dst
                if len(changes_preview) < 250:
                    changes_preview.append(
                        {
                            "line": cand.line_no,
                            "key": cand.key,
                            "before": src,
                            "after": dst,
                        }
                    )

        print(
            f"Chunk {chunk_idx}/{len(chunks)}: size={len(batch)}, changed_total={changed},"
            f" token_rejects={token_rejects}, shape_rejects={shape_rejects}, errors={len(errors)}"
        )
        if args.request_delay > 0:
            time.sleep(args.request_delay)

    out_lines = list(lines)
    for idx, new_val in updated_values.items():
        rec = parsed[idx]
        if rec is None:
            continue
        key, sep, _old, _line = rec
        out_lines[idx] = f"{key}{sep}{new_val}"

    out_text = newline.join(out_lines)
    if had_trailing_newline:
        out_text += newline

    out_path.parent.mkdir(parents=True, exist_ok=True)
    if args.dry_run or changed == 0:
        out_path.write_bytes(original_bytes)
    else:
        write_text_with_bom(out_path, out_text, had_bom)

    report = {
        "input": str(in_path),
        "output": str(out_path),
        "report": str(report_path),
        "provider": provider,
        "model": args.model,
        "chunk_size": args.chunk_size,
        "request_delay": args.request_delay,
        "timeout": args.timeout,
        "dry_run": bool(args.dry_run),
        "stats": {
            "total_lines": len(lines),
            "total_candidates": total_candidates,
            "processed_candidates": len(candidates),
            "changed": changed,
            "token_rejects": token_rejects,
            "shape_rejects": shape_rejects,
            "errors": len(errors),
        },
        "changes_preview": changes_preview,
        "errors": errors,
    }
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(
        json.dumps(report, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )

    print(f"Input:  {in_path}")
    print(f"Output: {out_path}")
    print(f"Report: {report_path}")
    print(
        "Stats: candidates={cand}, processed={proc}, changed={chg}, token_rejects={tok},"
        " shape_rejects={shape}, errors={err}".format(
            cand=total_candidates,
            proc=len(candidates),
            chg=changed,
            tok=token_rejects,
            shape=shape_rejects,
            err=len(errors),
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
