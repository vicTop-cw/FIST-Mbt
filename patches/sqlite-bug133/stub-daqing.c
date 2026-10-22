// patches/sqlite-bug133/stub-daqing.c — daqing/sqlite@0.4.0 的 native stub 替换版
// ============================================================================
// 为什么需要它（BUG-133 族在 daqing 上的复刻，2026-10-22 valgrind 定位）
// ---------------------------------------------------------------
// 上游 stub 把 `sqlite3*` / `sqlite3_stmt*` **裸指针直接当 MoonBit GC 对象**回传：
//   · `sqlite_prepare` 返回 C 指针 → MoonBit 侧把它当对象；
//   · `Statement::finalize()` 显式 `sqlite3_finalize` 释放了同一块内存；
//   · 语句作用域结束/GC 时运行时仍对它执行 `moonbit_drop_object` ⇒ **use-after-free**。
// valgrind 首条错误即：
//   Invalid read of size 4 at moonbit_drop_object (runtime.c:545)
//   Address … is 0 bytes inside a block of size 312 free'd by sqlite3_free ← sqlite3_finalize
//   Block was alloc'd at … sqlite_prepare (stub.c:96)
// 与 mizchi 时代 BUG-133 同一族（那次是 stub 缺 moonbit_make_external_object）。
//
// 修法（与仓库既有 patches/sqlite-bug133/stub.c 对 mizchi 的做法同构）
// ----------------------------------------------------------------
//   · 指针返回 → `moonbit_make_external_object(finalizer, payload_size)` 包成 MoonBit 可管理的
//     外部对象：GC 知道它走 finalizer 释放，不再按普通对象头遍历；
//   · 指针入参 → runtime 直接把 external object 的 **payload 起点**传给 C，故 C 侧收到的是
//     payload 指针，用 DB()/STMT() 取回真正的 sqlite 句柄；
//   · `close` / `finalize` 仍可用：内部置 NULL，finalizer 变 no-op（幂等，不会二次释放）。
//   · `const char*` 返回沿用上游已修好的 cstring_to_bytes（上游 CLAUDE.md 已记这条）。
// ============================================================================
#include <sqlite3.h>
#include <moonbit.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

// ---- external object payloads (BUG-133 族) --------------------------------

typedef struct { sqlite3* db; } MoonDb;
typedef struct { sqlite3_stmt* stmt; } MoonStmt;

static void moon_db_finalize(void* self) {
    MoonDb* p = (MoonDb*)self;
    if (p && p->db) { sqlite3_close(p->db); p->db = NULL; }
}

static void moon_stmt_finalize(void* self) {
    MoonStmt* p = (MoonStmt*)self;
    if (p && p->stmt) { sqlite3_finalize(p->stmt); p->stmt = NULL; }
}

#define DB(x)   (((MoonDb*)(x)) ? ((MoonDb*)(x))->db : NULL)
#define STMT(x) (((MoonStmt*)(x)) ? ((MoonStmt*)(x))->stmt : NULL)

// Helper to convert MoonBit Bytes to C string
static char* bytes_to_cstring(moonbit_bytes_t bytes) {
    int32_t len = Moonbit_array_length(bytes);
    char* str = (char*)malloc((size_t)len + 1);
    memcpy(str, bytes, (size_t)len);
    str[len] = '\0';
    return str;
}

// Copy a C string into a fresh MoonBit-owned Bytes.
static moonbit_bytes_t cstring_to_bytes(const char* s) {
    if (!s) {
        return moonbit_make_bytes(0, 0);
    }
    int32_t len = (int32_t)strlen(s);
    moonbit_bytes_t result = moonbit_make_bytes(len, 0);
    if (len > 0) {
        memcpy(result, s, (size_t)len);
    }
    return result;
}

// ---- open / close ---------------------------------------------------------

// 返回 boxed 外部对象；失败返回 NULL（MoonBit 侧用 sqlite_is_null 判）。
void* sqlite_open(moonbit_bytes_t filename) {
    char* fname = bytes_to_cstring(filename);
    sqlite3* db = NULL;
    int rc = sqlite3_open(fname, &db);
    free(fname);
    if (rc != SQLITE_OK) {
        if (db) sqlite3_close(db);
        return NULL;
    }
    MoonDb* payload = (MoonDb*)moonbit_make_external_object(moon_db_finalize, sizeof(MoonDb));
    payload->db = db;
    return payload;
}

void* sqlite_open_v2(moonbit_bytes_t filename, int32_t flags, moonbit_bytes_t vfs) {
    char* fname = bytes_to_cstring(filename);
    char* vfs_str = NULL;
    if (Moonbit_array_length(vfs) > 0) {
        vfs_str = bytes_to_cstring(vfs);
    }
    sqlite3* db = NULL;
    int rc = sqlite3_open_v2(fname, &db, flags, vfs_str);
    free(fname);
    if (vfs_str) free(vfs_str);
    if (rc != SQLITE_OK) {
        if (db) sqlite3_close(db);
        return NULL;
    }
    MoonDb* payload = (MoonDb*)moonbit_make_external_object(moon_db_finalize, sizeof(MoonDb));
    payload->db = db;
    return payload;
}

// 入参是 payload 指针；NULL 对象 ⇒ payload 为 NULL。
int32_t sqlite_is_null(void* ptr) {
    return ptr == NULL ? 1 : 0;
}

int32_t sqlite_stmt_is_null(void* ptr) {
    return ptr == NULL ? 1 : 0;
}

// 显式关闭后把 payload 置 NULL，finalizer 幂等。
void sqlite_close(void* db) {
    MoonDb* p = (MoonDb*)db;
    if (p && p->db) { sqlite3_close(p->db); p->db = NULL; }
}

// ---- exec / prepare ------------------------------------------------------

int32_t sqlite_exec(void* db, moonbit_bytes_t sql) {
    char* sql_str = bytes_to_cstring(sql);
    char* err_msg = NULL;
    int rc = sqlite3_exec(DB(db), sql_str, NULL, NULL, &err_msg);
    free(sql_str);
    if (err_msg) { sqlite3_free(err_msg); }
    return rc;
}

// 返回 boxed 语句外部对象；失败 NULL。
void* sqlite_prepare(void* db, moonbit_bytes_t sql) {
    char* sql_str = bytes_to_cstring(sql);
    sqlite3_stmt* stmt = NULL;
    int rc = sqlite3_prepare_v2(DB(db), sql_str, -1, &stmt, NULL);
    free(sql_str);
    if (rc != SQLITE_OK) {
        if (stmt) sqlite3_finalize(stmt);
        return NULL;
    }
    MoonStmt* payload = (MoonStmt*)moonbit_make_external_object(moon_stmt_finalize, sizeof(MoonStmt));
    payload->stmt = stmt;
    return payload;
}

// 显式 finalize 后置 NULL，finalizer 幂等。
void sqlite_finalize(void* stmt) {
    MoonStmt* p = (MoonStmt*)stmt;
    if (p && p->stmt) { sqlite3_finalize(p->stmt); p->stmt = NULL; }
}

// ---- bind ----------------------------------------------------------------

int32_t sqlite_bind_int(void* stmt, int32_t idx, int32_t value) {
    return sqlite3_bind_int(STMT(stmt), idx, value);
}

int32_t sqlite_bind_double(void* stmt, int32_t idx, double value) {
    return sqlite3_bind_double(STMT(stmt), idx, value);
}

int32_t sqlite_bind_text(void* stmt, int32_t idx, moonbit_bytes_t text) {
    char* text_str = bytes_to_cstring(text);
    int rc = sqlite3_bind_text(STMT(stmt), idx, text_str, -1, SQLITE_TRANSIENT);
    free(text_str);
    return rc;
}

int32_t sqlite_bind_null(void* stmt, int32_t idx) {
    return sqlite3_bind_null(STMT(stmt), idx);
}

int32_t sqlite_bind_int64(void* stmt, int64_t idx, int64_t value) {
    return sqlite3_bind_int64(STMT(stmt), (int)idx, value);
}

int32_t sqlite_bind_blob(void* stmt, int32_t idx, moonbit_bytes_t blob) {
    int32_t len = Moonbit_array_length(blob);
    return sqlite3_bind_blob(STMT(stmt), idx, blob, len, SQLITE_TRANSIENT);
}

int32_t sqlite_clear_bindings(void* stmt) {
    return sqlite3_clear_bindings(STMT(stmt));
}

// ---- step / column -------------------------------------------------------

int32_t sqlite_step(void* stmt) {
    return sqlite3_step(STMT(stmt));
}

int32_t sqlite_reset(void* stmt) {
    sqlite3_reset(STMT(stmt));
    return 0;
}

int32_t sqlite_column_int(void* stmt, int32_t col) {
    return sqlite3_column_int(STMT(stmt), col);
}

double sqlite_column_double(void* stmt, int32_t col) {
    return sqlite3_column_double(STMT(stmt), col);
}

int64_t sqlite_column_int64(void* stmt, int32_t col) {
    return sqlite3_column_int64(STMT(stmt), col);
}

moonbit_bytes_t sqlite_column_text(void* stmt, int32_t col) {
    const unsigned char* text = sqlite3_column_text(STMT(stmt), col);
    int len = sqlite3_column_bytes(STMT(stmt), col);
    if (text == NULL || len == 0) {
        return moonbit_make_bytes(0, 0);
    }
    moonbit_bytes_t result = moonbit_make_bytes(len, 0);
    memcpy(result, text, (size_t)len);
    return result;
}

moonbit_bytes_t sqlite_column_blob(void* stmt, int32_t col) {
    const void* blob = sqlite3_column_blob(STMT(stmt), col);
    int len = sqlite3_column_bytes(STMT(stmt), col);
    if (blob == NULL || len == 0) {
        return moonbit_make_bytes(0, 0);
    }
    moonbit_bytes_t result = moonbit_make_bytes(len, 0);
    memcpy(result, blob, (size_t)len);
    return result;
}

int32_t sqlite_column_bytes(void* stmt, int32_t col) {
    return sqlite3_column_bytes(STMT(stmt), col);
}

int32_t sqlite_column_type(void* stmt, int32_t col) {
    return sqlite3_column_type(STMT(stmt), col);
}

int32_t sqlite_column_count(void* stmt) {
    return sqlite3_column_count(STMT(stmt));
}

moonbit_bytes_t sqlite_column_name(void* stmt, int32_t col) {
    return cstring_to_bytes(sqlite3_column_name(STMT(stmt), col));
}

// ---- db-level helpers ----------------------------------------------------

int32_t sqlite_errcode(void* db) { return sqlite3_errcode(DB(db)); }
moonbit_bytes_t sqlite_errmsg(void* db) { return cstring_to_bytes(sqlite3_errmsg(DB(db))); }
int32_t sqlite_extended_errcode(void* db) { return sqlite3_extended_errcode(DB(db)); }
int32_t sqlite_changes(void* db) { return sqlite3_changes(DB(db)); }
int64_t sqlite_last_insert_rowid(void* db) { return sqlite3_last_insert_rowid(DB(db)); }
int32_t sqlite_busy_timeout(void* db, int32_t ms) { return sqlite3_busy_timeout(DB(db), ms); }
int32_t sqlite_get_autocommit(void* db) { return sqlite3_get_autocommit(DB(db)); }
int32_t sqlite_total_changes(void* db) { return sqlite3_total_changes(DB(db)); }
void sqlite_interrupt(void* db) { sqlite3_interrupt(DB(db)); }
int32_t sqlite_limit(void* db, int32_t id, int32_t newVal) { return sqlite3_limit(DB(db), id, newVal); }

moonbit_bytes_t sqlite_db_filename(void* db, moonbit_bytes_t dbname) {
    char* dbname_str = bytes_to_cstring(dbname);
    const char* filename = sqlite3_db_filename(DB(db), dbname_str);
    moonbit_bytes_t result = cstring_to_bytes(filename);
    free(dbname_str);
    return result;
}

int32_t sqlite_db_readonly(void* db, moonbit_bytes_t dbname) {
    char* dbname_str = bytes_to_cstring(dbname);
    int readonly = sqlite3_db_readonly(DB(db), dbname_str);
    free(dbname_str);
    return readonly;
}

// ---- statement introspection --------------------------------------------

moonbit_bytes_t sqlite_sql(void* stmt) { return cstring_to_bytes(sqlite3_sql(STMT(stmt))); }

int32_t sqlite_bind_parameter_count(void* stmt) { return sqlite3_bind_parameter_count(STMT(stmt)); }

int32_t sqlite_stmt_readonly(void* stmt) { return sqlite3_stmt_readonly(STMT(stmt)); }

moonbit_bytes_t sqlite_bind_parameter_name(void* stmt, int32_t idx) {
    return cstring_to_bytes(sqlite3_bind_parameter_name(STMT(stmt), idx));
}

int32_t sqlite_bind_parameter_index(void* stmt, moonbit_bytes_t name) {
    char* name_str = bytes_to_cstring(name);
    int idx = sqlite3_bind_parameter_index(STMT(stmt), name_str);
    free(name_str);
    return idx;
}

moonbit_bytes_t sqlite_expanded_sql(void* stmt) {
    char* sql = sqlite3_expanded_sql(STMT(stmt));
    moonbit_bytes_t result = cstring_to_bytes(sql);
    if (sql) sqlite3_free(sql);
    return result;
}

// ---- error strings (no handle) ------------------------------------------

moonbit_bytes_t sqlite_errstr(int32_t errcode) { return cstring_to_bytes(sqlite3_errstr(errcode)); }
