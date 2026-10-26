#ifndef _RL_STDIO_H
#define _RL_STDIO_H
#include <stddef.h>
#include <stdarg.h>
typedef struct __sFILE FILE;
extern FILE *__stdinp, *__stdoutp, *__stderrp;
#define stdin  __stdinp
#define stdout __stdoutp
#define stderr __stderrp
#define EOF (-1)
#define BUFSIZ 1024
#define SEEK_SET 0
#define SEEK_CUR 1
#define SEEK_END 2
int printf(const char *, ...);
int fprintf(FILE *, const char *, ...);
int sprintf(char *, const char *, ...);
int snprintf(char *, size_t, const char *, ...);
int vprintf(const char *, va_list);
int vfprintf(FILE *, const char *, va_list);
int vsprintf(char *, const char *, va_list);
int vsnprintf(char *, size_t, const char *, va_list);
int sscanf(const char *, const char *, ...);
int puts(const char *);
int putchar(int);
int getchar(void);
int fputs(const char *, FILE *);
int fputc(int, FILE *);
int fgetc(FILE *);
char *fgets(char *, int, FILE *);
FILE *fopen(const char *, const char *);
int fclose(FILE *);
size_t fread(void *, size_t, size_t, FILE *);
size_t fwrite(const void *, size_t, size_t, FILE *);
int fseek(FILE *, long, int);
long ftell(FILE *);
void rewind(FILE *);
int fflush(FILE *);
int feof(FILE *);
int ferror(FILE *);
int remove(const char *);
int rename(const char *, const char *);
void perror(const char *);
#endif
