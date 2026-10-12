// Floating-point loops: matrix multiply, n-body, mandelbrot.
#include <math.h>
#include <stdio.h>
#define N 384
static double A[N][N], B[N][N], C[N][N];
typedef struct { double x, y, z, vx, vy, vz, m; } Body;
int main(void) {
    for (int i = 0; i < N; i++) for (int j = 0; j < N; j++) { A[i][j] = (i * j % 7) * 0.5; B[i][j] = (i + j) % 5 - 2.0; }
    for (int i = 0; i < N; i++) for (int k = 0; k < N; k++) { double a = A[i][k]; for (int j = 0; j < N; j++) C[i][j] += a * B[k][j]; }
    Body b[5] = {{0,0,0,0,0,0,39.47}, {4.84,-1.16,-0.10,0.606,2.81,-0.02,0.037}, {8.34,4.12,-0.4,-1.01,1.82,0.008,0.011},
                 {12.89,-15.11,-0.22,1.08,0.868,-0.01,0.0017}, {15.37,-25.9,0.179,0.979,0.594,-0.034,0.002}};
    for (int step = 0; step < 3000000; step++) {
        for (int i = 0; i < 5; i++) for (int j = i + 1; j < 5; j++) {
            double dx = b[i].x - b[j].x, dy = b[i].y - b[j].y, dz = b[i].z - b[j].z;
            double d2 = dx * dx + dy * dy + dz * dz, mag = 0.01 / (d2 * sqrt(d2));
            b[i].vx -= dx * b[j].m * mag; b[i].vy -= dy * b[j].m * mag; b[i].vz -= dz * b[j].m * mag;
            b[j].vx += dx * b[i].m * mag; b[j].vy += dy * b[i].m * mag; b[j].vz += dz * b[i].m * mag;
        }
        for (int i = 0; i < 5; i++) { b[i].x += 0.01 * b[i].vx; b[i].y += 0.01 * b[i].vy; b[i].z += 0.01 * b[i].vz; }
    }
    int inside = 0;
    for (int y = 0; y < 600; y++) for (int x = 0; x < 800; x++) {
        float cr = x / 400.0f - 2.0f, ci = y / 300.0f - 1.0f, zr = 0, zi = 0; int it = 0;
        while (it < 200 && zr * zr + zi * zi < 4.0f) { float t = zr * zr - zi * zi + cr; zi = 2 * zr * zi + ci; zr = t; it++; }
        inside += it == 200;
    }
    printf("%g %g %d\n", C[17][33], b[1].x, inside);
    return 0;
}
