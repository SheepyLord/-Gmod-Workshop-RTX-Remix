#pragma once
// A strict ILuaBase stack double. Unexpected engine/metamethod operations fail the test.
#include <GarrysMod/Lua/Interface.h>
#include <cstring>
#include <memory>
#include <string>
#include <unordered_map>
#include <vector>
#include <stdexcept>

namespace nl::glass::test {
namespace Type=GarrysMod::Lua::Type;
struct Value;
using Table=std::unordered_map<std::string,Value>;
struct Value {
  int type=Type::Nil;double n=0;bool b=false;std::string s;
  GarrysMod::Lua::CFunc f=nullptr;std::shared_ptr<Table> table;Vector vector;
  static Value num(double v) { Value a;a.type=Type::Number;a.n=v;return a; }
  static Value boolean(bool v) { Value a;a.type=Type::Bool;a.b=v;return a; }
  static Value text(std::string v) { Value a;a.type=Type::String;a.s=std::move(v);return a; }
  static Value object() { Value a;a.type=Type::Table;a.table=std::make_shared<Table>();return a; }
  static Value array(std::initializer_list<Value> values) {
    auto a=object();unsigned i=0;for(const auto& v:values)(*a.table)["n"+std::to_string(++i)]=v;return a;
  }
};
class Lua final:public GarrysMod::Lua::ILuaBase {
public:
  std::vector<Value> stack;
  Value globals=Value::object();
  unsigned tables=0;
  [[noreturn]] static void unexpected() { throw std::runtime_error("unexpected ILuaBase call"); }
  Value& at(int i) {
    const auto index=i<0?int(stack.size())+i:i-1;
    if(index<0 || index>=int(stack.size())) { static Value none;none.type=Type::None;return none; }
    return stack[static_cast<unsigned>(index)];
  }
  static std::string key(const Value& v) {
    if(v.type==Type::String)return "s"+v.s;
    if(v.type==Type::Number)return "n"+std::to_string(static_cast<unsigned>(v.n));
    unexpected();
  }
  int Top() override { return static_cast<int>(stack.size()); }
  void Push(int i) override { auto copy=at(i);stack.push_back(copy); }
  void Pop(int n=1) override { if(n<0 || unsigned(n)>stack.size())unexpected();stack.resize(stack.size()-n); }
  void GetTable(int) override { unexpected(); }
  void GetField(int,const char*) override { unexpected(); }
  void SetField(int,const char*) override { unexpected(); }
  void CreateTable() override { ++tables;stack.push_back(Value::object()); }
  void SetTable(int) override { unexpected(); }
  void SetMetaTable(int) override { unexpected(); }
  bool GetMetaTable(int) override { unexpected(); }
  void Call(int,int) override { unexpected(); }
  int PCall(int,int,int) override { unexpected(); }
  int Equal(int,int) override { unexpected(); }
  int RawEqual(int,int) override { unexpected(); }
  void Insert(int i) override { const auto n=i<0?Top()+i:i-1;auto v=stack.back();stack.pop_back();stack.insert(stack.begin()+n,v); }
  void Remove(int i) override { const auto n=i<0?Top()+i:i-1;stack.erase(stack.begin()+n); }
  int Next(int) override { unexpected(); }
  void* NewUserdata(unsigned) override { unexpected(); }
  [[noreturn]] void ThrowError(const char*) override { unexpected(); }
  void CheckType(int,int) override { unexpected(); }
  [[noreturn]] void ArgError(int,const char*) override { unexpected(); }
  void RawGet(int i) override {
    auto t=at(i).table;if(!t)unexpected();const auto k=key(stack.back());stack.pop_back();
    auto found=t->find(k);stack.push_back(found==t->end()?Value{}:found->second);
  }
  void RawSet(int i) override {
    auto t=at(i).table;if(!t)unexpected();const auto k=key(stack[stack.size()-2]);
    if(stack.back().type==Type::Nil)t->erase(k);else(*t)[k]=stack.back();Pop(2);
  }
  const char* GetString(int i=-1,unsigned* length=nullptr) override {
    if(at(i).type!=Type::String)return nullptr;if(length)*length=static_cast<unsigned>(at(i).s.size());return at(i).s.data();
  }
  double GetNumber(int i=-1) override { return at(i).n; }
  bool GetBool(int i=-1) override { return at(i).b; }
  GarrysMod::Lua::CFunc GetCFunction(int i=-1) override { return at(i).f; }
  void* GetUserdata(int=-1) override { unexpected(); }
  void PushNil() override { stack.emplace_back(); }
  void PushString(const char* v,unsigned length=0) override { stack.push_back(Value::text(std::string(v,length?length:std::strlen(v)))); }
  void PushNumber(double v) override { stack.push_back(Value::num(v)); }
  void PushBool(bool v) override { stack.push_back(Value::boolean(v)); }
  void PushCFunction(GarrysMod::Lua::CFunc fn) override { Value v;v.type=Type::Function;v.f=fn;stack.push_back(v); }
  void PushCClosure(GarrysMod::Lua::CFunc,int) override { unexpected(); }
  void PushUserdata(void*) override { unexpected(); }
  int ReferenceCreate() override { unexpected(); }
  void ReferenceFree(int) override { unexpected(); }
  void ReferencePush(int) override { unexpected(); }
  void PushSpecial(int which) override { if(which!=GarrysMod::Lua::SPECIAL_GLOB)unexpected();stack.push_back(globals); }
  bool IsType(int i,int t) override { return at(i).type==t; }
  int GetType(int i) override { return at(i).type; }
  const char* GetTypeName(int) override { unexpected(); }
  void CreateMetaTableType(const char*,int) override { unexpected(); }
  const char* CheckString(int=-1) override { unexpected(); }
  double CheckNumber(int=-1) override { unexpected(); }
  int ObjLen(int i=-1) override {
    auto t=at(i).table;if(!t)unexpected();int n=0;while(t->contains("n"+std::to_string(n+1)))++n;return n;
  }
  const QAngle& GetAngle(int i=-1) override { return at(i).vector; }
  const Vector& GetVector(int i=-1) override { return at(i).vector; }
  void PushAngle(const QAngle&) override { unexpected(); }
  void PushVector(const Vector&) override { unexpected(); }
  void SetState(lua_State*) override {}
  int CreateMetaTable(const char*) override { unexpected(); }
  bool PushMetaTable(int) override { unexpected(); }
  void PushUserType(void*,int) override { unexpected(); }
  void SetUserType(int,void*) override { unexpected(); }
};
}
