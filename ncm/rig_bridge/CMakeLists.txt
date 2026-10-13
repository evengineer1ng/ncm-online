cmake_minimum_required(VERSION 3.21)
project(ncm_rig_bridge VERSION 0.1.9 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

set(CARRIER_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../carrier")
if (NOT EXISTS "${CARRIER_ROOT}/third_party/RED4ext.SDK/CMakeLists.txt")
    message(FATAL_ERROR "RED4ext.SDK is missing. Initialise the carrier submodules first.")
endif()
if (NOT EXISTS "${CARRIER_ROOT}/third_party/json/nlohmann/json.hpp")
    message(FATAL_ERROR "nlohmann/json is missing. Run .\\ncm\\carrier\\fetch-deps.ps1 first.")
endif()

add_subdirectory("${CARRIER_ROOT}/third_party/RED4ext.SDK" red4ext-sdk EXCLUDE_FROM_ALL)

add_library(ncm_rig_bridge SHARED
    src/main.cpp
    src/log.cpp
    src/config.cpp
    src/state.cpp
    src/direct_input.cpp
    src/ffb_output.cpp
    src/net_guard.cpp
    src/pad/pad_engine.cpp
    src/pad/sdl_input.cpp
    src/pad/xinput_hook.cpp
    src/pad/pad_service.cpp
    src/vehicle_hook.cpp
    src/rtti.cpp
    src/bridge.cpp
)

target_include_directories(ncm_rig_bridge PRIVATE
    src
    "${CARRIER_ROOT}/third_party/json"
)

target_link_libraries(ncm_rig_bridge PRIVATE RED4ext.SDK dinput8 dxguid ws2_32 iphlpapi)
target_compile_definitions(ncm_rig_bridge PRIVATE
    NCM_RIG_BRIDGE_VERSION="${PROJECT_VERSION}"
    WIN32_LEAN_AND_MEAN NOMINMAX DIRECTINPUT_VERSION=0x0800 _CRT_SECURE_NO_WARNINGS)
set_target_properties(ncm_rig_bridge PROPERTIES OUTPUT_NAME "ncm_rig_bridge" PREFIX "")

if (MSVC)
    target_compile_options(ncm_rig_bridge PRIVATE /W4 /EHsc /permissive- /utf-8)
endif()

# A standalone report of what DirectInput can see, for "it does not detect my wheel". Ships beside the
# plugin so a user can answer that question without launching the game.
add_executable(ncm_rig_devices tools/enumerate_devices.cpp)
target_link_libraries(ncm_rig_devices PRIVATE dinput8 dxguid)
target_compile_definitions(ncm_rig_devices PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX DIRECTINPUT_VERSION=0x0800)
if (MSVC)
    target_compile_options(ncm_rig_devices PRIVATE /W4 /EHsc /permissive-)
endif()

include(CTest)
if (BUILD_TESTING)
    add_executable(ncm_rig_mapping_tests tests/mapping_tests.cpp)
    target_include_directories(ncm_rig_mapping_tests PRIVATE src)
    add_test(NAME ncm_rig_mapping COMMAND ncm_rig_mapping_tests)

    add_executable(ncm_rig_pad_tests tests/pad_tests.cpp src/pad/pad_engine.cpp)
    target_include_directories(ncm_rig_pad_tests PRIVATE src "${CARRIER_ROOT}/third_party/json")
    target_compile_definitions(ncm_rig_pad_tests PRIVATE NOMINMAX)
    if (MSVC)
        target_compile_options(ncm_rig_pad_tests PRIVATE /W4 /EHsc /permissive- /utf-8)
    endif()
    add_test(NAME ncm_rig_pad COMMAND ncm_rig_pad_tests)

    add_executable(ncm_rig_feel_tests tests/feel_tests.cpp)
    target_include_directories(ncm_rig_feel_tests PRIVATE src)
    add_test(NAME ncm_rig_feel COMMAND ncm_rig_feel_tests)
endif()
