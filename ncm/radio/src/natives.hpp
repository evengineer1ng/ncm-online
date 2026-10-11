#pragma once

#include <string>

namespace ncm::radio {
class Player;
namespace natives {
void attach(Player* player, const std::wstring& directory);
void registerNatives();
}
}
