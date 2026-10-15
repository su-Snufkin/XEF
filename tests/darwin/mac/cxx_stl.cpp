#include <iostream>
#include <sstream>
#include <fstream>
#include <iomanip>
#include <vector>
#include <list>
#include <map>
#include <unordered_map>
#include <set>
#include <string>
#include <algorithm>
#include <numeric>
#include <functional>
#include <memory>
#include <optional>
#include <variant>
#include <thread>
#include <mutex>
#include <atomic>
#include <chrono>
#include <regex>
#include <random>
#include <filesystem>
#include <cmath>
struct Base{ virtual ~Base()=default; virtual std::string name() const {return "base";} };
struct Derived:Base{ std::string name() const override {return "derived";} };
template<class T> T sq(T x){return x*x;}
int main(){
  std::ostringstream os; os<<std::fixed<<std::setprecision(3)<<3.14159<<" "<<std::hex<<255<<" "<<std::setw(6)<<std::setfill('*')<<42; std::cout<<os.str()<<"\n";
  std::vector<int> v(10); std::iota(v.begin(),v.end(),1); std::cout<<std::accumulate(v.begin(),v.end(),0)<<"\n";
  std::unordered_map<std::string,int> um{{"a",1},{"b",2},{"c",3}}; int s=0; for(auto&[k,x]:um) s+=x; std::cout<<s<<"\n";
  std::set<std::string> st{"z","a","m"}; for(auto&x:st) std::cout<<x; std::cout<<"\n";
  std::unique_ptr<Base> p=std::make_unique<Derived>(); std::cout<<p->name()<<" "<<(dynamic_cast<Derived*>(p.get())!=nullptr)<<"\n";
  std::shared_ptr<int> sp=std::make_shared<int>(9); auto sp2=sp; std::cout<<sp.use_count()<<"\n";
  std::optional<int> o=5; std::variant<int,std::string> va="str"; std::cout<<*o<<std::get<std::string>(va)<<"\n";
  std::function<int(int)> f=[](int x){return x*3;}; std::cout<<f(4)<<sq(1.5)<<"\n";
  std::mutex m; std::atomic<int> cnt{0}; std::vector<std::thread> th; for(int i=0;i<4;i++) th.emplace_back([&]{for(int j=0;j<500;j++){std::lock_guard<std::mutex> g(m);cnt++;}}); for(auto&t:th)t.join(); std::cout<<cnt<<"\n";
  std::regex re("(\\d+)-(\\w+)"); std::smatch mm; std::string in="id 123-abc end"; if(std::regex_search(in,mm,re)) std::cout<<mm[1]<<mm[2]<<"\n";
  std::mt19937 g(42); std::cout<<g()<<" "<<std::uniform_int_distribution<int>(1,100)(g)<<"\n";
  auto t0=std::chrono::steady_clock::now(); std::this_thread::sleep_for(std::chrono::milliseconds(5)); std::cout<<(std::chrono::steady_clock::now()-t0>=std::chrono::milliseconds(5))<<"\n";
  { std::ofstream of("/tmp/xef_cxx.txt"); of<<"hello file\n12 34\n"; } std::ifstream inf("/tmp/xef_cxx.txt"); std::string line; std::getline(inf,line); int a,b; inf>>a>>b; std::cout<<line<<a+b<<"\n";
  std::cout<<std::filesystem::exists("/tmp/xef_cxx.txt")<<std::filesystem::file_size("/tmp/xef_cxx.txt")<<"\n"; std::filesystem::remove("/tmp/xef_cxx.txt");
  try{ std::vector<int> e; e.at(3); }catch(const std::out_of_range&){ std::cout<<"oor\n"; }
  try{ throw 42; }catch(int x){ std::cout<<"int "<<x<<"\n"; }
  std::string str="The quick brown fox"; std::transform(str.begin(),str.end(),str.begin(),::toupper); std::cout<<str<<" "<<str.find("QUICK")<<"\n";
  std::cout<<std::stod("2.5")+std::stoi("4")<<" "<<std::to_string(3.5)<<" "<<std::sqrt(2.0)<<"\n";
  std::cerr<<"to stderr\n"; return 0; }
