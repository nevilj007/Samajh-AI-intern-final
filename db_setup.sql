CREATE TABLE conversations (
    id SERIAL PRIMARY KEY,
    call_id TEXT UNIQUE NOT NULL,
    transcripts TEXT NOT NULL,
    summary TEXT,
    audio_url TEXT,
    phone_number TEXT
);

CREATE TABLE call_responses (
    id SERIAL PRIMARY KEY,
    call_id TEXT REFERENCES conversations(call_id),
    question TEXT NOT NULL,
    response TEXT NOT NULL
);

