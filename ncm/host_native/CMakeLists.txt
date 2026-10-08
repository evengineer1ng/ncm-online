# NCM Host -- the RED4ext plugin that runs NCM 3.0's simulation in single player (L338, KB-385).
# Embeds Lua 5.4 and SQLite (fetched by fetch-deps.ps1); shares RED4ext.SDK from ncm/carrier/third_party.
#   .\ncm\host_native\fetch-deps.ps1
#   .\tools\build-host-native.ps1
cmake_minimum_required(VERSION 3.21)
project(ncm_host VERSION 3.0.0 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

set(TP "${CMAKE_CURRENT_SOURCE_DIR}/third_party")
if (NOT EXISTS "${TP}/lua/src/lua.h" OR NOT EXISTS "${TP}/sqlite/sqlite3.c")
    message(FATAL_ERROR "Lua / SQLite missing. Run .\\ncm\\host_native\\fetch-deps.ps1")
endif()
set(SDK_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../carrier/third_party/RED4ext.SDK")

# Lua 5.4 as a static library (every core file; not the lua/luac front ends)
file(GLOB LUA_SRC "${TP}/lua/src/*.c")
list(REMOVE_ITEM LUA_SRC "${TP}/lua/src/lua.c" "${TP}/lua/src/luac.c")
add_library(ncm_lua STATIC ${LUA_SRC})
target_include_directories(ncm_lua PUBLIC "${TP}/lua/src")
target_compile_definitions(ncm_lua PRIVATE _CRT_SECURE_NO_WARNINGS)

add_library(ncm_sqlite STATIC "${TP}/sqlite/sqlite3.c")
target_include_directories(ncm_sqlite PUBLIC "${TP}/sqlite")
target_compile_definitions(ncm_sqlite PRIVATE SQLITE_THREADSAFE=1 SQLITE_DEFAULT_FOREIGN_KEYS=0 SQLITE_ENABLE_JSON1)

# the VM core, shared by the plugin and the self-test
add_library(ncm_host_vm STATIC src/vm.cpp src/net.cpp)
target_link_libraries(ncm_host_vm PUBLIC ncm_lua ncm_sqlite winhttp ws2_32)
target_compile_definitions(ncm_host_vm PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
target_include_directories(ncm_host_vm PUBLIC src)

# the plugin
if (EXISTS "${SDK_ROOT}/CMakeLists.txt")
    add_subdirectory("${SDK_ROOT}" red4ext-sdk EXCLUDE_FROM_ALL)
    add_library(ncm_host SHARED src/main.cpp)
    target_link_libraries(ncm_host PRIVATE ncm_host_vm RED4ext.SDK)
    target_compile_definitions(ncm_host PRIVATE NCM_HOST_VERSION="${PROJECT_VERSION}" WIN32_LEAN_AND_MEAN NOMINMAX)
    set_target_properties(ncm_host PROPERTIES OUTPUT_NAME "ncm_host" PREFIX "")
endif()

# the self-test: the same VM and the real host/resources, no game (tools/build-host-native.ps1 runs it)
add_executable(ncm_host_selftest tests/selftest.cpp)
target_link_libraries(ncm_host_selftest PRIVATE ncm_host_vm)
