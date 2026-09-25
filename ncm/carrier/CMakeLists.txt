# NCM Carrier -- the RED4ext plugin that carries drive-model effects, final-command authority and force
# feedback for NCM Online.
#
# Dependencies are deliberately few. SDL2 does input and haptics; RED4ext.SDK is header-only and vendored as
# a submodule. There is NO ViGEm and no virtual gamepad: the companion needed one because nothing inside the
# game could read a wheel, and this plugin writes the final vehicle command directly (Report 36 section 6.2).
#
#   git submodule update --init --recursive
#   cmake --preset release && cmake --build --preset release
cmake_minimum_required(VERSION 3.21)
project(ncm_carrier VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

find_package(SDL2 CONFIG REQUIRED)
find_package(nlohmann_json CONFIG REQUIRED)

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
    src/vehicle/hook.cpp
)

target_include_directories(ncm_carrier PRIVATE src)
target_link_libraries(ncm_carrier PRIVATE RED4ext.SDK SDL2::SDL2 nlohmann_json::nlohmann_json ws2_32)
target_compile_definitions(ncm_carrier PRIVATE
    NCM_CARRIER_VERSION="${PROJECT_VERSION}"
    WIN32_LEAN_AND_MEAN NOMINMAX _CRT_SECURE_NO_WARNINGS)

# RED4ext loads `<name>.dll` from red4ext/plugins/<name>/.
set_target_properties(ncm_carrier PROPERTIES OUTPUT_NAME "ncm_carrier" PREFIX "")

if (MSVC)
    # /EHsc, and warnings that matter for a plugin that must never throw into the host.
    target_compile_options(ncm_carrier PRIVATE /W4 /EHsc /permissive-)
endif()
