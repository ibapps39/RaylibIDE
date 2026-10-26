#ifndef _RL_ERRNO_H
#define _RL_ERRNO_H
int *__error(void);
#define errno (*__error())
#define ENOENT 2
#define EINTR 4
#define EIO 5
#define ENOMEM 12
#define EACCES 13
#define EEXIST 17
#define EINVAL 22
#endif
