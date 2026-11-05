// The Lua boundary of the bridge (R19, BR-02), against a small in-memory stand-in
// for Garry's Mod's ILuaBase: a request string's length is checked before any of
// it is copied, and no C++ exception leaves an exported function.
#ifdef NDEBUG
#undef NDEBUG
#endif

// The bindings' internal functions (Apply, Clear, Guarded, ...) are in an
// anonymous namespace; including the source makes them reachable here.
#include "../src/lua_bindings.cpp"

#include <chrono>
#include <cstdlib>
#include <iostream>
#include <map>
#include <memory>
#include <new>
#include <string>
#include <vector>

namespace {

namespace LuaType = GarrysMod::Lua::Type;
using GarrysMod::Lua::CFunc;

int g_failures = 0;

#define EXPECT(condition)                                                        \
    do {                                                                         \
        if (!(condition)) {                                                      \
            std::cerr << "FAILED line " << __LINE__ << ": " #condition "\n";     \
            ++g_failures;                                                        \
        }                                                                        \
    } while (false)

struct Table;

struct Value {
    int type = LuaType::Nil;
    bool boolean = false;
    double number = 0.0;
    std::shared_ptr<const std::string> text;
    std::shared_ptr<Table> table;
};

struct Table {
    std::map<std::string, Value> fields;
    std::map<double, Value> items;
};

Value Nil() { return {}; }

Value Text(std::string value) {
    Value result;
    result.type = LuaType::String;
    result.text = std::make_shared<const std::string>(std::move(value));
    return result;
}

Value SharedText(const std::shared_ptr<const std::string>& value) {
    Value result;
    result.type = LuaType::String;
    result.text = value;
    return result;
}

Value NewTable() {
    Value result;
    result.type = LuaType::Table;
    result.table = std::make_shared<Table>();
    return result;
}

Value Array(const std::vector<Value>& values) {
    Value result = NewTable();
    double index = 1.0;
    for (const auto& value : values) result.table->items[index++] = value;
    return result;
}

[[noreturn]] void Unsupported() {
    std::cerr << "the test called an ILuaBase function the stand-in does not implement\n";
    std::abort();
}

// Just enough of a Lua stack for the bindings: tables with string and number
// keys, strings, numbers, booleans and C functions as opaque values.
class FakeLua final : public GarrysMod::Lua::ILuaBase {
public:
    std::vector<Value> stack;
    Value globals = NewTable();
    // GetField throws std::bad_alloc when it is asked for this field.
    std::string throwOnField;

    std::size_t Absolute(int index) const {
        const auto position = index > 0 ? index - 1 : static_cast<int>(stack.size()) + index;
        if (position < 0 || position >= static_cast<int>(stack.size())) Unsupported();
        return static_cast<std::size_t>(position);
    }
    Value& At(int index) { return stack[Absolute(index)]; }

    static Value Lookup(const Value& table, const Value& key) {
        if (table.type != LuaType::Table) return Nil();
        if (key.type == LuaType::String) {
            const auto found = table.table->fields.find(*key.text);
            return found == table.table->fields.end() ? Nil() : found->second;
        }
        if (key.type == LuaType::Number) {
            const auto found = table.table->items.find(key.number);
            return found == table.table->items.end() ? Nil() : found->second;
        }
        return Nil();
    }

    int Top() override { return static_cast<int>(stack.size()); }
    void Push(int index) override { stack.push_back(At(index)); }
    void Pop(int amount) override {
        if (amount < 0 || static_cast<std::size_t>(amount) > stack.size()) Unsupported();
        stack.resize(stack.size() - static_cast<std::size_t>(amount));
    }
    void GetTable(int index) override {
        const Value table = At(index);
        const Value key = stack.back();
        stack.pop_back();
        stack.push_back(Lookup(table, key));
    }
    void GetField(int index, const char* name) override {
        if (!throwOnField.empty() && throwOnField == name) throw std::bad_alloc();
        stack.push_back(Lookup(At(index), Text(name)));
    }
    void SetField(int index, const char* name) override {
        Value table = At(index);
        const Value value = stack.back();
        stack.pop_back();
        if (table.type != LuaType::Table) Unsupported();
        table.table->fields[name] = value;
    }
    void CreateTable() override { stack.push_back(NewTable()); }
    void SetTable(int index) override {
        Value table = At(index);
        const Value value = stack.back();
        stack.pop_back();
        const Value key = stack.back();
        stack.pop_back();
        if (table.type != LuaType::Table) Unsupported();
        if (key.type == LuaType::String) table.table->fields[*key.text] = value;
        else if (key.type == LuaType::Number) table.table->items[key.number] = value;
        else Unsupported();
    }
    void SetMetaTable(int) override { Unsupported(); }
    bool GetMetaTable(int) override { Unsupported(); }
    void Call(int, int) override { Unsupported(); }
    int PCall(int, int, int) override { Unsupported(); }
    int Equal(int, int) override { Unsupported(); }
    int RawEqual(int, int) override { Unsupported(); }
    void Insert(int) override { Unsupported(); }
    void Remove(int) override { Unsupported(); }
    int Next(int) override { Unsupported(); }
    void* NewUserdata(unsigned int) override { Unsupported(); }
    [[noreturn]] void ThrowError(const char*) override { Unsupported(); }
    void CheckType(int, int) override { Unsupported(); }
    [[noreturn]] void ArgError(int, const char*) override { Unsupported(); }
    void RawGet(int) override { Unsupported(); }
    void RawSet(int) override { Unsupported(); }
    const char* GetString(int index, unsigned int* length) override {
        const Value& value = At(index);
        if (value.type != LuaType::String) return nullptr;
        if (length) *length = static_cast<unsigned int>(value.text->size());
        return value.text->c_str();
    }
    double GetNumber(int index) override {
        const Value& value = At(index);
        return value.type == LuaType::Number ? value.number : 0.0;
    }
    bool GetBool(int index) override {
        const Value& value = At(index);
        return value.type == LuaType::Bool && value.boolean;
    }
    CFunc GetCFunction(int) override { Unsupported(); }
    void* GetUserdata(int) override { Unsupported(); }
    void PushNil() override { stack.push_back(Nil()); }
    void PushString(const char* value, unsigned int length) override {
        stack.push_back(Text(length ? std::string(value, length) : std::string(value)));
    }
    void PushNumber(double value) override {
        Value result;
        result.type = LuaType::Number;
        result.number = value;
        stack.push_back(result);
    }
    void PushBool(bool value) override {
        Value result;
        result.type = LuaType::Bool;
        result.boolean = value;
        stack.push_back(result);
    }
    void PushCFunction(CFunc) override {
        Value result;
        result.type = LuaType::Function;
        stack.push_back(result);
    }
    void PushCClosure(CFunc, int) override { Unsupported(); }
    void PushUserdata(void*) override { Unsupported(); }
    int ReferenceCreate() override { Unsupported(); }
    void ReferenceFree(int) override { Unsupported(); }
    void ReferencePush(int) override { Unsupported(); }
    void PushSpecial(int type) override {
        if (type != GarrysMod::Lua::SPECIAL_GLOB) Unsupported();
        stack.push_back(globals);
    }
    bool IsType(int index, int type) override { return At(index).type == type; }
    int GetType(int index) override { return At(index).type; }
    const char* GetTypeName(int) override { Unsupported(); }
    void CreateMetaTableType(const char*, int) override { Unsupported(); }
    const char* CheckString(int) override { Unsupported(); }
    double CheckNumber(int) override { Unsupported(); }
    int ObjLen(int index) override {
        const Value& value = At(index);
        if (value.type == LuaType::String) return static_cast<int>(value.text->size());
        if (value.type != LuaType::Table) return 0;
        int length = 0;
        while (value.table->items.count(static_cast<double>(length + 1))) ++length;
        return length;
    }
    const QAngle& GetAngle(int) override { Unsupported(); }
    const Vector& GetVector(int) override { Unsupported(); }
    void PushAngle(const QAngle&) override { Unsupported(); }
    void PushVector(const Vector&) override { Unsupported(); }
    void SetState(lua_State*) override { Unsupported(); }
    int CreateMetaTable(const char*) override { Unsupported(); }
    bool PushMetaTable(int) override { Unsupported(); }
    void PushUserType(void*, int) override { Unsupported(); }
    void SetUserType(int, void*) override { Unsupported(); }
};

// Calls an exported function the way Lua does: the request is argument 1, and
// the results are the values the function left on top.
std::vector<Value> Call(FakeLua& lua, int (*function)(GarrysMod::Lua::ILuaBase*),
                        const Value& request) {
    lua.stack.clear();
    lua.stack.push_back(request);
    const int count = advmat::rtx_bridge::Guarded(&lua, function);
    EXPECT(count >= 1 && static_cast<std::size_t>(count) <= lua.stack.size());
    std::vector<Value> results;
    for (std::size_t index = lua.stack.size() - static_cast<std::size_t>(count);
         index < lua.stack.size(); ++index) {
        results.push_back(lua.stack[index]);
    }
    lua.stack.clear();
    return results;
}

bool Refused(const std::vector<Value>& results, const std::string& reason) {
    return results.size() == 2 && results[0].type == LuaType::Bool && !results[0].boolean &&
        results[1].type == LuaType::String &&
        results[1].text->find(reason) != std::string::npos;
}

Value Request(const Value& hashes) {
    Value request = NewTable();
    Value target = NewTable();
    target.table->fields["material"] = Text("models/test/skin");
    request.table->fields["target"] = target;
    request.table->fields["hashes"] = hashes;
    return request;
}

} // namespace

int main() {
    namespace bridge = advmat::rtx_bridge;
    FakeLua lua;
    // A game root that does not exist: the provider registers, unavailable, and
    // every call that reaches it fails with not_initialized after parsing.
    const auto nonce = std::chrono::steady_clock::now().time_since_epoch().count();
    const auto missingRoot = std::filesystem::temp_directory_path() /
        ("advmat_lua_binding_test_missing_" + std::to_string(nonce));
    EXPECT(bridge::RegisterLua(&lua, missingRoot));
    EXPECT(lua.stack.empty());
    EXPECT(lua.globals.table->fields.count("AdvMatRTXBridge") == 1);

    // A valid hash passes the length check and reaches the provider.
    const auto valid = Call(lua, bridge::Clear, Request(Array({Text("0x0123456789ABCDEF")})));
    EXPECT(Refused(valid, "not_initialized"));

    // One byte too long, a NUL inside, and 128 entries of one 16 MiB string:
    // each is refused before it is copied, with the same message.
    const std::string tooLong = "every request.hashes entry must be a hexadecimal string of at most 18";
    EXPECT(Refused(Call(lua, bridge::Clear, Request(Array({Text(std::string(19, 'A'))}))), tooLong));
    EXPECT(Refused(Call(lua, bridge::Clear,
                        Request(Array({Text(std::string("0x01\0" "23", 7))}))), tooLong));
    const auto huge = std::make_shared<const std::string>(16u * 1024u * 1024u, 'A');
    std::vector<Value> hugeHashes(128, SharedText(huge));
    const auto started = std::chrono::steady_clock::now();
    EXPECT(Refused(Call(lua, bridge::Clear, Request(Array(hugeHashes))), tooLong));
    EXPECT(Refused(Call(lua, bridge::Apply, Request(Array(hugeHashes))), tooLong));
    EXPECT(std::chrono::steady_clock::now() - started < std::chrono::seconds(5));

    // A texture path over 2048 bytes is refused before it is copied too.
    Value request = Request(Array({Text("0x0123456789ABCDEF")}));
    Value compiled = NewTable();
    Value pbr = NewTable();
    Value maps = NewTable();
    maps.table->fields["albedo"] = Text(std::string(3000, 'a'));
    pbr.table->fields["maps"] = maps;
    compiled.table->fields["pbr"] = pbr;
    request.table->fields["compiled"] = compiled;
    EXPECT(Refused(Call(lua, bridge::Apply, request),
                   "texture source path must contain 1 to 2048 UTF-8 bytes"));
    maps.table->fields["albedo"] = Text("garrysmod/data/map.png");
    EXPECT(Refused(Call(lua, bridge::Apply, request), "not_initialized"));

    // An exception thrown while a call holds the bridge lock becomes a failed
    // result, and the lock is released: the next call takes it again.
    lua.throwOnField = "compiled";
    EXPECT(Refused(Call(lua, bridge::Apply, request), "native_exception"));
    lua.throwOnField.clear();
    const auto capabilities = Call(lua, bridge::GetCapabilities, Nil());
    EXPECT(capabilities.size() == 1 && capabilities[0].type == LuaType::Table);
    EXPECT(Refused(Call(lua, bridge::Apply, request), "not_initialized"));

    bridge::UnregisterLua(&lua);
    EXPECT(lua.globals.table->fields.count("AdvMatRTXBridge") == 1 &&
           lua.globals.table->fields["AdvMatRTXBridge"].type == LuaType::Nil);
    if (g_failures != 0) {
        std::cerr << g_failures << " Lua binding check(s) failed\n";
        return 1;
    }
    std::cout << "advmat RTX Lua binding tests passed\n";
    return 0;
}
