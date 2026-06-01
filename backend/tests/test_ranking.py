"""Pure unit tests for the ranker (no network) — the correctness core."""
from app.search.ranking import score_candidate

PARSED = {"artist": "Artist", "title": "Song", "is_obscure": False}


def test_long_loop_ranks_below_real_track():
    real = {"video_id": "a", "title": "Artist - Song", "duration_sec": 200}
    loop = {"video_id": "b", "title": "Artist - Song (1 hour loop)", "duration_sec": 3600}
    sim = 0.9
    assert score_candidate(real, PARSED, sim) > score_candidate(loop, PARSED, sim)


def test_topic_channel_beats_random_upload():
    topic = {"video_id": "a", "title": "Artist - Song", "channel": "Artist - Topic",
             "source_hint": "topic", "duration_sec": 200}
    rando = {"video_id": "b", "title": "Artist - Song", "channel": "SomeGuy123",
             "source_hint": "other", "duration_sec": 200}
    sim = 0.9
    assert score_candidate(topic, PARSED, sim) > score_candidate(rando, PARSED, sim)


def test_reaction_and_cover_rank_below_clean():
    clean = {"video_id": "a", "title": "Artist - Song", "duration_sec": 200}
    reaction = {"video_id": "b", "title": "Artist - Song REACTION", "duration_sec": 200}
    cover = {"video_id": "c", "title": "Artist - Song (cover)", "duration_sec": 200}
    sim = 0.9
    base = score_candidate(clean, PARSED, sim)
    assert base > score_candidate(reaction, PARSED, sim)
    assert base > score_candidate(cover, PARSED, sim)


def test_missing_field_candidate_still_sane():
    # Exa-style: only title + sim, no duration/channel/source_hint.
    sparse_high = {"video_id": "a", "title": "Artist - Song"}
    sparse_low = {"video_id": "b", "title": "Artist - Song"}
    assert score_candidate(sparse_high, PARSED, 0.95) > score_candidate(sparse_low, PARSED, 0.10)
    # A purely-semantic match should still outrank a junk-titled high-sim one.
    junk = {"video_id": "c", "title": "Artist - Song reaction cover live"}
    assert score_candidate(sparse_high, PARSED, 0.95) > score_candidate(junk, PARSED, 0.95)


# --- artist/title intent matching (RC-1): the named artist's recording must beat
# covers/tributes/karaoke that match the query text but not the artist. ---

INTENT = {"artist": "Daft Punk", "title": "Get Lucky", "is_obscure": False}


def test_named_artist_beats_higher_sim_cover():
    # Cover stuffs the query into its title -> higher embedding sim, but wrong artist.
    cover = {"video_id": "a", "title": "Daft Punk - Get Lucky", "artist": "Various Artists",
             "channel": "Various Artists", "source_hint": "topic", "duration_sec": 242}
    real = {"video_id": "b", "title": "Get Lucky (feat. Pharrell Williams)",
            "artist": "Daft Punk, Pharrell Williams, Nile Rodgers",
            "channel": "Daft Punk, Pharrell Williams, Nile Rodgers",
            "source_hint": "topic", "duration_sec": 248}
    assert score_candidate(real, INTENT, 0.81) > score_candidate(cover, INTENT, 0.92)


def test_tribute_and_karaoke_penalized_for_named_artist():
    real = {"video_id": "a", "title": "Get Lucky", "artist": "Daft Punk",
            "channel": "Daft Punk", "source_hint": "topic", "duration_sec": 248}
    tribute = {"video_id": "b", "title": "Get Lucky (A Tribute to Daft Punk)",
               "artist": "Live Airplay", "channel": "Live Airplay",
               "source_hint": "topic", "duration_sec": 249}
    karaoke = {"video_id": "c", "title": "Get Lucky (Made Popular By Daft Punk)",
               "artist": "Party Tyme Karaoke", "channel": "Party Tyme Karaoke",
               "source_hint": "topic", "duration_sec": 245}
    assert score_candidate(real, INTENT, 0.81) > score_candidate(tribute, INTENT, 0.87)
    assert score_candidate(real, INTENT, 0.81) > score_candidate(karaoke, INTENT, 0.83)


def test_artist_match_via_channel_when_artist_field_missing():
    # yt-dlp results carry artist=None but a channel; the channel should still match.
    real = {"video_id": "a", "title": "Hotline Bling", "artist": None, "channel": "Drake",
            "source_hint": "other", "duration_sec": 240, "view_count": 2_000_000_000}
    cover = {"video_id": "b", "title": "Hotline Bling", "artist": "Rockabye Baby!",
             "channel": "Rockabye Baby!", "source_hint": "topic", "duration_sec": 176}
    drake = {"artist": "Drake", "title": "Hotline Bling", "is_obscure": False}
    assert score_candidate(real, drake, 0.78) > score_candidate(cover, drake, 0.84)


def test_vague_query_no_artist_no_cover_penalty():
    # No named artist -> don't apply artist boost or cover penalty (user may want a cover).
    vague = {"artist": None, "title": None, "is_obscure": False}
    a = {"video_id": "a", "title": "Hotline Bling", "artist": "Rockabye Baby!",
         "channel": "Rockabye Baby!", "source_hint": "topic", "duration_sec": 176}
    # Score should equal the same candidate scored with the cover-marker logic disabled,
    # i.e. no penalty applied: a tribute candidate isn't dragged below a plain one.
    plain = {"video_id": "b", "title": "Hotline Bling", "artist": "SomeArtist",
             "channel": "SomeArtist", "source_hint": "topic", "duration_sec": 176}
    assert abs(score_candidate(a, vague, 0.8) - score_candidate(plain, vague, 0.8)) < 1e-9


# --- canonical_label (RC-5): marry the LLM's clean artist/title to the chosen
# video when the candidate is that artist's recording, so records dedup and the
# phone shows "Drake / Hotline Bling", not "Drake - Hotline Bling". ---
from app.search.ranking import canonical_label


def test_canonical_label_uses_clean_intent_for_verbose_ytmusic_entry():
    c = {"artist": "Daft Punk, Pharrell Williams, Nile Rodgers",
         "title": "Get Lucky (feat. Pharrell Williams and Nile Rodgers)",
         "channel": "Daft Punk, Pharrell Williams, Nile Rodgers"}
    parsed = {"artist": "Daft Punk", "title": "Get Lucky"}
    assert canonical_label(c, parsed, "daft punk get lucky") == ("Daft Punk", "Get Lucky")


def test_canonical_label_cleans_ytdlp_artist_dash_title():
    c = {"artist": None, "title": "Drake - Hotline Bling", "channel": "Drake"}
    parsed = {"artist": "Drake", "title": "Hotline Bling"}
    assert canonical_label(c, parsed, "drake hotline bling") == ("Drake", "Hotline Bling")


def test_canonical_label_keeps_candidate_when_artist_mismatch():
    # Candidate is a different artist than the named one -> keep candidate's own label.
    c = {"artist": "Rockabye Baby!", "title": "Hotline Bling", "channel": "Rockabye Baby!"}
    parsed = {"artist": "Drake", "title": "Hotline Bling"}
    assert canonical_label(c, parsed, "drake hotline bling") == ("Rockabye Baby!", "Hotline Bling")


def test_canonical_label_falls_back_to_query_when_empty():
    c = {"artist": None, "title": None, "channel": None}
    parsed = {"artist": None, "title": None}
    assert canonical_label(c, parsed, "some raw query") == ("", "some raw query")


# --- the product is "Spotify for UNRELEASED music": when the user names a specific
# song, title match must dominate. A different (released) track by the same artist
# on an official channel must NOT outrank the named song just because it's official —
# even when the named song is a leak on a fan channel. ---

def test_named_leak_beats_wrong_song_by_same_artist():
    intent = {"artist": "Playboi Carti", "title": "Cancun", "is_obscure": False}
    # Wrong song, but right artist + official "topic" channel (today's winner — a bug).
    wrong = {"video_id": "a", "title": "Sky", "artist": "Playboi Carti",
             "channel": "Playboi Carti", "source_hint": "topic", "duration_sec": 194}
    # The actual leak: right title, fan-channel upload (no artist/official signal).
    leak = {"video_id": "b", "title": "Playboi Carti - Cancun (SEGA Edition)", "artist": None,
            "channel": "KADO.", "source_hint": "other", "duration_sec": 117, "view_count": 2_800_000}
    assert score_candidate(leak, intent, 0.82) > score_candidate(wrong, intent, 0.66)


def test_named_song_title_match_dominates_official_wrong_title():
    intent = {"artist": "Travis Scott", "title": "A Man", "is_obscure": False}
    wrong = {"video_id": "a", "title": "goosebumps", "artist": "Travis Scott",
             "channel": "Travis Scott", "source_hint": "topic", "duration_sec": 240}
    leak = {"video_id": "b", "title": "Travis Scott - A Man (OG)", "artist": None,
            "channel": "Unreleased 2", "source_hint": "other", "duration_sec": 185, "view_count": 1742}
    assert score_candidate(leak, intent, 0.80) > score_candidate(wrong, intent, 0.68)


def test_canonical_label_cleans_leak_on_fan_channel():
    # A leak of the named song on a fan channel (title matches, no cover markers):
    # show the artist the user asked for, not the uploader handle.
    c = {"artist": None, "title": "Playboi Carti - Cancun (SEGA Edition)", "channel": "KADO."}
    parsed = {"artist": "Playboi Carti", "title": "Cancun"}
    assert canonical_label(c, parsed, "cancun playboi carti") == ("Playboi Carti", "Cancun")


def test_canonical_label_still_keeps_cover_artist():
    # A genuine cover (cover marker present) must NOT be relabeled as the real artist,
    # so it can't dedup onto the real track.
    c = {"artist": "Rockabye Baby!", "title": "Hotline Bling", "channel": "Rockabye Baby!"}
    parsed = {"artist": "Drake", "title": "Hotline Bling"}
    assert canonical_label(c, parsed, "drake hotline bling") == ("Rockabye Baby!", "Hotline Bling")
