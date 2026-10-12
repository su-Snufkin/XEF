#include <algorithm>
#include <iostream>
#include <map>
#include <memory>
#include <sstream>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <vector>
struct Shape { virtual ~Shape() {} virtual double area() const = 0; virtual const char* name() const = 0; };
struct Sq : Shape { double s; Sq(double s) : s(s) {} double area() const override { return s * s; } const char* name() const override { return "sq"; } };
struct Ci : Shape { double r; Ci(double r) : r(r) {} double area() const override { return 3.14159 * r * r; } const char* name() const override { return "ci"; } };
int thrower(int x) { if (x % 3 == 0) throw std::runtime_error("bad " + std::to_string(x)); return x * 2; }
int main() {
    std::vector<std::unique_ptr<Shape>> v;
    for (int i = 0; i < 1000; i++) {
        if (i & 1) v.emplace_back(new Sq(i * 0.5)); else v.emplace_back(new Ci(i * 0.25));
    }
    double tot = 0;
    for (auto& s : v) tot += s->area();
    std::sort(v.begin(), v.end(), [](auto& a, auto& b) { return a->area() < b->area(); });
    std::cout << "total " << tot << " first " << v.front()->name() << " last " << v.back()->area() << "\n";
    int caught = 0, sum = 0;
    for (int i = 0; i < 300; i++) {
        try { sum += thrower(i); } catch (const std::exception& e) { caught++; if (i == 297) std::cout << e.what() << "\n"; }
    }
    std::cout << "caught " << caught << " sum " << sum << "\n";
    std::map<std::string, int> m;
    std::unordered_map<int, std::string> um;
    for (int i = 0; i < 5000; i++) { m["k" + std::to_string(i % 731)] += i; um[i * 37 % 1009] = std::to_string(i); }
    std::ostringstream os;
    os << m.size() << " " << m["k5"] << " " << um.size() << " " << um[37];
    std::cout << os.str() << std::endl;
    std::string s = "the quick brown fox jumps over the lazy dog";
    std::reverse(s.begin(), s.end());
    std::cout << s << " " << std::count(s.begin(), s.end(), 'o') << std::endl;
    return 0;
}
