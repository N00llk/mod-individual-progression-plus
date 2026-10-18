/*
 * mpqread - extract or verify one internal file in an MPQ via StormLib.
 *
 * Usage: mpqread <archive.MPQ> <internal\path> <out_path>
 *        mpqread verify <archive.MPQ> <internal\path> <source_path>
 * Internal paths use backslashes, e.g. DBFilesClient\Spell.dbc
 *
 * Exit status: 0 on success, nonzero on any failure (message on stderr).
 */
#include <StormLib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* StormLib on Linux reports errors via SErrGetLastError() (errno-space plus
 * a handful of StormLib-only codes) - there is no GetLastError() on this
 * platform, so use the same accessor mpqpack.c uses. */

int main(int argc, char** argv) {
    int verify = argc == 5 && strcmp(argv[1], "verify") == 0;
    if ((!verify && argc != 4) || (argc == 5 && !verify)) {
        fprintf(stderr, "usage: mpqread [verify] <mpq> <internal> <path>\n");
        return 2;
    }

    const char* archivePath = argv[verify ? 2 : 1];
    const char* internalPath = argv[verify ? 3 : 2];
    const char* outPath = argv[verify ? 4 : 3];

    HANDLE mpq = NULL, file = NULL;
    if (!SFileOpenArchive(archivePath, 0, MPQ_OPEN_READ_ONLY, &mpq)) {
        fprintf(stderr, "SFileOpenArchive(%s) failed: %u\n", archivePath, SErrGetLastError());
        return 1;
    }
    if (!SFileOpenFileEx(mpq, internalPath, 0, &file)) {
        fprintf(stderr, "SFileOpenFileEx(%s) failed: %u\n", internalPath, SErrGetLastError());
        SFileCloseArchive(mpq);
        return 1;
    }

    DWORD size = SFileGetFileSize(file, NULL);
    if (verify) {
        FILE* reference = fopen(outPath, "rb");
        if (!reference) {
            fprintf(stderr, "fopen(%s) failed\n", outPath);
            SFileCloseFile(file); SFileCloseArchive(mpq);
            return 1;
        }
        unsigned char buf[65536];
        unsigned char expected[65536];
        DWORD remaining = size;
        int equal = 1;
        while (remaining > 0) {
            DWORD want = remaining < sizeof(buf) ? remaining : sizeof(buf);
            DWORD got = 0;
            if (!SFileReadFile(file, buf, want, &got, NULL) || got != want ||
                fread(expected, 1, want, reference) != want ||
                memcmp(buf, expected, want) != 0) {
                equal = 0;
                break;
            }
            remaining -= want;
        }
        if (fgetc(reference) != EOF) equal = 0;
        fclose(reference);
        SFileCloseFile(file); SFileCloseArchive(mpq);
        if (!equal) {
            fprintf(stderr, "Mismatch: %s does not match %s\n", internalPath, outPath);
            return 1;
        }
        fprintf(stderr, "OK: %s matches %s\n", internalPath, outPath);
        return 0;
    }

    unsigned char* buf = (unsigned char*)malloc(size);
    if (!buf) {
        fprintf(stderr, "malloc(%u) failed\n", size);
        SFileCloseFile(file); SFileCloseArchive(mpq);
        return 1;
    }

    DWORD got = 0;
    if (!SFileReadFile(file, buf, size, &got, NULL) && got != size) {
        fprintf(stderr, "SFileReadFile failed: %u (got %u/%u)\n", SErrGetLastError(), got, size);
        free(buf); SFileCloseFile(file); SFileCloseArchive(mpq);
        return 1;
    }

    FILE* out = fopen(outPath, "wb");
    if (!out) {
        fprintf(stderr, "fopen(%s) failed\n", outPath);
        free(buf); SFileCloseFile(file); SFileCloseArchive(mpq);
        return 1;
    }
    fwrite(buf, 1, got, out);
    fclose(out);
    free(buf);

    SFileCloseFile(file);
    SFileCloseArchive(mpq);

    fprintf(stderr, "wrote %u bytes -> %s\n", got, outPath);
    return 0;
}
