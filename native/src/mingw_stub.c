// Stub for MinGW runtime functions when linking with MSVC
// This provides compatibility symbols that FFmpeg (built with MinGW) expects

#ifdef _MSC_VER
// MSVC implementation

#include <windows.h>
#include <time.h>
#include <math.h>

// ___chkstk_ms: MinGW stack checking function
// MSVC has its own stack checking, so we provide a no-op stub
void __chkstk_ms(void) {
    // No-op: MSVC handles stack checking automatically on x64
}

// Export with MinGW naming convention (double underscore prefix)
void ___chkstk_ms(void) {
    __chkstk_ms();
}

// clock_gettime64: MinGW time function
// Stub implementation using Windows API
int clock_gettime64(int clock_id, struct timespec *tp) {
    (void)clock_id; // Unused parameter
    FILETIME ft;
    ULARGE_INTEGER uli;
    GetSystemTimeAsFileTime(&ft);
    uli.LowPart = ft.dwLowDateTime;
    uli.HighPart = ft.dwHighDateTime;
    // Convert from 100-nanosecond intervals since 1601-01-01 to seconds since 1970-01-01
    uli.QuadPart -= 116444736000000000ULL;
    tp->tv_sec = (long)(uli.QuadPart / 10000000ULL);
    tp->tv_nsec = (long)((uli.QuadPart % 10000000ULL) * 100);
    return 0;
}

// nanosleep64: MinGW sleep function
// Stub implementation using Windows API
int nanosleep64(const struct timespec *req, struct timespec *rem) {
    DWORD ms = (DWORD)(req->tv_sec * 1000 + req->tv_nsec / 1000000);
    Sleep(ms);
    if (rem) {
        rem->tv_sec = 0;
        rem->tv_nsec = 0;
    }
    return 0;
}

// sincos: GNU math extension (simultaneous sin and cos)
// MSVC doesn't have this, so we provide it
void sincos(double x, double *sinx, double *cosx) {
    *sinx = sin(x);
    *cosx = cos(x);
}

// sincosf: float version of sincos
void sincosf(float x, float *sinx, float *cosx) {
    *sinx = sinf(x);
    *cosx = cosf(x);
}

// IID_ICodecAPI: Windows Media Foundation interface GUID
// FFmpeg (built with MinGW) expects this GUID to be defined
// We define it explicitly here to ensure it's available for linking
#include <initguid.h>
#include <codecapi.h>

// Define IID_ICodecAPI explicitly to ensure it's exported
// This GUID is from codecapi.h: {901db4c7-31ce-41a2-85dc-8fa0bf41b8da}
DEFINE_GUID(IID_ICodecAPI, 0x901db4c7, 0x31ce, 0x41a2, 0x85, 0xdc, 0x8f, 0xa0, 0xbf, 0x41, 0xb8, 0xda);

#endif // _MSC_VER
