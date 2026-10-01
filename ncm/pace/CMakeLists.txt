cmake_minimum_required(VERSION 3.21)
project(ncm_pace VERSION 0.5.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

# Third-party headers only. The SDK and nlohmann/json are vendored under the carrier's tree; this plugin shares
# none of the Carrier's, the Rig Bridge's, the Radial's or the Scanner's code, state, port range or package.
set(DEPS_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../carrier/third_party")
if (NOT EXISTS "${DEPS_ROOT}/RED4ext.SDK/CMakeLists.txt")
    message(FATAL_ERROR "RED4ext.SDK is missing. Initialise ncm/carrier/third_party first.")
endif()
if (NOT EXISTS "${DEPS_ROOT}/json/nlohmann/json.hpp")
    message(FATAL_ERROR "nlohmann/json is missing. Run .\\ncm\\carrier\\fetch-deps.ps1 first.")
endif()

add_subdirectory("${DEPS_ROOT}/RED4ext.SDK" red4ext-sdk EXCLUDE_FROM_ALL)

add_library(ncm_pace SHARED
    src/main.cpp
    src/log.cpp
    src/state.cpp
    src/speed_profile.cpp
    src/road_graph.cpp
    src/road_loader.cpp
    src/rtti.cpp
    src/bridge.cpp
)

target_include_directories(ncm_pace PRIVATE src "${DEPS_ROOT}/json")
target_link_libraries(ncm_pace PRIVATE RED4ext.SDK ws2_32 iphlpapi)
target_compile_definitions(ncm_pace PRIVATE
    NCM_PACE_VERSION="${PROJECT_VERSION}"
    WIN32_LEAN_AND_MEAN NOMINMAX _CRT_SECURE_NO_WARNINGS)
set_target_properties(ncm_pace PROPERTIES OUTPUT_NAME "ncm_pace" PREFIX "")

if (MSVC)
    target_compile_options(ncm_pace PRIVATE /W4 /EHsc /permissive-)
endif()

include(CTest)
if (BUILD_TESTING)
    add_executable(ncm_pace_state_tests tests/state_tests.cpp src/state.cpp src/speed_profile.cpp src/road_graph.cpp)
    target_include_directories(ncm_pace_state_tests PRIVATE src "${DEPS_ROOT}/json")
    target_compile_definitions(ncm_pace_state_tests PRIVATE NCM_PACE_VERSION="${PROJECT_VERSION}" NOMINMAX)
    add_test(NAME ncm_pace_state COMMAND ncm_pace_state_tests)
endif()
