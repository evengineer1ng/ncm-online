#include "puppet_guard_policy.hpp"
#include <cstdio>

int main()
{
    using namespace ncm::pace::puppet_guard;
    int calls = 0, blocks = 0, failures = 0;
    bool answer = true;
    const BorrowedHandle* received = nullptr;
    auto original = [&](const BorrowedHandle* h) { ++calls; received = h; return answer; };
    auto blocked = [&] { ++blocks; };
    auto check = [&](bool pass, const char* what) { if (!pass) { ++failures; std::printf("FAIL %s\n", what); } };
    BorrowedHandle empty{};
    int object = 1;
    BorrowedHandle valid{&object, nullptr};
    check(!dispatch(&empty, 42, 42, original, blocked) && calls == 0 && blocks == 1,
          "captured failed-cast handle bypasses native dereference");
    check(!dispatch(nullptr, 42, 42, original, blocked) && calls == 0 && blocks == 2,
          "null handle pointer at the same caller is rejected");
    check(dispatch(&valid, 42, 42, original, blocked) && calls == 1 && received == &valid && blocks == 2,
          "valid puppet handle and true result pass through unchanged");
    answer = false;
    check(!dispatch(&valid, 42, 42, original, blocked) && calls == 2 && blocks == 2,
          "valid puppet false result preserved");
    answer = true;
    check(dispatch(&empty, 43, 42, original, blocked) && calls == 3 && received == &empty && blocks == 2,
          "other call sites retain original behavior");
    std::printf("puppet guard: 5 checks, %d failures\n", failures);
    return failures ? 1 : 0;
}
