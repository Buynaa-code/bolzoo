import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const basePath = fileURLToPath(new URL('./base.sql', import.meta.url));
const migrationPath = fileURLToPath(new URL('../migrations/0001_memories.sql', import.meta.url));

// SQLite executes the real migration and triggers in an isolated in-memory
// database. No running Worker, production binding, or stored credential is used.
const program = String.raw`
from pathlib import Path
import sqlite3, sys, time, uuid

base = Path(sys.argv[1]).read_text()
migration = Path(sys.argv[2]).read_text()
scenario = sys.argv[3]
checks = 0

def fixture():
    db = sqlite3.connect(':memory:')
    db.executescript(base + '\n' + migration)
    for actor in ('alice', 'bob', 'outsider'):
        db.execute('INSERT INTO "user"(id,email,emailVerified) VALUES(?,?,1)',
                   (actor, actor + '@test.invalid'))
        db.execute('INSERT INTO hamtdaa_profiles(user_id) VALUES(?)', (actor,))
    db.execute("INSERT INTO hamtdaa_pairs(id,state) VALUES('pair','active')")
    db.execute("INSERT INTO hamtdaa_pair_members(pair_id,user_id,slot) VALUES('pair','alice',1),('pair','bob',2)")
    return db

def insert(db, actor='alice', **updates):
    stamp = int(time.time() * 1000)
    mid = str(uuid.uuid4())
    values = dict(
        id=mid, pair_id='pair', creator_id=actor, day='2026-10-08',
        title='A memory', note='', sticker='rounded', state='pending',
        photo_key=mid + '/photo.jpg', thumbnail_key=mid + '/thumb.jpg',
        photo_bytes=1000, thumb_bytes=200, payload_hash='a' * 64,
        command_id=str(uuid.uuid4()), created_at=stamp,
        upload_deadline=stamp + 120000,
    )
    values.update(updates)
    db.execute('INSERT INTO hamtdaa_memories(' + ','.join(values) + ') VALUES('
               + ','.join('?' for _ in values) + ')', tuple(values.values()))
    return values

def reject(action):
    global checks
    try:
        action()
    except sqlite3.IntegrityError:
        checks += 1
    else:
        raise AssertionError('Expected a database constraint rejection')

def verify(condition):
    global checks
    assert condition
    checks += 1

if scenario == 'publication':
    db = fixture()
    first = insert(db)
    db.execute("UPDATE hamtdaa_memories SET state='ready' WHERE id=?", (first['id'],))
    verify(db.execute('SELECT state FROM hamtdaa_memories').fetchone()[0] == 'ready')
    reject(lambda: db.execute("UPDATE hamtdaa_memories SET state='pending'"))
    reject(lambda: db.execute("UPDATE hamtdaa_memories SET title='Changed'"))
    reject(lambda: insert(db, state='ready'))
    reject(lambda: insert(db, actor='outsider'))
    reject(lambda: insert(db, command_id=first['command_id']))
    reject(lambda: insert(db, photo_key=first['thumbnail_key']))
    reject(lambda: insert(db, thumbnail_key=first['photo_key']))
    reject(lambda: insert(db, day='2025-02-29'))
    reject(lambda: insert(db, title='x' * 81))
    reject(lambda: insert(db, photo_bytes=0))
    reject(lambda: db.execute("INSERT INTO hamtdaa_memory_quotas VALUES('alice','2026-10-08',11)"))
    verify(insert(db, day='2024-02-29')['day'] == '2024-02-29')

elif scenario == 'access':
    for statement in [
        "UPDATE hamtdaa_profiles SET account_state='disabled' WHERE user_id='bob'",
        "UPDATE user SET emailVerified=0 WHERE id='bob'",
        "UPDATE hamtdaa_pair_members SET revoked_at=1 WHERE user_id='bob'",
        "INSERT INTO hamtdaa_blocks VALUES('alice','bob')",
        "INSERT INTO hamtdaa_blocks VALUES('bob','alice')",
        "INSERT INTO hamtdaa_deleted_accounts VALUES('bob',1)",
    ]:
        db = fixture()
        pending = insert(db)
        db.execute(statement)
        reject(lambda: insert(db))
        reject(lambda: db.execute("UPDATE hamtdaa_memories SET state='ready' WHERE id=?",
                                  (pending['id'],)))

elif scenario == 'deletion':
    db = fixture()
    first = insert(db)
    other = insert(db, actor='bob')
    # Both pending and published memories must be purged by an unlink.
    db.execute("UPDATE hamtdaa_memories SET state='ready' WHERE id=?", (other['id'],))
    for actor, memory in [('alice', first), ('bob', other)]:
        db.execute('INSERT INTO hamtdaa_memory_receipts VALUES(?,?,?,?,?,?,?)',
                   (actor, str(uuid.uuid4()), 'pair', 'create', 'a' * 64,
                    memory['id'], int(time.time() * 1000)))
        db.execute('INSERT INTO hamtdaa_memory_quotas VALUES(?,?,1)',
                   (actor, '2026-10-08'))
    db.execute("INSERT INTO hamtdaa_deleted_accounts VALUES('alice',?)",
               (int(time.time() * 1000),))
    verify(db.execute('SELECT creator_id FROM hamtdaa_memories').fetchall() == [('bob',)])
    verify(db.execute('SELECT user_id FROM hamtdaa_memory_receipts').fetchall() == [('bob',)])
    verify(db.execute('SELECT user_id FROM hamtdaa_memory_quotas').fetchall() == [('bob',)])
    verify(db.execute('SELECT count(*) FROM hamtdaa_memory_gc').fetchone()[0] == 2)
    db.execute("UPDATE hamtdaa_pairs SET state='unlinked',unlinked_at=1 WHERE id='pair'")
    verify(db.execute('SELECT count(*) FROM hamtdaa_memories').fetchone()[0] == 0)
    verify(db.execute('SELECT count(*) FROM hamtdaa_memory_gc').fetchone()[0] == 4)
    verify(db.execute('SELECT count(*) FROM hamtdaa_memory_receipts').fetchone()[0] == 1)
    now = int(time.time() * 1000)
    for due, retain, attempts in db.execute('SELECT due_at,retain_until,attempts FROM hamtdaa_memory_gc'):
        verify(abs(due - now - 300000) < 2000
               and abs(retain - now - 86400000) < 2000 and attempts == 0)
    verify(db.execute('PRAGMA foreign_key_check').fetchall() == [])

elif scenario == 'gc':
    db = fixture()
    first = insert(db)
    db.execute('DELETE FROM hamtdaa_memories')
    reject(lambda: insert(db, photo_key=first['photo_key']))
    verify(db.execute('SELECT count(*) FROM hamtdaa_memory_gc').fetchone()[0] == 2)
    db.execute("INSERT INTO hamtdaa_memory_gc_state VALUES('cursor','next-page')")
    verify(db.execute("SELECT value FROM hamtdaa_memory_gc_state WHERE name='cursor'").fetchone()[0] == 'next-page')
else:
    raise AssertionError('Unknown test scenario')

print(checks)
`;

function runScenario(scenario: string, expectedChecks: number) {
  const result = spawnSync('python3', ['-c', program, basePath, migrationPath, scenario], {
    encoding: 'utf8',
    timeout: 10_000,
    maxBuffer: 1024 * 1024,
  });
  assert.ifError(result.error);
  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.equal(Number(result.stdout.trim()), expectedChecks);
}

test('schema permits publication and rejects invalid ownership, mutation, keys and inputs', () => {
  runScenario('publication', 13);
});

test('schema rejects reservations and publication after either member loses pair access', () => {
  runScenario('access', 12);
});

test('account and pair deletion erase content and queue both private objects atomically', () => {
  runScenario('deletion', 12);
});

test('GC tombstones prevent key reuse and preserve the orphan sweep cursor', () => {
  runScenario('gc', 3);
});
