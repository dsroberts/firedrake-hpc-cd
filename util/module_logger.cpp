// Set ARG_LOG_DEBUG (even to an empty value) to print errors to inherited stderr.

#include <sqlite3.h>

#include <cerrno>
#include <csignal>
#include <cstdlib>
#include <cstdio>
#include <filesystem>
#include <grp.h>
#include <memory>
#include <pwd.h>
#include <stdexcept>
#include <string>
#include <string_view>
#include <system_error>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <fcntl.h>

namespace {
[[noreturn]] void fail(const char* message) { throw std::runtime_error(message); }

[[noreturn]] void system_failure(const char* operation) {
    throw std::system_error(errno, std::generic_category(), operation);
}

[[noreturn]] void database_failure(sqlite3* db, const char* operation) {
    throw std::runtime_error(std::string(operation) + ": " +
                             (db ? sqlite3_errmsg(db) : "SQLite allocation failed"));
}

void detach(bool debug) {
    const long descriptor_limit = ::sysconf(_SC_OPEN_MAX);
    if (descriptor_limit < 0) system_failure("sysconf(_SC_OPEN_MAX)");

    pid_t child = ::fork();
    if (child < 0) system_failure("first fork");
    if (child > 0) ::_exit(EXIT_SUCCESS);
    if (::setsid() < 0) system_failure("setsid");

    struct sigaction action {};
    action.sa_handler = SIG_IGN;
    if (::sigemptyset(&action.sa_mask) < 0 ||
        ::sigaction(SIGHUP, &action, nullptr) < 0) system_failure("ignore SIGHUP");

    child = ::fork();
    if (child < 0) system_failure("second fork");
    if (child > 0) ::_exit(EXIT_SUCCESS);

    ::umask(0077);
    if (::chdir("/") < 0) system_failure("chdir(/)");

    // Close inherited descriptors, including any caller-owned pipes/sockets.
    // close_range also handles descriptors above a subsequently lowered limit.
    // Debug mode keeps the caller's stderr available in the detached process.
    if (debug) {
        ::close(STDIN_FILENO);
        ::close(STDOUT_FILENO);
    }
    const unsigned int first_fd = debug ? 3U : 0U;
#ifdef SYS_close_range
    if (::syscall(SYS_close_range, first_fd, ~0U, 0U) < 0) {
        if (errno != ENOSYS) system_failure("close_range");
#endif
        for (long fd = first_fd; fd < descriptor_limit; ++fd)
            ::close(static_cast<int>(fd));
#ifdef SYS_close_range
    }
#endif

    const int null_fd = ::open("/dev/null", O_RDWR);
    if (null_fd < 0) system_failure("open(/dev/null)");
    if (null_fd != STDIN_FILENO) fail("/dev/null did not open as stdin");
    if (::dup2(null_fd, STDOUT_FILENO) < 0 ||
        (!debug && ::dup2(null_fd, STDERR_FILENO) < 0))
        system_failure("redirect standard descriptors");
}

struct DatabaseCloser {
    void operator()(sqlite3* db) const noexcept { sqlite3_close_v2(db); }
};
using Database = std::unique_ptr<sqlite3, DatabaseCloser>;

class Statement {
    sqlite3_stmt* statement_ = nullptr;
public:
    Statement(sqlite3* db, const char* sql) {
        if (sqlite3_prepare_v2(db, sql, -1, &statement_, nullptr) != SQLITE_OK)
            database_failure(db, "prepare statement");
    }
    ~Statement() { sqlite3_finalize(statement_); }
    Statement(const Statement&) = delete;
    Statement& operator=(const Statement&) = delete;

    void integer(int index, sqlite3_int64 value) {
        if (sqlite3_bind_int64(statement_, index, value) != SQLITE_OK)
            database_failure(sqlite3_db_handle(statement_), "bind integer");
    }
    void text(int index, const std::string& value) {
        if (sqlite3_bind_text64(statement_, index, value.data(), value.size(),
                                SQLITE_TRANSIENT, SQLITE_UTF8) != SQLITE_OK)
            database_failure(sqlite3_db_handle(statement_), "bind text");
    }
    void execute() {
        if (sqlite3_step(statement_) != SQLITE_DONE)
            database_failure(sqlite3_db_handle(statement_), "execute statement");
    }
};

void execute(sqlite3* db, const char* sql) {
    if (sqlite3_exec(db, sql, nullptr, nullptr, nullptr) != SQLITE_OK)
        database_failure(db, "execute SQL");
}

void record(const std::string& path, const std::string& first,
            const std::string& second) {
    const uid_t uid = ::geteuid();
    const gid_t gid = ::getegid();
    errno = 0;
    const passwd* user = ::getpwuid(uid);
    if (!user || !user->pw_name) {
        if (errno) system_failure("getpwuid");
        fail("no username found for effective UID");
    }
    const std::string username(user->pw_name);
    errno = 0;
    const group* gr = ::getgrgid(gid);
    if (!gr || !gr->gr_name) {
        if (errno) system_failure("getgrgid");
        fail("no group name found for effective GID");
    }
    const std::string groupname(gr->gr_name);

    sqlite3* raw = nullptr;
    const int result = sqlite3_open_v2(path.c_str(), &raw,
        SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nullptr);
    Database db(raw);
    if (result != SQLITE_OK) database_failure(db.get(), "open database");
    if (sqlite3_busy_timeout(db.get(), 5000) != SQLITE_OK)
        database_failure(db.get(), "set busy timeout");

    execute(db.get(), "PRAGMA foreign_keys = ON;");
    // All changes are atomic. Closing the connection rolls back on any error.
    execute(db.get(), R"sql(
        BEGIN IMMEDIATE;
        CREATE TABLE IF NOT EXISTS users (
            uid INTEGER PRIMARY KEY,
            username TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS groups (
            gid INTEGER PRIMARY KEY,
            groupname TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS entries (
            id INTEGER PRIMARY KEY,
            argument1 TEXT NOT NULL,
            argument2 TEXT NOT NULL,
            uid INTEGER NOT NULL REFERENCES users(uid),
            gid INTEGER NOT NULL REFERENCES groups(gid),
            created_at INTEGER NOT NULL
        );
        CREATE INDEX IF NOT EXISTS entries_created_at ON entries(created_at);
    )sql");

    {
        Statement s(db.get(), "INSERT INTO users(uid, username) VALUES (?, ?) "
            "ON CONFLICT(uid) DO UPDATE SET username = excluded.username;");
        s.integer(1, uid);
        s.text(2, username);
        s.execute();
    }
    {
        Statement s(db.get(), "INSERT INTO groups(gid, groupname) VALUES (?, ?) "
            "ON CONFLICT(gid) DO UPDATE SET groupname = excluded.groupname;");
        s.integer(1, gid);
        s.text(2, groupname);
        s.execute();
    }
    {
        Statement s(db.get(), "INSERT INTO entries "
            "(argument1, argument2, uid, gid, created_at) "
            "VALUES (?, ?, ?, ?, CAST(strftime('%s', 'now') AS INTEGER));");
        s.text(1, first);
        s.text(2, second);
        s.integer(3, uid);
        s.integer(4, gid);
        s.execute();
    }
    // One calendar year in UTC, using SQLite's date arithmetic (including its
    // default leap-day normalization). Retain rows exactly at the cutoff.
    execute(db.get(), R"sql(
        DELETE FROM entries
        WHERE created_at < CAST(strftime('%s', 'now', '-1 year') AS INTEGER);
        COMMIT;
    )sql");
}
} // namespace

int main(int argc, char* argv[]) {
    const bool debug = std::getenv("ARG_LOG_DEBUG") != nullptr;
    try {
        if (argc != 3) fail("expected exactly two arguments");
        const std::string_view first(argv[1]);
        if (!first.starts_with("petsc") && !first.starts_with("firedrake"))
            ::_exit(EXIT_SUCCESS);
        // Resolve before chdir and open SQLite only after both forks.
        const auto path = std::string("/g/data/fp50/modules/.module_load_log.sqlite");
        detach(debug);
        record(path, argv[1], argv[2]);
    } catch (const std::exception& error) {
        if (debug) {
            std::fprintf(stderr, "sqlite_log: %s\n", error.what());
            std::fflush(stderr);
        }
        ::_exit(EXIT_FAILURE);
    } catch (...) {
        if (debug) {
            std::fputs("sqlite_log: unknown error\n", stderr);
            std::fflush(stderr);
        }
        ::_exit(EXIT_FAILURE);
    }
    ::_exit(EXIT_SUCCESS);
}