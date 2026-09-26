# NCM Carrier -- the RED4ext plugin that carries drive-model effects, final-command authority and force
# feedback for NCM Online.
#
# Dependencies are deliberately few and deliberately NOT managed by a package manager. SDL2 ships an official
# prebuilt VC package and nlohmann/json is one header; `fetch-deps.ps1` downloads both into third_party/.
# RED4ext.SDK is header-only and vendored as a submodule. Asking a solo developer to install and bootstrap
# vcpkg to build two dependencies was overhead with no payoff.
#
# There is NO ViGEm and no virtual gamepad: the companion needed one because nothing inside the game could
# read a wheel, and this plugin writes the final vehicle command directly (Report 36 section 6.2).
#
#   git submodule update --init --recursive
#   .\ncm\carrier\fetch-deps.ps1
#   .\tools\build-carrier.ps1 -PublishDev
cmake_minimum_required(VERSION 3.21)
project(ncm_carrier VERSION 0.1.16 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

set(SDL2_DIR "${CMAKE_CURRENT_SOURCE_DIR}/third_party/SDL2")
if (NOT EXISTS "${SDL2_DIR}/include/SDL.h")
    message(FATAL_ERROR "SDL2 is missing. Run: .\\ncm\\carrier\\fetch-deps.ps1")
endif()
if (NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/third_party/json/nlohmann/json.hpp")
    message(FATAL_ERROR "nlohmann/json is missing. Run: .\\ncm\\carrier\\fetch-deps.ps1")
endif()

add_subdirectory(third_party/RED4ext.SDK EXCLUDE_FROM_ALL)

add_library(ncm_carrier SHARED
    src/main.cpp
    src/log.cpp
    src/config.cpp
    src/bridge/server.cpp
    src/effects/tweak.cpp
    src/ffb/mixer.cpp
    src/ffb/output.cpp
    src/input/devices.cpp
    src/input/hid_scan.cpp
    src/vehicle/hook.cpp
    src/vehicle/physics_probe.cpp
    src/vehicle/arch_dump.cpp
)

target_include_directories(ncm_carrier PRIVATE
    src
    "${SDL2_DIR}/include"
    "${CMAKE_CURRENT_SOURCE_DIR}/third_party/json"
)

target_link_libraries(ncm_carrier PRIVATE
    RED4ext.SDK
    "${SDL2_DIR}/lib/x64/SDL2.lib"
    ws2_32
    setupapi
    hid
)

target_compile_definitions(ncm_carrier PRIVATE
    NCM_CARRIER_VERSION="${PROJECT_VERSION}"
    WIN32_LEAN_AND_MEAN NOMINMAX _CRT_SECURE_NO_WARNINGS)

# RED4ext loads `<name>.dll` from red4ext/plugins/<name>/.
set_target_properties(ncm_carrier PROPERTIES OUTPUT_NAME "ncm_carrier" PREFIX "")

# The runtime DLL has to travel with the plugin; build-carrier.ps1 picks it up from beside the binary.
add_custom_command(TARGET ncm_carrier POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${SDL2_DIR}/lib/x64/SDL2.dll" "$<TARGET_FILE_DIR:ncm_carrier>")

if (MSVC)
    # Warnings that matter for a plugin which must never throw into the host.
    target_compile_options(ncm_carrier PRIVATE /W4 /EHsc /permissive-)
endif()
