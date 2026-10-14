#!/usr/bin/env python3
"""Offline recovery gate: rebuild D1 schema and compare with observed deployment.

Requires only Python's standard library. It never connects to a remote database.
The fixture contains DDL only, not accounts, sessions, receipts or other data.
"""

import json
from pathlib import Path
import re
import sqlite3
import unittest


ROOT = Path(__file__).resolve().parents[2]
FIXTURE = json.loads(
    (Path(__file__).parent / "deployed-schema-2026-10-12.json").read_text()
)
AUTH_DIR = ROOT / "migrations"
MEMORY_DIR = ROOT.parent / "memories_worker" / "migrations"

# D1/Wrangler owns these; applications must not recreate them in migrations.
INTERNAL_OBJECTS = {
    "_cf_KV", "d1_migrations", "hamtdaa_memory_migrations", "sqlite_sequence"
}


def normalized_sql(sql):
    # Ignore SQL formatting/case while retaining quoted literal contents and
    # every identifier/operator/constraint. Do not strip comments inside text.
    tokens = re.findall(
        r"'(?:''|[^'])*'|\"(?:\"\"|[^\"])*\"|--[^\n]*|/\*[\s\S]*?\*/|\w+|[^\s]",
        sql,
    )
    return tuple(
        token if token.startswith("'") else token.lower()
        for token in tokens
        if not token.startswith(("--", "/*"))
    )


def schema(connection):
    return {
        name: (kind, table, normalized_sql(sql))
        for kind, name, table, sql in connection.execute(
            "SELECT type,name,tbl_name,sql FROM sqlite_master WHERE sql IS NOT NULL"
        )
        if name not in INTERNAL_OBJECTS
    }


def apply(connection, directory, names=None):
    for migration in sorted(directory.glob("*.sql")):
        if names is None or migration.name in names:
            connection.executescript(migration.read_text())


class RecoveredSchemaTest(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(":memory:")
        self.db.execute("PRAGMA foreign_keys=ON")
        self.addCleanup(self.db.close)

    def test_applied_migration_names_preserved(self):
        self.assertEqual(
            [p.name for p in sorted(AUTH_DIR.glob("*.sql"))][:len(FIXTURE["auth_migrations"])],
            FIXTURE["auth_migrations"],
        )
        self.assertEqual(
            [p.name for p in sorted(MEMORY_DIR.glob("*.sql"))],
            FIXTURE["memory_migrations"],
        )

    def test_auth_migrations_rebuild_independently(self):
        apply(self.db, AUTH_DIR, FIXTURE["auth_migrations"])
        actual = schema(self.db)
        # Memories and wishes are separately managed additive migrations.
        # Auth recovery must not acquire their tables, indexes or triggers.
        feature_prefixes = ("hamtdaa_memor", "hamtdaa_wish")
        expected = {
            item["name"]: (item["type"], item["tbl_name"], normalized_sql(item["sql"]))
            for item in FIXTURE["objects"]
            if not item["name"].startswith(feature_prefixes)
        }
        self.assertEqual(actual.keys(), expected.keys())
        for name in expected:
            with self.subTest(object=name):
                self.assertEqual(actual[name], expected[name])
        self.assertEqual(self.db.execute("PRAGMA integrity_check").fetchall(), [("ok",)])
        self.assertEqual(self.db.execute("PRAGMA foreign_key_check").fetchall(), [])

    def test_combined_migrations_match_deployed_schema(self):
        apply(self.db, AUTH_DIR, FIXTURE["auth_migrations"])
        apply(self.db, MEMORY_DIR)
        actual = schema(self.db)
        expected = {
            item["name"]: (item["type"], item["tbl_name"], normalized_sql(item["sql"]))
            for item in FIXTURE["objects"]
        }
        self.assertEqual(actual.keys(), expected.keys())
        for name in expected:
            with self.subTest(object=name):
                self.assertEqual(actual[name], expected[name])
        self.assertEqual(self.db.execute("PRAGMA integrity_check").fetchall(), [("ok",)])
        self.assertEqual(self.db.execute("PRAGMA foreign_key_check").fetchall(), [])

    def test_additive_gifts_music_migration_is_compatible(self):
        apply(self.db, AUTH_DIR)
        apply(self.db, MEMORY_DIR)
        columns = {row[1] for row in self.db.execute("PRAGMA table_info(hamtdaa_calendar_events)")}
        self.assertIn("music_json", columns)
        self.assertIn("hamtdaa_flower_gifts", schema(self.db))
        self.assertIn("hamtdaa_gift_receipts", schema(self.db))
        self.assertEqual(self.db.execute("PRAGMA integrity_check").fetchall(), [("ok",)])
        self.assertEqual(self.db.execute("PRAGMA foreign_key_check").fetchall(), [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
