import Foundation

/// Schema for the local usage database. Two roles live here: a parse cache that
/// mirrors what is currently on disk (`file_cursor`, `file_entry`), and a
/// permanent archive of sealed days (`daily_archive`).
enum UsageSchema {

    static let version = 1

    static let v1 = """
    CREATE TABLE file_cursor (
      path  TEXT PRIMARY KEY,
      size  INTEGER NOT NULL,
      mtime REAL    NOT NULL,
      alive INTEGER NOT NULL DEFAULT 1
    );

    CREATE TABLE file_entry (
      path            TEXT    NOT NULL REFERENCES file_cursor(path) ON DELETE CASCADE,
      request_id      TEXT,
      day             INTEGER NOT NULL,
      ts              REAL    NOT NULL,
      model           TEXT    NOT NULL,
      input_tokens    INTEGER NOT NULL,
      output_tokens   INTEGER NOT NULL,
      cache_write_5m  INTEGER NOT NULL,
      cache_write_1h  INTEGER NOT NULL,
      cache_read      INTEGER NOT NULL,
      cost_usd        REAL
    );

    CREATE INDEX idx_entry_path ON file_entry(path);
    CREATE INDEX idx_entry_day  ON file_entry(day);

    CREATE TABLE daily_archive (
      day                INTEGER PRIMARY KEY,
      cost               REAL    NOT NULL,
      cost_mode          TEXT    NOT NULL,
      input_tokens       INTEGER NOT NULL,
      output_tokens      INTEGER NOT NULL,
      cache_write_tokens INTEGER NOT NULL,
      cache_read_tokens  INTEGER NOT NULL,
      request_count      INTEGER NOT NULL,
      models             TEXT    NOT NULL,
      sealed_at          REAL    NOT NULL
    );
    """
}
