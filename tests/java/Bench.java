import java.util.*;
import java.util.stream.*;
public class Bench {
    static int fib(int n) { return n < 2 ? n : fib(n - 1) + fib(n - 2); }
    interface Shape { double area(); }
    record Circle(double r) implements Shape { public double area() { return Math.PI * r * r; } }
    record Sq(double s) implements Shape { public double area() { return s * s; } }
    public static void main(String[] a) throws Exception {
        long t0 = System.nanoTime();
        System.out.println("fib(30) = " + fib(30));
        Map<String, Integer> m = new HashMap<>();
        for (int i = 0; i < 200000; i++) m.merge("k" + (i % 1000), i, Integer::sum);
        System.out.println("map " + m.size() + " " + m.get("k7"));
        List<Shape> shapes = new ArrayList<>();
        Random rnd = new Random(42);
        for (int i = 0; i < 300000; i++) shapes.add(rnd.nextBoolean() ? new Circle(rnd.nextDouble()) : new Sq(rnd.nextDouble()));
        double s = shapes.stream().mapToDouble(Shape::area).sum();
        System.out.printf("area %.6f%n", s);
        String txt = IntStream.range(0, 50000).mapToObj(Integer::toString).collect(Collectors.joining(","));
        System.out.println("sha " + Integer.toHexString(txt.hashCode()));
        int[] arr = rnd.ints(1_000_000).toArray(); Arrays.sort(arr);
        System.out.println("sorted " + arr[0] + " " + arr[arr.length - 1]);
        // null-pointer exceptions (SIGSEGV-based implicit null checks)
        int npe = 0; Object o = null;
        for (int i = 0; i < 10000; i++) try { o.hashCode(); } catch (NullPointerException e) { npe++; }
        System.out.println("npe " + npe);
        // threads
        Thread[] ts = new Thread[4]; long[] sums = new long[4];
        for (int k = 0; k < 4; k++) { final int kk = k; ts[k] = new Thread(() -> { long x = 0; for (int i = 0; i < 20_000_000; i++) x += i ^ kk; sums[kk] = x; }); ts[k].start(); }
        for (Thread t : ts) t.join();
        System.out.println("threads " + Arrays.toString(sums));
        System.out.println("ms " + (System.nanoTime() - t0) / 1_000_000);
    }
}
