#!/usr/bin/env python3
"""Checks the site's strings. Run from the branch root: python3 tools/check_i18n.py

- every key used in index.html, docs.html and privacy.html exists in i18n/en.json, and every en.json key is used;
- the English text in the HTML equals i18n/en.json (the JSON is the authored source);
- each i18n/<lang>.json has exactly the English keys, no empty values and the same `backtick` spans;
- each file is really in its language: the script of its letters (Arabic, Devanagari, Hangul, ...), and for
  languages that share a script a few telltale letters or words (zh-Hans against zh-Hant, ru against uk,
  ar against fa against ur, hi against mr, id against ms, the Latin-script languages against each other), and not
  left in English. The telltale lists are short, so this catches a swapped or copied file, not a bad translation;
- every <option> of the language switcher has a file (a missing file is reported, not fatal: English is the fallback).

A correct file name does not prove the text inside is in that language, which is why the content is checked.
"""
import html
import json
import pathlib
import re
import sys
import unicodedata
from collections import Counter

ROOT = pathlib.Path(__file__).resolve().parent.parent
en = json.loads((ROOT / "i18n/en.json").read_text(encoding="utf-8"))
errors, notes = [], []

used = set()
for page in ("index.html", "docs.html", "privacy.html"):
    text = (ROOT / page).read_text(encoding="utf-8")
    keys = re.findall(r'data-i18n(?:-[a-z-]+)?="([^"]+)"', text)
    used.update(keys)
    for k in keys:
        if k not in en:
            errors.append(f"{page}: key {k} is not in en.json")
    for m in re.finditer(r'<(\w+)[^>]*?\sdata-i18n="([^"]+)"[^>]*>(.*?)</\1>', text, re.S):
        tag, key, inner = m.groups()
        if key not in en:
            continue
        shown = html.unescape(re.sub(r"</?code>", "`", inner))
        if shown != en[key]:
            errors.append(f"{page}: text of {key} differs from en.json")
    options = re.findall(r'<option value="([^"]+)"', text)
    for code in options:
        if not (ROOT / f"i18n/{code}.json").exists():
            notes.append(f"{page}: no i18n/{code}.json (falls back to English)")

for k in en:
    if k not in used:
        errors.append(f"key {k} is in en.json but unused")

ticks = lambda s: sorted(set(re.findall(r"`([^`]*)`", s)))  # word order may differ per language

# --- is the content in the language its file name says? -------------------------------------------------------
SCRIPT = {"ar": "ARABIC", "fa": "ARABIC", "ur": "ARABIC", "he": "HEBREW", "hi": "DEVANAGARI", "mr": "DEVANAGARI",
          "bn": "BENGALI", "ta": "TAMIL", "te": "TELUGU", "th": "THAI", "ko": "HANGUL", "el": "GREEK",
          "ru": "CYRILLIC", "uk": "CYRILLIC", "ja": "JAPANESE", "zh-Hans": "CJK", "zh-Hant": "CJK"}
LATIN_GROUP = {"de": "de", "es": "es", "fr": "fr", "it": "it", "nl": "nl", "pl": "pl", "pt-BR": "pt", "ro": "ro",
               "tr": "tr", "vi": "vi", "id": "idms", "ms": "idms"}
FUNCTION_WORDS = {
    "de": "und nicht mit für eine ist den auf dem nur sich auch wird".split(),
    "es": "los las para del por una pero sin como más también puede".split(),
    "fr": "les des pour avec une dans est sur pas aussi peut sont".split(),
    "it": "gli che per con una nel del dei della sono non anche può".split(),
    "nl": "het een van voor met niet ook naar wordt zijn kan".split(),
    "pl": "nie jest się dla że na oraz jako przez lub może".split(),
    "pt": "para com uma não você ou também pode mais são pelo".split(),
    "ro": "și şi pentru este într un nu sau mai care poate".split(),
    "tr": "ve bir için ile değil olarak veya daha çok olan".split(),
    "vi": "và của là một các không với cho được trong".split(),
    "idms": "yang dan untuk dengan tidak ini atau dari akan pada".split(),
}
# Words that one language of a close pair uses and the other does not (calibrated on the real files: the right
# language has dozens of them, the other one almost none).
PAIR_WORDS = {
    "hi": "है और नहीं में को हैं".split(), "mr": "आहे आणि नाही मध्ये".split(),
    "id": "pengaturan bisa sudah".split(), "ms": "fail tetapan boleh kepada".split(),
}
PAIR = {"hi": "mr", "mr": "hi", "id": "ms", "ms": "id"}
HANS = "这个设们说务页档发时对关还从应过"
HANT = "這個設們說務頁檔發時對關還從應過"
HANS_ONLY = [h for h, t in zip(HANS, HANT) if h != t]
HANT_ONLY = [t for h, t in zip(HANS, HANT) if h != t]


def letters(text):
    for ch in text:
        if ch.isalpha():
            yield ch


def script_of(ch):
    name = unicodedata.name(ch, "")
    for prefix in ("ARABIC", "HEBREW", "DEVANAGARI", "BENGALI", "TAMIL", "TELUGU", "THAI", "HANGUL", "GREEK",
                   "CYRILLIC", "HIRAGANA", "KATAKANA", "CJK", "LATIN"):
        if name.startswith(prefix):
            return {"HIRAGANA": "JAPANESE", "KATAKANA": "JAPANESE"}.get(prefix, prefix)
    return "OTHER"


def prose(value):
    return re.sub(r"`[^`]*`", " ", value)


def check_language(code, data):
    problems = []
    body = " ".join(prose(v) for v in data.values() if isinstance(v, str))
    counts = Counter(script_of(c) for c in letters(body))
    total = sum(counts.values()) or 1
    expected = SCRIPT.get(code)
    if expected:
        if expected == "JAPANESE":
            share = (counts["JAPANESE"] + counts["CJK"]) / total
            if counts["JAPANESE"] < 50:
                problems.append("no kana: this is not Japanese")
        else:
            share = counts[expected] / total
        if share < 0.55:
            problems.append(f"only {share:.0%} of the letters are {expected.lower()}")
    else:
        share = counts["LATIN"] / total
        if share < 0.85:
            problems.append(f"only {share:.0%} of the letters are Latin")
    if code in ("zh-Hans", "zh-Hant"):
        hans = sum(body.count(c) for c in HANS_ONLY)
        hant = sum(body.count(c) for c in HANT_ONLY)
        mine, other = (hans, hant) if code == "zh-Hans" else (hant, hans)
        if mine < 10 or other > mine // 10:
            problems.append(f"simplified/traditional mix-up ({hans} simplified-only, {hant} traditional-only characters)")
    if code in ("ru", "uk"):
        uk = sum(body.count(c) for c in "іїєґІЇЄҐ")
        ru = sum(body.count(c) for c in "ыэъЫЭЪ")
        if code == "uk" and (uk < 10 or ru > 2):
            problems.append(f"does not look Ukrainian (uk letters {uk}, ru-only letters {ru})")
        if code == "ru" and (ru < 10 or uk > 2):
            problems.append(f"does not look Russian (ru letters {ru}, uk-only letters {uk})")
    if code in ("ar", "fa", "ur"):
        fa_ur = sum(body.count(c) for c in "پچژگکی")  # Persian/Urdu letters; Arabic has ك and ي instead of ک and ی
        ar = sum(body.count(c) for c in "ةيك")
        ur_only = sum(body.count(c) for c in "ٹڈڑںےہھ")
        if code == "ar" and (ar < 20 or fa_ur > ar // 10):
            problems.append(f"does not look Arabic (arabic letters {ar}, persian/urdu letters {fa_ur})")
        if code == "fa" and (fa_ur < 20 or ur_only > 2):
            problems.append(f"does not look Persian (persian letters {fa_ur}, urdu-only letters {ur_only})")
        if code == "ur" and ur_only < 10:
            problems.append(f"does not look Urdu (urdu-only letters {ur_only})")
    if code in PAIR:
        words = Counter(re.findall(r"[\wऀ-ॿ]+", body.lower()))
        own = sum(words[w] for w in PAIR_WORDS[code])
        other = sum(words[w] for w in PAIR_WORDS[PAIR[code]])
        if own < 8 or other * 3 > own:
            problems.append(f"does not look like {code} rather than {PAIR[code]} (telltale words: {own} of {code}, {other} of {PAIR[code]})")
    group = LATIN_GROUP.get(code)
    if group:
        words = Counter(re.findall(r"[^\W\d_]+", body.lower()))
        score = {g: sum(words[w] for w in ws) for g, ws in FUNCTION_WORDS.items()}
        best = max(score, key=score.get)
        if best != group or score[group] < 10:
            problems.append(f"function words look like {best}, not {group}: {dict(sorted(score.items(), key=lambda kv: -kv[1])[:3])}")
    same = [k for k, v in data.items() if k in en and v == en[k] and len(re.findall(r"[A-Za-z]", prose(en[k]))) >= 20]
    if len(same) > 3:
        problems.append(f"{len(same)} long strings are still English, for example {same[:3]}")
    return problems


for path in sorted((ROOT / "i18n").glob("*.json")):
    if path.name == "en.json":
        continue
    code = path.stem
    data = json.loads(path.read_text(encoding="utf-8"))
    missing, extra = set(en) - set(data), set(data) - set(en)
    if missing:
        errors.append(f"{path.name}: missing {sorted(missing)[:5]}")
    if extra:
        errors.append(f"{path.name}: extra {sorted(extra)[:5]}")
    for k, v in data.items():
        if k in en:
            if not isinstance(v, str) or not v.strip():
                errors.append(f"{path.name}: empty {k}")
            elif ticks(v) != ticks(en[k]):
                errors.append(f"{path.name}: code spans of {k} changed: {ticks(v)} vs {ticks(en[k])}")
            if "<" in v and k in en and "<" not in en[k]:
                errors.append(f"{path.name}: {k} contains markup")
    for problem in check_language(code, data):
        errors.append(f"{path.name}: {problem}")

for n in sorted(set(notes)):
    print("note:", n)
for e in errors:
    print("ERROR:", e)
print("languages:", len(list((ROOT / "i18n").glob("*.json"))), "files;", len(errors), "errors")
sys.exit(1 if errors else 0)
