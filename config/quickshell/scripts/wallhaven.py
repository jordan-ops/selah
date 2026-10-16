#!/usr/bin/env python3
"""wallhaven.cc search / info / download — the filter set aether leaves out.

WHY this exists: aether ships `--search-wallhaven`, but its --ratios,
--top-range and --seed flags are silently ignored (verified live: identical,
unfiltered results with and without them), so a search that has to mean
"16:9, at least 1440p" cannot go through aether at all. wallhaven's v1 API is
a plain GET returning JSON, so the complete filter set lives here instead.
aether-apply.sh drives this script (`search ... --json`, then
`download <id>`), and aether keeps doing the one job it is trusted with in
this setup: the palette.

No key needed for SFW: --apikey / $WALLHAVEN_API_KEY only unlocks
sketchy/NSFW plus the account's own default filters. Anonymous requests are
capped at ~45/min (HTTP 429 when exceeded); one search plus one download per
theme apply stays far below that. The key does NOT unlock anything extra for
--similar (verified live: an apikey in the URL changes neither the challenge
nor the result set), so similar searches stay keyless.

--similar <id|url> is wallhaven's own "Search for similar..." — the API
spells it like:<id> under q (documented: tagname, -tag, +tag1 +tag2,
@user, id:123, type:png, like:wallpaper ID). Because a query that merely
starts with "like" trips a Cloudflare challenge from this client, _search()
retries that one query percent-encoded; see _search() for the measurements.

Endpoints (note /w/<id>: the obvious /api/v1/wallpaper/<id> 404s — checked
live, every id included; and the search term rides on `q=`, because
`query=` is silently ignored — checked live, it searches everything):
    /search?q=&categories=&purity=&sorting=&order=&topRange=&atleast=
           &ratios=&colors=&page=&seed=&apikey=
           q=like:<id> is the site's "Search for similar..." (see _search)
    /w/<id>            one wallpaper record, tags included
    <data.path field>  the full-size image, which `download` fetches verbatim

usage: wallhaven.py search <query...> [--similar ID|URL] [--categories 111]
                          [--purity 100] [--sorting relevance] [--order desc]
                          [--top-range 1d|3d|1w|1M|1y|all] [--at-least WxH]
                          [--ratios 16x9,21x9] [--colors [#]rrggbb[,...]]
                          [--page N] [--seed STR] [--limit N] [--json]
                          [--apikey KEY]
       wallhaven.py info <id|url> [--apikey KEY]
       wallhaven.py download <id|url> [--dest DIR] [--apikey KEY]

Output:
    search    {"results": [{id,url,resolution,category,purity,thumbs,path}],
               "meta": {...}}  pretty JSON (--json only spells out the
                               default so callers can state it)
    info      the wallpaper object (uploader, tags, ...), pretty JSON
    download  the absolute file path ALONE on stdout; progress on stderr

Query words may sit anywhere around the flags and may use wallhaven's own
syntax — ~tag, -exclude, id:123, @user, #id, like:123 — because they are
re-attached after `--` before argparse sees them (argparse would read a
bare -exclude as an unknown flag, and it refuses words placed after a
filter). Double-dash words stay flags, so a typo'd filter fails loudly
instead of quietly turning into part of the query. --similar is a value
flag for the same reason: its id must survive as a flag value rather than
become a query word.
"""

import argparse
import contextlib
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

API = "https://wallhaven.cc/api/v1"
TIMEOUT = 30
# Cloudflare answers Python's default "Python-urllib/3.x" user agent with a
# 403 (checked live), so EVERY request — API and image — carries a browser UA.
UA = ("Mozilla/5.0 (X11; Linux x86_64; rv:128.0) "
      "Gecko/20100101 Firefox/128.0")
DEFAULT_DEST = Path.home() / ".cache" / "wallhaven"

# Exactly the fields callers may rely on: aether-apply.sh reads id (to pick)
# and, via download, the path; a browser would want thumbs and resolution.
# A fixed shape means API additions can never change this output.
RESULT_FIELDS = ("id", "url", "resolution", "category", "purity", "thumbs",
                 "path")

# Search flags that take a value: _normalize_search_argv needs this to know
# where a flag's value ends, so it must stay in sync with build_parser().
VALUE_FLAGS = frozenset({
    "--categories", "--purity", "--sorting", "--order", "--top-range",
    "--at-least", "--ratios", "--colors", "--page", "--seed", "--limit",
    "--apikey", "--similar",
})

SORTINGS = ("date_added", "relevance", "random", "views", "favorites",
            "toplist")
# 3M and 6M also exist per the docs; these are the ones the UI offers and
# the set aether-apply.sh documents, so the CLI stays deliberately small.
TOP_RANGES = ("1d", "3d", "1w", "1M", "1y", "all")

AT_LEAST_RE = re.compile(r"^\d+x\d+$")
COLORS_RE = re.compile(r"^[0-9a-fA-F]{6}(,[0-9a-fA-F]{6})*$")
ID_RE = re.compile(r"^[A-Za-z0-9]{2,16}$")
FILE_TYPE_EXT = {"image/jpeg": "jpg", "image/png": "png",
                 "image/webp": "webp"}


class WallhavenError(Exception):
    """A failure worth exactly one clean line on stderr (see main()).

    challenge marks the failures Cloudflare created (403 + cf-mitigated) as
    opposed to wallhaven's own — see _is_challenge(). It stays False for
    every other error, class-wide, so callers can test it with getattr().
    """
    challenge = False


# --- argparse validators -----------------------------------------------------
# Failures here exit with argparse's usual code 2 and its own formatting, so
# a bad filter never reaches the network and never looks like an API error.

def at_least(text):
    """--at-least: '2560x1440', nothing else (wallhaven 400s on junk)."""
    if not AT_LEAST_RE.match(text):
        raise argparse.ArgumentTypeError(
            "--at-least wants WxH (e.g. 2560x1440), got: " + text)
    return text


def colors(text):
    """--colors: hex list with '#' optional — the API wants bare rrggbb."""
    cleaned = ",".join(part.lstrip("#") for part in text.split(","))
    if not COLORS_RE.match(cleaned):
        raise argparse.ArgumentTypeError(
            "--colors wants rrggbb or #rrggbb (comma list ok), got: " + text)
    return cleaned


def positive_int(text):
    """--page/--limit: whole number above zero."""
    if not text.isdigit() or int(text) < 1:
        raise argparse.ArgumentTypeError(
            "wants an integer >= 1, got: " + text)
    return int(text)


# --- argv pre-processing -----------------------------------------------------
def _normalize_search_argv(argv):
    """Re-arrange `search`'s arguments so query words can look like words.

    wallhaven's query syntax includes single-dash terms (-exclude), which
    argparse would reject as unknown flags, and argparse also refuses words
    that follow a filter (`search big --at-least 1x1 night` leaves `night`
    unassigned). So every token that is not a double-dash flag (nor -h) or
    a flag's value becomes a query word, flags stay in order, and the words
    are re-attached after `--`, where argparse treats them purely as
    positionals. Unknown double-dash flags pass through untouched and
    therefore still fail loudly.
    """
    try:
        idx = argv.index("search")
    except ValueError:
        return argv
    words = []
    opts = []
    seen_sep = False
    i = idx + 1
    while i < len(argv):
        tok = argv[i]
        i += 1
        if seen_sep:
            words.append(tok)
            continue
        if tok == "--":
            seen_sep = True
            continue
        if tok == "-h" or tok.startswith("--"):
            opts.append(tok)
            name, eq, _ = tok.partition("=")
            # A space-separated value is swallowed verbatim — even when it
            # starts with a dash (--seed -x must not read -x as a flag).
            if eq == "" and name in VALUE_FLAGS and i < len(argv):
                opts.append(argv[i])
                i += 1
            continue
        # Everything else is query text: plain words AND wallhaven's
        # single-dash terms (-exclude), which argparse would reject as
        # unknown flags. Only double-dash words are flags here.
        words.append(tok)
    return argv[: idx + 1] + opts + (["--"] if words else []) + words


# --- HTTP --------------------------------------------------------------------
def _error_body(exc):
    """The response body of an HTTPError, decoded, best effort.

    Read exactly once per failure: _http_error() wants it for wallhaven's
    own error text and _is_challenge() for Cloudflare's marker page, and
    the first read consumes the stream.
    """
    try:
        return exc.read().decode("utf-8", "replace")
    except (ValueError, AttributeError, OSError):
        return ""


def _is_challenge(exc, body):
    """True when a 403 came from Cloudflare's bot check, not from wallhaven.

    wallhaven's own refusals arrive as JSON ({"error": ...}) with a normal
    403; a managed challenge is flagged cf-mitigated: challenge and carries
    an HTML "Just a moment ..." page instead. Telling them apart is what
    lets _search() retry once instead of handing the user a bare
    "forbidden" for a request wallhaven would have served.
    """
    if getattr(exc, "code", None) != 403:
        return False
    headers = getattr(exc, "headers", None)
    mitigated = headers.get("cf-mitigated") if headers is not None else None
    if mitigated is not None and str(mitigated).lower() == "challenge":
        return True
    return "Just a moment" in body


def _http_error(exc, what, body=None):
    """One human line per failure mode wallhaven actually uses."""
    if body is None:
        body = _error_body(exc)
    detail = ""
    try:
        detail = str(json.loads(body).get("error") or "")
    except (ValueError, AttributeError, OSError):
        pass
    if exc.code == 429:
        base = "rate limited — wallhaven allows 45 requests/min, wait a minute"
    elif exc.code == 401:
        base = "unauthorized — the API key is missing or invalid"
    elif exc.code == 403:
        base = "forbidden — wallhaven refused this client"
    elif exc.code == 404:
        base = "not found"
    else:
        base = "HTTP {0} {1}".format(exc.code, exc.reason)
    msg = "{0}: {1}".format(what, base)
    if detail and detail.lower() not in base.lower():
        msg += " ({0})".format(detail)
    return msg


def api_get(path, params, what, raw_query_keys=()):
    """GET an API endpoint; return the decoded body or raise WallhavenError.

    raw_query_keys names params whose value is ALREADY in its wire form and
    must not be escaped a second time — _search()'s challenge retry is the
    only user, and it exists because urlencode() would turn %6C into %256C,
    handing wallhaven the escape text instead of the query (checked live:
    total 0, meta.query "%6C%69...").
    """
    pairs = []
    for key, val in params.items():
        if val in (None, ""):
            continue
        # raw_query_keys keep the wire form they already carry; everything
        # else is escaped exactly the way urlencode() would have escaped it.
        value = str(val)
        if key not in raw_query_keys:
            value = urllib.parse.quote_plus(value)
        pairs.append("{0}={1}".format(urllib.parse.quote_plus(key), value))
    url = API + path
    if pairs:
        url += "?" + "&".join(pairs)
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            raw = resp.read()
    except urllib.error.HTTPError as exc:
        body = _error_body(exc)
        err = WallhavenError(_http_error(exc, what, body))
        if _is_challenge(exc, body):
            err.challenge = True
        raise err from None
    except urllib.error.URLError as exc:
        raise WallhavenError(
            "{0}: cannot reach wallhaven ({1})".format(what, exc.reason)) from None
    except TimeoutError:
        raise WallhavenError(
            "{0}: wallhaven timed out after {1}s".format(what, TIMEOUT)) from None
    try:
        doc = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise WallhavenError(
            "{0}: wallhaven sent invalid JSON ({1})".format(what, exc)) from None
    if isinstance(doc, dict) and doc.get("error"):
        # Some failures arrive as HTTP 200 with an error body; never let
        # them masquerade as a valid empty result.
        raise WallhavenError("{0}: {1}".format(what, doc["error"]))
    return doc


def _apikey(args):
    """Flag beats environment; empty means anonymous (fine for SFW)."""
    return args.apikey or os.environ.get("WALLHAVEN_API_KEY") or ""


# --- shared fetch ------------------------------------------------------------
def extract_id(ref):
    """Accept a bare id, https://wallhaven.cc/w/<id> or https://whvn.cc/<id>."""
    ref = ref.strip()
    if ID_RE.match(ref):
        return ref
    tail = [seg for seg in urllib.parse.urlparse(ref).path.split("/") if seg]
    if tail and ID_RE.match(tail[-1]):
        # ID_RE keeps only [A-Za-z0-9]{2,16}: no slashes, no '..', nothing
        # that could escape the URL path this is pasted into.
        return tail[-1]
    raise WallhavenError("cannot read a wallpaper id from: " + ref)


def _wallpaper(wid, args):
    """GET /w/<id> — deliberately /w/, because /wallpaper/<id> 404s."""
    doc = api_get("/w/" + wid, {"apikey": _apikey(args)},
                  "wallpaper " + wid)
    data = doc.get("data") if isinstance(doc, dict) else None
    if not isinstance(data, dict):
        raise WallhavenError("wallpaper {0}: no data in response".format(wid))
    return data


def _image_ext(src, file_type):
    """jpg/png/webp from the path suffix, file_type as the fallback."""
    suffix = os.path.splitext(urllib.parse.urlparse(src).path)[1]
    suffix = suffix.lstrip(".").lower()
    if suffix == "jpeg":
        return "jpg"
    if suffix in ("jpg", "png", "webp"):
        return suffix
    return FILE_TYPE_EXT.get(file_type, "jpg")


# --- commands ----------------------------------------------------------------
def _wire_encode(text):
    """Percent-encode every byte of a query value.

    wallhaven decodes it server-side — meta.query echoes the original
    string — so this is the SAME query on a different wire encoding, not a
    different search. It must then reach the wire verbatim (see api_get's
    raw_query_keys): url-escaping it again would search for "%6C...".
    It exists purely for the challenge in _search().
    """
    return "".join("%{0:02X}".format(b) for b in text.encode("utf-8"))


def _search(params):
    """GET /search, with one encoded retry when Cloudflare challenges us.

    Why the retry exists (measured live, 2026-10, same IP and UA seconds
    apart): `like:<id>` — and any query merely STARTING with "like" — comes
    back 403 with `cf-mitigated: challenge`, while every other word returns
    200; an apikey in the URL changes nothing (403 with a key, 401 on a bad
    key with an ordinary query, so the origin is never even reached for the
    challenged form). The rule matches the RAW query string: `q=%6cike...`
    passes and meta.query reads back `like:...`. So one retry with the whole
    query percent-encoded costs a single extra request, only in the case
    that would otherwise just fail.
    """
    try:
        return api_get("/search", params, "search")
    except WallhavenError as exc:
        if not exc.challenge or not params.get("q"):
            raise
    retry = dict(params)
    retry["q"] = _wire_encode(params["q"])
    print("wallhaven.py: cloudflare challenged this query, retrying it "
          "percent-encoded ...", file=sys.stderr)
    # raw_query_keys: the encoding IS the point, urlencode() would undo it.
    return api_get("/search", retry, "search", raw_query_keys=("q",))


def cmd_search(args):
    query = " ".join(args.query)
    if args.similar:
        # wallhaven's wording is "Search for similar..."; the API spells it
        # like:<id>. extract_id() already accepts a bare id or either URL
        # form, and rejects anything else before a request is made.
        query = "like:" + extract_id(args.similar)
    params = {
        # `q`, NOT `query`: wallhaven silently ignores `query=` (verified
        # live — unfiltered results, meta.query null), which would let the
        # search look like it worked while dropping the words entirely.
        "q": query,
        "categories": args.categories,
        "purity": args.purity,
        "sorting": args.sorting,
        "order": args.order,
        "page": args.page,
        "apikey": _apikey(args),
    }
    # Sent only when actually given, so every other default stays the API's
    # own. seed is forwarded despite being currently ignored by wallhaven
    # (checked live 2026-10: it regenerates a fresh seed every request, even
    # for seeds it issued itself) — costs nothing, works if they fix it.
    if args.top_range:
        params["topRange"] = args.top_range
    if args.at_least:
        params["atleast"] = args.at_least
    if args.ratios:
        params["ratios"] = args.ratios
    if args.colors:
        params["colors"] = args.colors
    if args.seed:
        params["seed"] = args.seed

    doc = _search(params)
    data = doc.get("data") if isinstance(doc, dict) else None
    results = [{k: w.get(k) for k in RESULT_FIELDS}
               for w in (data or []) if isinstance(w, dict)]
    if args.limit is not None:
        results = results[:args.limit]
    json.dump({"results": results, "meta": (doc.get("meta") or {})},
              sys.stdout, indent=2)
    print()
    return 0


def cmd_info(args):
    wid = extract_id(args.ref)
    data = _wallpaper(wid, args)
    json.dump(data, sys.stdout, indent=2)
    print()
    return 0


def cmd_download(args):
    wid = extract_id(args.ref)
    data = _wallpaper(wid, args)
    src = data.get("path")
    if not src:
        raise WallhavenError(
            "wallpaper {0} has no full-size path".format(wid))
    ext = _image_ext(src, data.get("file_type") or "")

    dest_dir = Path(args.dest).expanduser()
    try:
        dest_dir.mkdir(parents=True, exist_ok=True)
        dest = (dest_dir / "wallhaven-{0}.{1}".format(wid, ext)).resolve()
    except OSError as exc:
        raise WallhavenError(
            "cannot prepare {0}: {1}".format(dest_dir, exc)) from None

    if dest.is_file():
        # Already have it: the caller wants the PATH, not the bytes, so
        # skipping still prints it — re-applying a wallpaper stays idempotent.
        print(dest)
        print("wallhaven.py: {0} already present, skipping download"
              .format(dest.name), file=sys.stderr)
        return 0

    size = data.get("file_size") or 0
    human = "{0:.1f} MiB".format(size / 1048576) if size else "unknown size"
    print("wallhaven.py: downloading {0} ({1}) ...".format(wid, human),
          file=sys.stderr)

    # Bytes land in a .part file first: an interrupted run must never leave
    # a truncated image under the final name for the next run to "skip".
    part = dest.with_name(dest.name + ".part")
    req = urllib.request.Request(src, headers={"User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            with open(part, "wb") as fh:
                while True:
                    chunk = resp.read(64 * 1024)
                    if not chunk:
                        break
                    fh.write(chunk)
        os.replace(part, dest)
    except urllib.error.HTTPError as exc:
        raise WallhavenError(
            _http_error(exc, "image for " + wid)) from None
    except urllib.error.URLError as exc:
        raise WallhavenError(
            "image for {0}: cannot fetch ({1})".format(wid, exc.reason)) from None
    except OSError as exc:
        raise WallhavenError(
            "image for {0}: {1}".format(wid, exc)) from None
    finally:
        with contextlib.suppress(OSError):
            part.unlink(missing_ok=True)   # no-op once replaced

    print("wallhaven.py: saved {0}".format(dest.name), file=sys.stderr)
    print(dest)                            # stdout carries ONLY the path
    return 0


def build_parser():
    parser = argparse.ArgumentParser(
        prog="wallhaven.py",
        description="search / inspect / fetch wallpapers from wallhaven.cc")
    sub = parser.add_subparsers(dest="command", required=True)

    def add_apikey(sp):
        sp.add_argument("--apikey", metavar="KEY", default=None,
                        help="wallhaven API key "
                             "(default: $WALLHAVEN_API_KEY)")

    sp = sub.add_parser("search",
                        help="search; pretty JSON {results, meta} on stdout")
    add_apikey(sp)
    sp.add_argument("query", nargs="*", metavar="word",
                    help="expression; wallhaven syntax passes through "
                         "(~tag, -exclude, id:123, @user, #id, like:123); "
                         "replaced, not joined, by --similar")
    sp.add_argument("--similar", metavar="ID|URL", default=None,
                    help="search for wallpapers LIKE this one — wallhaven's "
                         "own 'Search for similar...' (id or wallhaven URL); "
                         "needs no API key")
    sp.add_argument("--categories", default="111", metavar="MASK",
                    help="general/anime/people bitmask (default: 111)")
    sp.add_argument("--purity", default="100", metavar="MASK",
                    help="sfw/sketchy/nsfw bitmask (default: 100; "
                         "sketchy/nsfw need an API key)")
    sp.add_argument("--sorting", choices=SORTINGS, default="relevance",
                    help="default: relevance")
    sp.add_argument("--order", choices=("desc", "asc"), default="desc",
                    help="default: desc")
    sp.add_argument("--top-range", dest="top_range", choices=TOP_RANGES,
                    help="toplist window; only used with --sorting toplist")
    sp.add_argument("--at-least", dest="at_least", type=at_least,
                    metavar="WxH", help="minimum resolution, e.g. 2560x1440")
    sp.add_argument("--ratios", metavar="LIST", default=None,
                    help="comma list of aspect ratios, e.g. 16x9,21x9")
    sp.add_argument("--colors", type=colors, metavar="HEX[,HEX]", default=None,
                    help="dominant colour(s), rrggbb or #rrggbb")
    sp.add_argument("--page", type=positive_int, default=1, metavar="N",
                    help="results page (default: 1)")
    sp.add_argument("--seed", metavar="STR", default=None,
                    help="seed for --sorting random (passed through; the API "
                         "currently ignores it, see the docstring)")
    sp.add_argument("--limit", type=positive_int, metavar="N", default=None,
                    help="keep only the first N of the fetched page")
    sp.add_argument("--json", action="store_true",
                    help="pretty JSON (already the default; spelled out so "
                         "callers can state it)")
    sp.set_defaults(func=cmd_search)

    ip = sub.add_parser("info", help="one wallpaper's full record as JSON")
    add_apikey(ip)
    ip.add_argument("ref", metavar="id|url",
                    help="e.g. 85jxjo or https://wallhaven.cc/w/85jxjo")
    ip.set_defaults(func=cmd_info)

    dp = sub.add_parser("download",
                        help="fetch the full image (absolute path on stdout)")
    add_apikey(dp)
    dp.add_argument("ref", metavar="id|url", help="as for info")
    dp.add_argument("--dest", metavar="DIR", default=str(DEFAULT_DEST),
                    help="destination directory (default: {0})"
                         .format(DEFAULT_DEST))
    dp.set_defaults(func=cmd_download)
    return parser


def main(argv=None):
    argv = list(sys.argv[1:]) if argv is None else list(argv)
    argv = _normalize_search_argv(argv)
    parser = build_parser()
    args = parser.parse_args(argv)
    if getattr(args, "command", None) == "search":
        # --similar and query words are two ways to say WHAT to search for.
        # query is nargs="*" so either can be left out — which also means
        # both can be wrong, and both mistakes get named here, before any
        # request is made.
        if args.similar and args.query:
            parser.error("--similar replaces the query words, "
                         "it does not add to them")
        if not args.similar and not args.query:
            parser.error("search wants query words, or --similar <id|url>")
    try:
        return args.func(args)
    except WallhavenError as exc:
        print("wallhaven.py: " + str(exc), file=sys.stderr)
        return 1
    except OSError as exc:
        # Filesystem trouble that slipped past the narrower catches
        # (unwritable dest, disk full): still one clean line, no traceback.
        print("wallhaven.py: " + str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
