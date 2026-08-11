# Lyrics provider and matching

## Provider boundary

Lyrics lookup is isolated behind `LyricsProvider`:

```swift
public protocol LyricsProvider: Sendable {
    var providerName: String { get }
    func searchLyrics(for query: LyricsQuery) async throws -> [LyricsCandidate]
}
```

The protocol returns candidates rather than a single assumed match. Provider-neutral domain code owns normalization, scoring, ambiguity handling, LRC parsing, and timeline selection. Replacing LRCLIB therefore does not require changes to views, the synchronization engine, or the Rokid transport boundary.

`LyricsCandidate` can contain plain lyrics, synchronized LRC lyrics, or an instrumental marker. The playback pipeline requires nonempty synchronized lyrics; plain-only results remain useful metadata/search results but cannot drive the current timeline.

## LRCLIB implementation

`LRCLibLyricsProvider` uses the public `GET /api/search` endpoint documented at [LRCLIB API Documentation](https://lrclib.net/docs). It does not use database dumps, publish records, mirror the database, or ship fetched lyrics in this repository.

### Request

The provider sends:

| HTTP field | Value |
| --- | --- |
| Method | `GET` |
| URL | `https://lrclib.net/api/search` by default |
| `track_name` | Required `LyricsQuery.title` |
| `artist_name` | Required `LyricsQuery.artist` |
| `album_name` | Included when nonempty |
| `Accept` | `application/json` |
| `User-Agent` | App name, version, and project URL |
| Request timeout | 15 seconds |

Duration is not sent to `/api/search`; it is used locally to distinguish returned candidates. LRCLIB documents that search accepts field-specific title, artist, and album parameters, returns at most 20 records, and currently has no pagination.

### Response mapping

The documented response fields are decoded as follows:

| LRCLIB field | Domain field |
| --- | --- |
| `id` | String `LyricsCandidate.id` |
| `trackName` | `trackTitle` |
| `artistName` | `artistName` |
| `albumName` | `albumName` |
| `duration` | `duration` |
| `instrumental` | `isInstrumental` |
| `plainLyrics` | `plainLyrics` |
| `syncedLyrics` | `synchronizedLyrics` |

A non-2xx response is an error, not an empty result. Invalid JSON is a decoding error, not “no lyrics.” Cancellation propagates to the caller.

### Networking and retry behavior

The default HTTP client uses an ephemeral `URLSession`, disables the system URL cache, and sets 15-second request and 30-second resource timeouts. It performs at most two retries for transient network errors and retryable HTTP status codes (`408`, `425`, `429`, and `5xx`). Cancellation is never retried.

Backoff is bounded. When LRCLIB supplies a `Retry-After` interval that is within the configured retry ceiling, the client waits that interval. A server interval beyond the local ceiling is not shortened and retried early; the request fails so the caller can try again later. This is intended to respect LRCLIB's documented rate-limit requirement without holding an app task for an unbounded time. The app performs single interactive searches rather than bulk database scans.

## Runtime cache

Caching is optional at the provider boundary. The iPhone app injects `DiskLyricsCache` using its Caches directory with these defaults:

- maximum 100 entries;
- 30-day lifetime;
- atomic JSON writes;
- oldest-modified files pruned when the entry limit is exceeded;
- expired entries removed on access;
- cache errors ignored so they never turn a valid network lookup into a user-facing failure.

The key contains canonically composed, lowercased title, artist, album, and duration, separated unambiguously and hashed for the filename. The cached value contains the complete provider candidates, including any plain and synchronized lyrics returned by LRCLIB. This is local runtime data, not source-controlled content. There is currently no in-app “clear lyrics cache” control; the OS may purge Caches data, and uninstalling removes app sandbox data.

`MemoryLyricsCache` is available for tests and alternate compositions. It also caps entries at 100 by default, but it is process-lifetime only.

## Conservative normalization

`LyricsMetadataNormalizer` is designed to reduce obvious formatting differences without erasing meaningful identity.

It performs:

- canonical Unicode composition;
- case-insensitive folding;
- width-insensitive folding, including full-width Latin variants;
- whitespace/newline collapse and trim;
- normalization of curly apostrophes to `'`;
- normalization of common en/em/minus dashes to `-`;
- limited trailing `feat.`, `ft.`, and `featuring` handling;
- limited recognition of version descriptors such as live, acoustic, edit, instrumental, remix/mix, remaster, mono/stereo, slowed, and sped-up variants.

It intentionally does **not**:

- strip accents/diacritics;
- transliterate Japanese, Chinese, or Korean text;
- convert scripts;
- remove arbitrary punctuation wholesale;
- discard arbitrary parenthetical/bracketed content;
- treat every parenthetical suffix as a version;
- delete featured text unless an explicit supported marker is present.

That balance allows canonically equivalent accented Latin strings and exact CJK metadata to match while preserving version information that can prevent a false positive.

## Match score

The scorer is deterministic and provider-independent.

| Component | Maximum weight | Behavior |
| --- | ---: | --- |
| Title | 0.60 | Exact normalized title is strongest. Same core title with an absent/present or conflicting version is penalized. Otherwise token/character similarity is used. |
| Artist | 0.35 | Exact normalized artist is strongest. A match after conservative featured-artist removal receives a small penalty. Otherwise token/character similarity is used. |
| Album | 0.03 | Used only when both query and candidate supply an album. |
| Duration | 0.02 | Used only when both sides supply positive durations. |

Optional weights are not redistributed. Exact title and artist therefore score `0.95` without album or duration, which is sufficient for automatic consideration.

Duration similarity is:

- `1.00` within 2 seconds;
- `0.75` within 5 seconds;
- `0.35` within 10 seconds;
- `0.00` beyond 10 seconds.

Fuzzy text similarity takes the larger of a token Dice coefficient and `0.90 ×` normalized Levenshtein character similarity. Values below `0.45` are treated as zero. Character comparison is capped at the first 256 characters to bound work on unreasonable metadata.

Default selection rules:

- minimum total score: `0.72`;
- ambiguity window: `0.025` from the best score;
- exactly one plausible candidate: `.match`;
- two or more plausible candidates in the ambiguity window: `.ambiguous`;
- no candidate at the threshold: `.noMatch`;
- ties are ordered by provider candidate ID for deterministic output.

The app's automatic path first filters out instrumental candidates and records with missing/empty synchronized lyrics. It automatically activates only a unique safe match among the remaining candidates. Ambiguous and no-match cases go to the search screen rather than being guessed. Users can also run a manual title/artist search and select returned candidates.

### Current activation rule

After selection, activation rejects records marked instrumental, records without synchronized lyrics, and synchronized text with no usable timestamps. These errors are surfaced rather than falling back to untimed plain lyrics. Automatic filtering prevents a high-scoring plain-only record from obscuring a suitable synchronized alternative; a user can still choose an unusable record from a transparent manual result list and receive the explicit error.

## LRC parsing

The provider returns synchronized text; `LRCParser` converts it into the domain timeline. Supported forms include:

- `[m:ss]`
- `[mm:ss.x]`
- `[mm:ss.xx]`
- `[mm:ss.xxx]`
- `[h:mm:ss.xxx]`
- multiple leading timestamps on one lyric line;
- metadata tags;
- `[offset:milliseconds]`;
- Unicode/CJK text;
- timestamped empty lines;
- duplicate timestamps with stable source order.

Malformed and untimed lines are ignored. Parsed lines are sorted by timestamp and then by source ID. No test fixture contains real song lyrics.

## Copyright and responsible use

- Lyrics are fetched only in response to a user action and cached in a bounded local cache.
- The repository contains no fetched lyric dump and no real-song lyric fixtures or screenshots.
- The client does not call LRCLIB's publish endpoint.
- Provider availability, rights, accuracy, and record quality are not guaranteed by this project.
- Contributors must use short fictional text in tests and documentation.
- Deployers are responsible for reviewing LRCLIB's current terms, applicable law, and their intended distribution model.

## Provider test coverage

Stubbed tests verify documented response decoding, client identification, HTTP error surfacing, invalid JSON, cancellation, and cache hits. Matching tests cover exact metadata, artist mismatch, featured syntax, canonical Unicode composition, CJK, full-width Latin, version conflicts, arbitrary parentheses, optional album/duration, and ambiguity.

No default test contacts LRCLIB, downloads lyrics, or requires network access. Live-service and content-quality validation is a separate manual test and must not use copyrighted lyrics in committed evidence.
