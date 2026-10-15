#include <iostream>
#include <vector>
#include <string>
#include <map>
#include <algorithm>
#include <memory>
#include <stdexcept>
int main(){
  std::vector<int> v{5,3,1,4}; std::sort(v.begin(),v.end());
  std::map<std::string,int> m; m["a"]=1; m["b"]=2;
  auto p=std::make_unique<std::string>("unique");
  std::cout<<"cpp "<<v[0]<<" "<<m["b"]<<" "<<*p<<"\n";
  try{ throw std::runtime_error("boom"); }catch(std::exception&e){ std::cout<<"caught "<<e.what()<<"\n"; }
}
