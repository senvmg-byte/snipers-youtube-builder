#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>

int main(int argc, char **argv) {
    const char *hostfxr_path = getenv("SNIPERS_DOTNET_HOSTFXR");
    const char *dotnet_root = getenv("DOTNET_ROOT");
    if (hostfxr_path == NULL || hostfxr_path[0] != '/' ||
        dotnet_root == NULL || dotnet_root[0] != '/') {
        fputs("DOTNET_ROOT and SNIPERS_DOTNET_HOSTFXR must be absolute paths.\n", stderr);
        return 127;
    }

    void *hostfxr = dlopen(hostfxr_path, RTLD_NOW | RTLD_LOCAL);
    if (hostfxr == NULL) {
        fprintf(stderr, "Could not load .NET hostfxr: %s\n", dlerror());
        return 127;
    }
    int (*hostfxr_main_startupinfo)(int, const char **, const char *,
                                    const char *, const char *) =
        dlsym(hostfxr, "hostfxr_main_startupinfo");
    if (hostfxr_main_startupinfo == NULL) {
        fprintf(stderr, "Could not find hostfxr_main_startupinfo: %s\n", dlerror());
        return 127;
    }

    char **host_argv = calloc((size_t)argc + 1, sizeof(char *));
    if (host_argv == NULL) {
        perror("calloc");
        return 127;
    }
    char *dotnet = malloc(strlen(dotnet_root) + sizeof("/dotnet"));
    char *app_path = malloc(strlen(dotnet_root) + sizeof("/dotnet.dll"));
    if (dotnet == NULL || app_path == NULL) {
        perror("malloc");
        return 127;
    }
    sprintf(dotnet, "%s/dotnet", dotnet_root);
    sprintf(app_path, "%s/dotnet.dll", dotnet_root);
    host_argv[0] = dotnet;
    for (int index = 1; index < argc; index++) {
        host_argv[index] = argv[index];
    }
    return hostfxr_main_startupinfo(
        argc, (const char **)host_argv, dotnet, dotnet_root, app_path);
}
