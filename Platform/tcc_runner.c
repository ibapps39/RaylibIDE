#include <stdio.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <setjmp.h>
#include <pthread.h>
#include <unistd.h>
#include <sys/mman.h>
#include "libtcc.h"
#include "raylib.h"
#include "rlgl.h"
#include "tcc_runner.h"

static pthread_t g_thread;
static volatile int g_running = 0, g_stop = 0, g_jmp_valid = 0;
static sigjmp_buf g_jmp;
static volatile int g_crash_sig = 0;
static volatile void *g_crash_addr = NULL;
static rlrun_config g_cfg;
static char g_cwd_backup[1024];

static void logf_(int kind, const char *fmt, ...)
{
    char buf[1024];
    va_list ap; va_start(ap, fmt); vsnprintf(buf, sizeof buf, fmt, ap); va_end(ap);
    if (g_cfg.log) g_cfg.log(kind, buf, g_cfg.ctx);
}

//------------------------------------------------------------------------------
// Stop / crash handling
//------------------------------------------------------------------------------
int rlrun_stop_requested(void) { return g_stop; }
int rlrun_is_running(void)     { return g_running; }

void rlrun_checkpoint(void)
{
    if (g_stop && g_jmp_valid && pthread_equal(pthread_self(), g_thread)) siglongjmp(g_jmp, 2);
}

static void fault_handler(int sig, siginfo_t *si, void *uc)
{
    (void)uc;
    if (g_jmp_valid && pthread_equal(pthread_self(), g_thread)) {
        g_crash_sig = sig;
        g_crash_addr = si ? si->si_addr : NULL;
        siglongjmp(g_jmp, sig == SIGUSR2 ? 2 : 3);
    }
    signal(sig, SIG_DFL);
    raise(sig);
}

static void install_handlers_once(void)
{
    static int done = 0;
    if (done) return;
    done = 1;
    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_sigaction = fault_handler;
    sa.sa_flags = SA_SIGINFO | SA_NODEFER;
    sigemptyset(&sa.sa_mask);
    int sigs[] = { SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGABRT, SIGUSR2 };
    for (unsigned i = 0; i < sizeof sigs/sizeof sigs[0]; i++) sigaction(sigs[i], &sa, NULL);
}

void rlrun_request_stop(void) { g_stop = 1; }
void rlrun_force_stop(void)   { if (g_running) pthread_kill(g_thread, SIGUSR2); }

// Programs calling exit()/abort() must not take the whole app down.
static void hook_exit(int code)  { (void)code; if (g_jmp_valid) siglongjmp(g_jmp, 4); pthread_exit(NULL); }
static void hook_abort(void)     { if (g_jmp_valid) siglongjmp(g_jmp, 4); pthread_exit(NULL); }

//------------------------------------------------------------------------------
// JIT probe
//------------------------------------------------------------------------------
int rlrun_jit_available(void)
{
    size_t sz = 16384;
    void *p = mmap(NULL, sz, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    if (p == MAP_FAILED) return 0;
    int ok = (mprotect(p, sz, PROT_READ | PROT_WRITE | PROT_EXEC) == 0);
    munmap(p, sz);
    return ok;
}

//------------------------------------------------------------------------------
// stdout/stderr capture
//------------------------------------------------------------------------------
static int g_pipe[2] = { -1, -1 };
static rlrun_log_fn g_cap_fn; static void *g_cap_ctx;

static void *capture_thread(void *arg)
{
    (void)arg;
    char buf[2048];
    ssize_t n;
    while ((n = read(g_pipe[0], buf, sizeof buf - 1)) > 0) {
        buf[n] = 0;
        if (g_cap_fn) g_cap_fn(RLRUN_STDOUT, buf, g_cap_ctx);
    }
    return NULL;
}

void rlrun_capture_stdio(rlrun_log_fn log, void *ctx)
{
    if (g_pipe[0] >= 0) { g_cap_fn = log; g_cap_ctx = ctx; return; }
    g_cap_fn = log; g_cap_ctx = ctx;
    if (pipe(g_pipe) != 0) return;
    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);
    dup2(g_pipe[1], STDOUT_FILENO);
    dup2(g_pipe[1], STDERR_FILENO);
    pthread_t t;
    pthread_create(&t, NULL, capture_thread, NULL);
    pthread_detach(t);
}

//------------------------------------------------------------------------------
// Compile + run
//------------------------------------------------------------------------------
static void tcc_err(void *opaque, const char *msg) { (void)opaque; if (g_cfg.log) g_cfg.log(RLRUN_DIAG, msg, g_cfg.ctx); }

static void register_symbols(TCCState *s)
{
#define RL_SYM(n) tcc_add_symbol(s, #n, (const void *)n);
#include "raylib_symbols.inc"
#undef RL_SYM
    tcc_add_symbol(s, "exit",  (const void *)hook_exit);
    tcc_add_symbol(s, "_exit", (const void *)hook_exit);
    tcc_add_symbol(s, "abort", (const void *)hook_abort);
}

static void *worker(void *arg)
{
    (void)arg;
    int rc = 0;
    TCCState *s = tcc_new();
    int compiled = 0;

    if (!s) { logf_(RLRUN_DIAG, "internal: tcc_new failed"); rc = -1; goto out; }

    tcc_set_error_func(s, NULL, tcc_err);
    tcc_set_options(s, "-nostdlib -nostdinc -w");
    tcc_set_output_type(s, TCC_OUTPUT_MEMORY);
    tcc_set_lib_path(s, g_cfg.include_dir);
    if (g_cfg.override_dir && g_cfg.override_dir[0]) tcc_add_sysinclude_path(s, g_cfg.override_dir);
    tcc_add_sysinclude_path(s, g_cfg.include_dir);
    tcc_add_include_path(s, g_cfg.project_dir);
    tcc_define_symbol(s, "__IOS__", "1");
    tcc_define_symbol(s, "PLATFORM_IOS", "1");
    register_symbols(s);

    logf_(RLRUN_STATUS, "Compiling…");
    for (int i = 0; i < g_cfg.nfiles; i++) {
        if (tcc_add_file(s, g_cfg.files[i]) < 0) { rc = -2; goto out; }
    }
    if (tcc_relocate(s) < 0) {
        logf_(RLRUN_DIAG, "error: could not map executable memory. JIT must be enabled for this app (see Settings → JIT).");
        rc = -3; goto out;
    }
    compiled = 1;

    int (*entry)(int, char **) = (int (*)(int, char **))tcc_get_symbol(s, "main");
    if (!entry) { logf_(RLRUN_DIAG, "error: no main() function found"); rc = -4; goto out; }

    getcwd(g_cwd_backup, sizeof g_cwd_backup);
    chdir(g_cfg.project_dir);
    logf_(RLRUN_STATUS, "Running");

    {
        char *argv[] = { "program", NULL };
        int j = sigsetjmp(g_jmp, 1);
        if (j == 0) { g_jmp_valid = 1; rc = entry(1, argv); }
        else if (j == 3) {
            logf_(RLRUN_DIAG, "runtime crash: signal %d at address %p", (int)g_crash_sig, (void *)g_crash_addr);
            rc = 128 + (int)g_crash_sig;
        }
        else if (j == 4) { rc = 0; }
        else { rc = 0; logf_(RLRUN_STATUS, "Stopped"); }
        g_jmp_valid = 0;
    }

    if (IsWindowReady()) CloseWindow();
    chdir(g_cwd_backup);

out:
    if (s) tcc_delete(s);
    (void)compiled;
    g_running = 0;
    if (g_cfg.done) g_cfg.done(rc, g_cfg.ctx);
    return NULL;
}

int rlrun_start(const rlrun_config *cfg)
{
    if (g_running) return -1;
    install_handlers_once();
    g_cfg = *cfg;
    // deep-copy everything the worker thread will read after the caller returns
    g_cfg.project_dir  = strdup(cfg->project_dir);
    g_cfg.include_dir  = strdup(cfg->include_dir);
    g_cfg.override_dir = cfg->override_dir ? strdup(cfg->override_dir) : NULL;
    const char **files = (const char **)calloc(cfg->nfiles + 1, sizeof(char *));
    for (int i = 0; i < cfg->nfiles; i++) files[i] = strdup(cfg->files[i]);
    g_cfg.files = files;
    g_stop = 0;
    g_running = 1;
    pthread_attr_t at;
    pthread_attr_init(&at);
    pthread_attr_setstacksize(&at, 8 * 1024 * 1024);
    int r = pthread_create(&g_thread, &at, worker, NULL);
    pthread_attr_destroy(&at);
    if (r != 0) { g_running = 0; return -2; }
    pthread_detach(g_thread);
    return 0;
}
