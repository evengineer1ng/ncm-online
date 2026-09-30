cmake_minimum_required(VERSION 3.21)
project(ncm_broadcast VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

# Third-party headers only. The SDK and nlohmann/json are vendored under the carrier's tree; this plugin shares
# none of the Carrier's, the Rig Bridge's, the Radial's, the Scanner's or Pace's code, state, port range or package.
set(DEPS_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../carrier/third_party")
if (NOT EXISTS "${DEPS_ROOT}/RED4ext.SDK/CMakeLists.txt")
    message(FATAL_ERROR "RED4ext.SDK is missing. Initialise ncm/carrier/third_party first.")
endif()
if (NOT EXISTS "${DEPS_ROOT}/json/nlohmann/json.hpp")
    message(FATAL_ERROR "nlohmann/json is missing. Run .\\ncm\\carrier\\fetch-deps.ps1 first.")
endif()

add_subdirectory("${DEPS_ROOT}/RED4ext.SDK" red4ext-sdk EXCLUDE_FROM_ALL)

add_library(ncm_broadcast SHARED
    src/main.cpp
    src/log.cpp
    src/state.cpp
    src/rtti.cpp
    src/bridge.cpp
)

target_include_directories(ncm_broadcast PRIVATE src "${DEPS_ROOT}/json")
target_link_libraries(ncm_broadcast PRIVATE RED4ext.SDK ws2_32 iphlpapi)
target_compile_definitions(ncm_broadcast PRIVATE
    NCM_BROADCAST_VERSION="${PROJECT_VERSION}"
    WIN32_LEAN_AND_MEAN NOMINMAX _CRT_SECURE_NO_WARNINGS)
set_target_properties(ncm_broadcast PROPERTIES OUTPUT_NAME "ncm_broadcast" PREFIX "")

if (MSVC)
    target_compile_options(ncm_broadcast PRIVATE /W4 /EHsc /permissive-)
endif()

include(CTest)
if (BUILD_TESTING)
    add_executable(ncm_broadcast_state_tests tests/state_tests.cpp src/state.cpp)
    target_include_directories(ncm_broadcast_state_tests PRIVATE src "${DEPS_ROOT}/json")
    target_compile_definitions(ncm_broadcast_state_tests PRIVATE NCM_BROADCAST_VERSION="${PROJECT_VERSION}" NOMINMAX)
    add_test(NAME ncm_broadcast_state COMMAND ncm_broadcast_state_tests)
endif()
