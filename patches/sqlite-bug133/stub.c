#pragma comment(lib, "sqlite3.lib")
#include <sqlite3.h>
#include <moonbit.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

// ============================================================================
// BUG-133 修复（2026-10-10，自研 FFI 内存安全）：
// 原版 stub.c 把 C 侧裸指针（sqlite3* / sqlite3_stmt*）直接当 MoonBit 对象回传，
// MoonBit native 运行时按对象头去标记/释放一个非堆起点指针 → SIGSEGV/SIGABRT
//（`munmap_chunk(): invalid pointer` / `free(): invalid pointer`）。另有 6 个函数
// C 回 `const char*` 而 MoonBit 声明成 `-> Bytes`（Bytes 要读长度前缀）→ UB。
//
// 修法（与 runtime.c 的 moonbit_make_external_object 契约对齐）：
//   · 指针返回 → moonbit_make_external_object(finalize, payload_size) 包成
//     MoonBit 可管理的外部对象（GC 知道它是外部对象，走 finalize 释放，不再
//     按对象头遍历）；
//   · 指针入参 → FFI 拿到的就是 external object 的 payload 起点（runtime 直接把
//     payload 指针传给 C，与 moonbit_monotonic_clock_stop 同型），直接 cast。
//   · `const char*` 返回 → moonbit_make_bytes(len) + memcpy 复制（同 sqlite_column_name）。
// ============================================================================

// Helper to convert MoonBit Bytes to C string
// @encoding.encode_utf8() returns UTF-8 encoded bytes, so we copy directly and add NULL terminator
static char* bytes_to_cstring(moonbit_bytes_t bytes) {
    int32_t len = Moonbit_array_length(bytes);
    char* str = (char*)malloc(len + 1);
    memcpy(str, bytes, len);
    str[len] = '\0';
    return str;
}

// --- external object helpers (BUG-133) ---

// Wrap sqlite3* in a MoonBit-managed external object. `finalize` closes db.
typedef struct { sqlite3* db; } SqliteDbPayload;

static void sqlite_db_finalize(void* self) {
    SqliteDbPayload* p = (SqliteDbPayload*)self;
    if (p && p->db) { sqlite3_close(p->db); p->db = NULL; }
}

// Wrap sqlite3_stmt* in a MoonBit-managed external object. `finalize` releases stmt.
typedef struct { sqlite3_stmt* stmt; } SqliteStmtPayload;

static void sqlite_stmt_finalize(void* self) {
    SqliteStmtPayload* p = (SqliteStmtPayload*)self;
    if (p && p->stmt) { sqlite3_finalize(p->stmt); p->stmt = NULL; }
}

// Convert C string to MoonBit-owned Bytes (copies). NULL/empty → empty bytes.
static moonbit_bytes_t cstring_to_moonbit_bytes(const char* s) {
    if (!s) return moonbit_make_bytes(0, 0);
    size_t len = strlen(s);
    if (len == 0) return moonbit_make_bytes(0, 0);
    moonbit_bytes_t result = moonbit_make_bytes((int32_t)len, 0);
    memcpy(result, s, len);
    return result;
}

// Open database (returns MoonBit external object on success, NULL on failure)
void* sqlite_open(moonbit_bytes_t filename) {
    char* fname = bytes_to_cstring(filename);
    sqlite3* db;
    int rc = sqlite3_open(fname, &db);
    free(fname);
    if (rc != SQLITE_OK) {
        if (db) sqlite3_close(db);
        return NULL;
    }
    SqliteDbPayload* payload = (SqliteDbPayload*)moonbit_make_external_object(
        sqlite_db_finalize, sizeof(SqliteDbPayload));
    payload->db = db;
    return payload;
}

// Open database with extended options
void* sqlite_open_v2(moonbit_bytes_t filename, int32_t flags, moonbit_bytes_t vfs) {
    char* fname = bytes_to_cstring(filename);
    char* vfs_str = NULL;
    if (Moonbit_array_length(vfs) > 0) {
        vfs_str = bytes_to_cstring(vfs);
    }

    sqlite3* db;
    int rc = sqlite3_open_v2(fname, &db, flags, vfs_str);

    free(fname);
    if (vfs_str) free(vfs_str);

    if (rc != SQLITE_OK) {
        if (db) sqlite3_close(db);
        return NULL;
    }
    SqliteDbPayload* payload = (SqliteDbPayload*)moonbit_make_external_object(
        sqlite_db_finalize, sizeof(SqliteDbPayload));
    payload->db = db;
    return payload;
}

// Check if pointer is NULL
int32_t sqlite_is_null(void* ptr) {
    if (!ptr) return 1;
    SqliteDbPayload* p = (SqliteDbPayload*)ptr;
    return p->db == NULL ? 1 : 0;
}

int32_t sqlite_stmt_is_null(void* ptr) {
    if (!ptr) return 1;
    SqliteStmtPayload* p = (SqliteStmtPayload*)ptr;
    return p->stmt == NULL ? 1 : 0;
}

// Close database (idempotent; safe to call multiple times)
void sqlite_close(void* db_obj) {
    if (!db_obj) return;
    SqliteDbPayload* p = (SqliteDbPayload*)db_obj;
    if (p->db) { sqlite3_close(p->db); p->db = NULL; }
}

// Execute SQL (no result). Returns 0 on success
int32_t sqlite_exec(void* db_obj, moonbit_bytes_t sql) {
    if (!db_obj) return SQLITE_MISUSE;
    SqliteDbPayload* p = (SqliteDbPayload*)db_obj;
    char* sql_str = bytes_to_cstring(sql);
    char* err_msg = NULL;
    int rc = sqlite3_exec(p->db, sql_str, NULL, NULL, &err_msg);
    free(sql_str);
    if (err_msg) {
        sqlite3_free(err_msg);
    }
    return rc;
}

// Create prepared statement (returns MoonBit external object on success, NULL on failure)
void* sqlite_prepare(void* db_obj, moonbit_bytes_t sql) {
    if (!db_obj) return NULL;
    SqliteDbPayload* p = (SqliteDbPayload*)db_obj;
    char* sql_str = bytes_to_cstring(sql);
    sqlite3_stmt* stmt = NULL;
    int rc = sqlite3_prepare_v2(p->db, sql_str, -1, &stmt, NULL);
    free(sql_str);
    if (rc != SQLITE_OK) {
        if (stmt) sqlite3_finalize(stmt);
        return NULL;
    }
    SqliteStmtPayload* payload = (SqliteStmtPayload*)moonbit_make_external_object(
        sqlite_stmt_finalize, sizeof(SqliteStmtPayload));
    payload->stmt = stmt;
    return payload;
}

// Finalize statement (idempotent)
void sqlite_finalize(void* stmt_obj) {
    if (!stmt_obj) return;
    SqliteStmtPayload* p = (SqliteStmtPayload*)stmt_obj;
    if (p->stmt) { sqlite3_finalize(p->stmt); p->stmt = NULL; }
}

// Bind parameter (1-indexed)
int32_t sqlite_bind_int(void* stmt_obj, int32_t idx, int32_t value) {
    if (!stmt_obj) return SQLITE_MISUSE;
    SqliteStmtPayload* p = (SqliteStmtPayload*)stmt_obj;
    return sqlite3_bind_int(p->stmt, idx, value);
}

int32_t sqlite_bind_double(void* stmt_obj, int32_t idx, double value) {
    if (!stmt_obj) return SQLITE_MISUSE;
    SqliteStmtPayload* p = (SqliteStmtPayload*)stmt_obj;
    return sqlite3_bind_double(p->stmt, idx, value);
}

int32_t sqlite_bind_text(void* stmt_obj, int32_t idx, moonbit_bytes_t text) {
    if (!stmt_obj) return SQLITE_MISUSE;
    SqliteStmtPayload* p = (SqliteStmtPayload*)stmt_obj;
    char* text_str = bytes_to_cstring(text);
    int rc = sqlite3_bind_text(p->stmt, idx, text_str, -1, SQLITE_TRANSIENT);
    free(text_str);
    return rc;
}

// Step to next row. 100=SQLITE_ROW (has data), 101=SQLITE_DONE (finished)
int32_t sqlite_step(void* stmt_obj) {
    if (!stmt_obj) return SQLITE_MISUSE;
    SqliteStmtPayload* p = (SqliteStmtPayload*)stmt_obj;
    return sqlite3_step(p->stmt);
}

// Get column value (0-indexed)
int32_t sqlite_column_int(void* stmt_obj, int32_t col) {
    if (!stmt_obj) return 0;
    SqliteStmtPayload* p = (SqliteStmtPayload*)stmt_obj;
    return sqlite3_column_int(p->stmt, col);
}

double sqlite_column_double(void* stmt_obj, int32_t col) {
    if (!stmt_obj) return 0.0;
    SqliteStmtPayload* p = (SqliteStmtPayload*)stmt_obj;
    return sqlite3_column_double(p->stmt, col);
}

// Return SQLite text column as MoonBit Bytes
// moonbit_bytes_t is a length-prefixed byte array
moonbit_bytes_t sqlite_column_text(void* stmt_obj, int32_t col) {
    if (!stmt_obj) return moonbit_make_bytes(0, 0);
    SqliteStmtPayload* p = (SqliteStmtPayload*)stmt_obj;
    const unsigned char* text = sqlite3_column_text(p->stmt, col);
    int len = sqlite3_column_bytes(p->stmt, col);
    if (text == NULL || len == 0) {
        return moonbit_make_bytes(0, 0);
    }
    moonbit_bytes_t result = moonbit_make_bytes(len, 0);
    memcpy(result, text, len);
    return result;
}

// Reset statement (make it reusable)
void sqlite_reset(void* stmt_obj) {
    if (!stmt_obj) return;
    SqliteStmtPayload* p = (SqliteStmtPayload*)stmt_obj;
    sqlite3_reset(p->stmt);
}

// Error handling
int32_t sqlite_errcode(void* db_obj) {
    if (!db_obj) return SQLITE_MISUSE;
    SqliteDbPayload* p = (SqliteDbPayload*)db_obj;
    return sqlite3_errcode(p->db);
}

// Return error message as MoonBit Bytes (const char* → Bytes is UB; copy properly)
moonbit_bytes_t sqlite_errmsg(void* db_obj) {
    if (!db_obj) return moonbit_make_bytes(0, 0);
    SqliteDbPayload* p = (SqliteDbPayload*)db_obj;
    return cstring_to_moonbit_bytes(sqlite3_errmsg(p->db));
}

// Additional bind functions
int32_t sqlite_bind_null(void* stmt_obj, int32_t idx) {
    if (!stmt_obj) return SQLITE_MISUSE;
    SqliteStmtPayload* p = (SqliteStmtPayload*)stmt_obj;
    return sqlite3_bind_null(p->stmt, idx);
}

// Note: Using int64_t for idx to avoid ABI issues with mixed 32/64-bit parameters
// on some platforms (Linux x86-64). MoonBit may pass parameters differently
// when mixing Int and Int64 types.
int32_t sqlite_bind_int64(void* stmt_obj, int64_t idx, int64_t value) {
    if (!stmt_obj) return SQLITE_MISUSE;
    SqliteStmtPayload* p = (SqliteStmtPayload*)stmt_obj;
    return sqlite3_bind_int64(p->stmt, (int)idx, value);
}

int32_t sqlite_bind_blob(void* stmt_obj, int32_t idx, moonbit_bytes_t blob) {
    if (!stmt_obj) return SQLITE_MISUSE;
    SqliteStmtPayload* p = (SqliteStmtPayload*)stmt_obj;
    int32_t len = Moonbit_array_length(blob);
    return sqlite3_bind_blob(p->stmt, idx, blob, len, SQLITE_TRANSIENT);
}

// Additional column getter functions
int64_t sqlite_column_int64(void* stmt_obj, int32_t col) {
    if (!stmt_obj) return 0;
    SqliteStmtPayload* p = (SqliteStmtPayload*)stmt_obj;
    return sqlite3_column_int64(p->stmt, col);
}

// Return SQLite BLOB column as MoonBit Bytes
moonbit_bytes_t sqlite_column_blob(void* stmt_obj, int32_t col) {
    if (!stmt_obj) return moonbit_make_bytes(0, 0);
    SqliteStmtPayload* p = (SqliteStmtPayload*)stmt_obj;
    const void* blob = sqlite3_column_blob(p->stmt, col);
    int len = sqlite3_column_bytes(p->stmt, col);
    if (blob == NULL || len == 0) {
        return moonbit_make_bytes(0, 0);
    }
    moonbit_bytes_t result = moonbit_make_bytes(len, 0);
    memcpy(result, blob, len);
    return result;
}

int32_t sqlite_column_bytes(void* stmt_obj, int32_t col) {
    if (!stmt_obj) return 0;
    SqliteStmtPayload* p = (SqliteStmtPayload*)stmt_obj;
    return sqlite3_column_bytes(p->stmt, col);
}

int32_t sqlite_column_type(void* stmt_obj, int32_t col) {
    if (!stmt_obj) return 0;
    SqliteStmtPayload* p = (SqliteStmtPayload*)stmt_obj;
    return sqlite3_column_type(p->stmt, col);
}

// Metadata functions
int32_t sqlite_column_count(void* stmt_obj) {
    if (!stmt_obj) return 0;
    SqliteStmtPayload* p = (SqliteStmtPayload*)stmt_obj;
    return sqlite3_column_count(p->stmt);
}

// Return a MoonBit-owned copy of the column name. Plain `const char*`
// passed back as moonbit_bytes_t is UB — Bytes reads a length prefix
// before the pointer, so the caller hits random memory. Copy into a
// proper moonbit_make_bytes(len) buffer instead (same pattern as
// sqlite_column_text above).
moonbit_bytes_t sqlite_column_name(void* stmt_obj, int32_t col) {
    if (!stmt_obj) return moonbit_make_bytes(0, 0);
    SqliteStmtPayload* p = (SqliteStmtPayload*)stmt_obj;
    const char* name = sqlite3_column_name(p->stmt, col);
    if (!name) {
        return moonbit_make_bytes(0, 0);
    }
    int32_t len = (int32_t)strlen(name);
    moonbit_bytes_t result = moonbit_make_bytes(len, 0);
    memcpy(result, name, (size_t)len);
    return result;
}

int32_t sqlite_changes(void* db_obj) {
    if (!db_obj) return 0;
    SqliteDbPayload* p = (SqliteDbPayload*)db_obj;
    return sqlite3_changes(p->db);
}

int64_t sqlite_last_insert_rowid(void* db_obj) {
    if (!db_obj) return 0;
    SqliteDbPayload* p = (SqliteDbPayload*)db_obj;
    return sqlite3_last_insert_rowid(p->db);
}

// Clear statement bindings
int32_t sqlite_clear_bindings(void* stmt_obj) {
    if (!stmt_obj) return SQLITE_MISUSE;
    SqliteStmtPayload* p = (SqliteStmtPayload*)stmt_obj;
    return sqlite3_clear_bindings(p->stmt);
}

// Concurrency control
int32_t sqlite_busy_timeout(void* db_obj, int32_t ms) {
    if (!db_obj) return SQLITE_MISUSE;
    SqliteDbPayload* p = (SqliteDbPayload*)db_obj;
    return sqlite3_busy_timeout(p->db, ms);
}

// Transaction management
int32_t sqlite_get_autocommit(void* db_obj) {
    if (!db_obj) return 0;
    SqliteDbPayload* p = (SqliteDbPayload*)db_obj;
    return sqlite3_get_autocommit(p->db);
}

int32_t sqlite_total_changes(void* db_obj) {
    if (!db_obj) return 0;
    SqliteDbPayload* p = (SqliteDbPayload*)db_obj;
    return sqlite3_total_changes(p->db);
}

// Statement introspection: return SQL text as MoonBit Bytes
moonbit_bytes_t sqlite_sql(void* stmt_obj) {
    if (!stmt_obj) return moonbit_make_bytes(0, 0);
    SqliteStmtPayload* p = (SqliteStmtPayload*)stmt_obj;
    const char* sql = sqlite3_sql(p->stmt);
    return cstring_to_moonbit_bytes(sql);
}

int32_t sqlite_bind_parameter_count(void* stmt_obj) {
    if (!stmt_obj) return 0;
    SqliteStmtPayload* p = (SqliteStmtPayload*)stmt_obj;
    return sqlite3_bind_parameter_count(p->stmt);
}

int32_t sqlite_stmt_readonly(void* stmt_obj) {
    if (!stmt_obj) return 0;
    SqliteStmtPayload* p = (SqliteStmtPayload*)stmt_obj;
    return sqlite3_stmt_readonly(p->stmt);
}

// Extended error handling
int32_t sqlite_extended_errcode(void* db_obj) {
    if (!db_obj) return 0;
    SqliteDbPayload* p = (SqliteDbPayload*)db_obj;
    return sqlite3_extended_errcode(p->db);
}

// Return errstr as MoonBit Bytes (const char* → Bytes is UB; copy properly)
moonbit_bytes_t sqlite_errstr(int32_t errcode) {
    const char* msg = sqlite3_errstr(errcode);
    return cstring_to_moonbit_bytes(msg);
}

// Get parameter name as MoonBit Bytes (const char* → Bytes is UB; copy properly)
moonbit_bytes_t sqlite_bind_parameter_name(void* stmt_obj, int32_t idx) {
    if (!stmt_obj) return moonbit_make_bytes(0, 0);
    SqliteStmtPayload* p = (SqliteStmtPayload*)stmt_obj;
    const char* name = sqlite3_bind_parameter_name(p->stmt, idx);
    return cstring_to_moonbit_bytes(name);
}

int32_t sqlite_bind_parameter_index(void* stmt_obj, moonbit_bytes_t name) {
    if (!stmt_obj) return 0;
    SqliteStmtPayload* p = (SqliteStmtPayload*)stmt_obj;
    char* name_str = bytes_to_cstring(name);
    int rc = sqlite3_bind_parameter_index(p->stmt, name_str);
    free(name_str);
    return rc;
}

// Get database filename as MoonBit Bytes (const char* → Bytes is UB; copy properly)
moonbit_bytes_t sqlite_db_filename(void* db_obj, moonbit_bytes_t dbname) {
    if (!db_obj) return moonbit_make_bytes(0, 0);
    SqliteDbPayload* p = (SqliteDbPayload*)db_obj;
    char* dbname_str = bytes_to_cstring(dbname);
    const char* filename = sqlite3_db_filename(p->db, dbname_str);
    free(dbname_str);
    return cstring_to_moonbit_bytes(filename);
}

int32_t sqlite_db_readonly(void* db_obj, moonbit_bytes_t dbname) {
    if (!db_obj) return 0;
    SqliteDbPayload* p = (SqliteDbPayload*)db_obj;
    char* dbname_str = bytes_to_cstring(dbname);
    int readonly = sqlite3_db_readonly(p->db, dbname_str);
    free(dbname_str);
    return readonly;
}

// Get expanded SQL as MoonBit Bytes (const char* → Bytes is UB; copy properly)
moonbit_bytes_t sqlite_expanded_sql(void* stmt_obj) {
    if (!stmt_obj) return moonbit_make_bytes(0, 0);
    SqliteStmtPayload* p = (SqliteStmtPayload*)stmt_obj;
    char* sql = sqlite3_expanded_sql(p->stmt);
    if (!sql) return moonbit_make_bytes(0, 0);
    moonbit_bytes_t result = cstring_to_moonbit_bytes(sql);
    sqlite3_free(sql);  // free dynamically allocated string
    return result;
}

// Interrupt running query
void sqlite_interrupt(void* db_obj) {
    if (!db_obj) return;
    SqliteDbPayload* p = (SqliteDbPayload*)db_obj;
    sqlite3_interrupt(p->db);
}

// Set/get resource limits
int32_t sqlite_limit(void* db_obj, int32_t id, int32_t newVal) {
    if (!db_obj) return 0;
    SqliteDbPayload* p = (SqliteDbPayload*)db_obj;
    return sqlite3_limit(p->db, id, newVal);
}