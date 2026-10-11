cmake_minimum_required(VERSION 3.21)
project(ncm_snowglobe VERSION 0.0.6 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

# Third-party headers only, vendored under the carrier's tree; this plugin shares none of the Carrier's code, state
# or package (feedback: new features, new mods).
set(DEPS_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../carrier/third_party")
if (NOT EXISTS "${DEPS_ROOT}/RED4ext.SDK/CMakeLists.txt")
    message(FATAL_ERROR "RED4ext.SDK is missing. Initialise ncm/carrier/third_party first.")
endif()
if (NOT EXISTS "${DEPS_ROOT}/json/nlohmann/json.hpp")
    message(FATAL_ERROR "nlohmann/json is missing. Run .\\ncm\\carrier\\fetch-deps.ps1 first.")
endif()

add_subdirectory("${DEPS_ROOT}/RED4ext.SDK" red4ext-sdk EXCLUDE_FROM_ALL)

add_library(ncm_snowglobe SHARED
    src/main.cpp
    src/log.cpp
    src/seam.cpp
    src/natives.cpp
)

target_include_directories(ncm_snowglobe PRIVATE src "${DEPS_ROOT}/json")
target_link_libraries(ncm_snowglobe PRIVATE RED4ext.SDK Xinput)
target_compile_definitions(ncm_snowglobe PRIVATE
    NCM_SNOWGLOBE_VERSION="${PROJECT_VERSION}"
    WIN32_LEAN_AND_MEAN NOMINMAX _CRT_SECURE_NO_WARNINGS)
set_target_properties(ncm_snowglobe PROPERTIES OUTPUT_NAME "ncm_snowglobe" PREFIX "")

if (MSVC)
    target_compile_options(ncm_snowglobe PRIVATE /W4 /EHsc /permissive-)
endif()
