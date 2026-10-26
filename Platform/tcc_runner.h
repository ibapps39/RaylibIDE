// Compiles C with embedded TinyCC and runs it in-process on a worker thread.
#ifndef TCC_RUNNER_H
#define TCC_RUNNER_H
#ifdef __cplusplus
extern "C" {
#endif

enum { RLRUN_STDOUT = 0, RLRUN_DIAG = 2, RLRUN_STATUS = 3 };

typedef void (*rlrun_log_fn)(int kind, const char *text, void *ctx);
typedef void (*rlrun_done_fn)(int exitCode, void *ctx);

typedef struct {
    const char  *project_dir;     // cwd of the program; also searched for "quoted" includes
    const char  *include_dir;     // directory with raylib.h + libc-lite headers
    const char  *override_dir;    // optional: headers downloaded from GitHub (searched first), may be NULL
    const char **files;           // absolute paths of .c files to compile
    int          nfiles;
    rlrun_log_fn log;
    rlrun_done_fn done;
    void        *ctx;
} rlrun_config;

int  rlrun_start(const rlrun_config *cfg);   // 0 = started, <0 = error (already running etc.)
void rlrun_request_stop(void);               // cooperative: unwinds at next raylib call
void rlrun_force_stop(void);                 // signal-based; use if the program ignores request_stop
int  rlrun_is_running(void);
int  rlrun_stop_requested(void);
void rlrun_checkpoint(void);                 // called by the platform layer
int  rlrun_jit_available(void);              // can this process make RWX memory right now?
void rlrun_capture_stdio(rlrun_log_fn log, void *ctx);   // route stdout/stderr to the console

#ifdef __cplusplus
}
#endif
#endif
